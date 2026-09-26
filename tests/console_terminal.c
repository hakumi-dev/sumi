#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <locale.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif

/* PTY process control is not exposed by Neri's host API. Exercise the public CLI. */
static int terminal;
static pid_t child;
static char transcript[65536];
static int driven;

static void fail(const char *message) {
    fprintf(stderr, "%s\n%s\n", message, transcript);
    close(terminal);
    kill(-child, SIGKILL);
    waitpid(child, NULL, 0);
    exit(1);
}

static void send_keys(const char *keys) {
    /* libedit can display its prompt before switching the terminal to editing
       mode. Wait for that transition so the kernel does not consume Backspace. */
    int editing = 0;
    for (int attempt = 0; attempt < 300; attempt++) {
        struct termios mode;
        if (tcgetattr(terminal, &mode) != 0) fail("Cannot inspect terminal mode");
        if (!(mode.c_lflag & ICANON)) {
            editing = 1;
            break;
        }
        poll(NULL, 0, 10);
    }
    if (!editing) fail("Console did not enter terminal editing mode");
    size_t remaining = strlen(keys);
    while (remaining) {
        ssize_t count = write(terminal, keys, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) fail("Cannot send terminal input");
        remaining -= (size_t)count;
        keys += count;
    }
}

static int64_t monotonic_milliseconds(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) fail("Cannot read monotonic clock");
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static void prompt_with_budget(const char *expected, int budget_ms) {
    const int64_t deadline = monotonic_milliseconds() + budget_ms;
    /* '~' waits for displayed text and a quiet interval beyond the editor debounce. */
    int settled = driven && expected[0] == '~';
    int matched = 0;
    int display_only = driven && (expected[0] == '@' || settled);
    if (display_only) ++expected;
    size_t used = 0;
    transcript[0] = '\0';
    for (;;) {
        int64_t remaining = deadline - monotonic_milliseconds();
        if (remaining <= 0) break;
        int wait_ms = remaining < 100 ? (int)remaining : 100;
        struct pollfd ready = {terminal, POLLIN, 0};
        int status = poll(&ready, 1, wait_ms);
        if (status < 0 && errno == EINTR) continue;
        if (status < 0) fail("Cannot poll console terminal");
        if (!status) {
            if (settled && matched && wait_ms == 100) {
                fputs(transcript, stdout);
                return;
            }
            continue;
        }
        ssize_t count = read(terminal, transcript + used, sizeof(transcript) - used - 1);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) fail("Console closed before the prompt");
        used += (size_t)count;
        transcript[used] = '\0';
        /* Editing redisplays the prompt; only accept it after the expected result. */
        /* Match visible text even when a colored prompt resets before its space. */
        char visible[sizeof(transcript)];
        size_t source = 0, target = 0;
        while (source < used) {
            if (transcript[source] == '\033' && source + 1 < used && transcript[source + 1] == '[') {
                source += 2;
                while (source < used) {
                    unsigned char c = (unsigned char)transcript[source++];
                    if (c >= 0x40 && c <= 0x7e) break;
                }
            } else {
                visible[target++] = transcript[source++];
            }
        }
        visible[target] = '\0';
        char *result = strstr(visible, expected);
        int prompt_only = driven &&
            (!strcmp(expected, "sumi> ") || !strcmp(expected, " ...> "));
        if (result && (display_only || prompt_only || strstr(result + strlen(expected), "sumi> "))) {
            if (driven && !strcmp(expected, "Sumi console")) {
                const char *generation = strstr(transcript, "Generating native code (");
                const char *counts = generation ? strstr(generation, "): ") : NULL;
                const char *cleared = generation ? strstr(generation, "\r\033[2K") : NULL;
                const char *title = strstr(transcript, "Sumi console");
                if (cleared && title) {
                    const char *next = cleared;
                    while (next < title) {
                        const char *later = strstr(next + 1, "\r\033[2K");
                        if (!later || later >= title) break;
                        cleared = later;
                        next = later;
                    }
                }
                if (!generation || !counts || !cleared || !title || cleared >= title)
                    fail("Startup progress must show native function counts and clear before the console opens");
                if (memchr(generation, '\n', (size_t)(cleared - generation)))
                    fail("Startup progress must stay on one terminal line");
            }
            matched = 1;
            if (settled) continue;
            if (driven) fputs(transcript, stdout);
            return;
        }
        if (used == sizeof(transcript) - 1) fail("Console transcript overflow");
    }
    fail("Console prompt timed out");
}

static void prompt(const char *expected) {
    /* Scenarios mark compilation explicitly; ordinary interaction stays bounded. */
    int compilation = driven && expected[0] == '!';
    prompt_with_budget(expected + compilation, compilation ? 120000 : 30000);
}

/* Neri supplies test scenarios. This bridge only owns PTY I/O and synchronization.
   Input frames: little-endian uint32 length followed by bytes, bounded to 4096.
   Expected prefixes: '!' compilation budget, '@' display only, '~' settled display.
   A compilation prefix may precede a display prefix. */
static int frame(char *output) {
    unsigned char length[4];
    if (fread(length, 1, 4, stdin) != 4) return 0;
    uint32_t size = (uint32_t)length[0] | ((uint32_t)length[1] << 8) |
                    ((uint32_t)length[2] << 16) | ((uint32_t)length[3] << 24);
    if (size > 4096 || fread(output, 1, size, stdin) != size) fail("Invalid PTY frame");
    output[size] = '\0';
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) return 2;
    driven = argc == 4 && strcmp(argv[3], "--drive") == 0;
    if (argc == 4 && !driven) return 2;
    /* The child initializes LC_CTYPE from its environment for Unicode editing. */
    const char *utf8_locale = NULL;
    const char *candidates[] = {"C.UTF-8", "C.utf8", "en_US.UTF-8"};
    for (size_t index = 0; index < sizeof(candidates) / sizeof(candidates[0]); index++) {
        if (setlocale(LC_CTYPE, candidates[index]) != NULL) {
            utf8_locale = candidates[index];
            break;
        }
    }
    if (utf8_locale == NULL) {
        fputs("Console Unicode contracts require an available UTF-8 locale\n", stderr);
        return 1;
    }
    struct winsize size = {24, 100, 0, 0};
    child = forkpty(&terminal, NULL, NULL, &size);
    if (child < 0) return 1;
    if (child == 0) {
        setenv("TERM", "xterm-256color", 1);
        if (setenv("LC_ALL", utf8_locale, 1) != 0) {
            perror("Cannot configure console UTF-8 locale");
            _exit(1);
        }
        unsetenv("SUMI_CONSOLE_TIMINGS");
        execl(argv[1], argv[1], "c", "--project", argv[2], (char *)NULL);
        _exit(127);
    }
    /* Startup includes compilation; scenarios mark any later compilation explicitly. */
    prompt_with_budget("Sumi console", 120000);
    if (driven) {
        char keys[4097], expected[4097];
        while (frame(keys)) {
            if (!frame(expected)) fail("Missing expected PTY frame");
            send_keys(keys);
            if (!*expected) break;
            prompt(expected);
        }
    } else {
    send_keys("console::println(\"history-a\")\n");
    prompt("\r\nhistory-a\r\n");
    send_keys("console::println(\"history-b\")\n");
    prompt("\r\nhistory-b\r\n");
    send_keys("\033[A\033[A\033[B\n");
    prompt("\r\nhistory-b\r\n");
    send_keys("console::println(\"ac\")\033[D\033[D\033[Db\033[Cd\n");
    prompt("\r\nabcd\r\n");
    send_keys("console::println(\"á水\")\033[D\033[D\033[D\177ñ\033[C!\n");
    prompt("\r\nñ水!\r\n");
    send_keys("console::println(\"draft\")\033[A\033[B\n");
    prompt("\r\ndraft\r\n");
    send_keys("\004");
    }
    int status = 0;
    for (int attempt = 0; attempt < 100; attempt++) {
        if (waitpid(child, &status, WNOHANG) == child) {
            close(terminal);
            if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return 1;
            puts("Sumi terminal editing contracts passed");
            return 0;
        }
        /* Keep draining the PTY while the CLI and its child exit. macOS can
           defer process teardown until pending terminal output is consumed. */
        struct pollfd ready = {terminal, POLLIN, 0};
        if (poll(&ready, 1, 100) > 0) {
            char tail[4096];
            (void)read(terminal, tail, sizeof(tail));
        }
    }
    fail("EOF did not close the console");
}

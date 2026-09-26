#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <limits.h>
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

static int terminal = -1;
static pid_t child = -1;
static char transcript[262144];
static size_t used;

static void stop_child(void) {
    if (terminal >= 0) close(terminal);
    terminal = -1;
    if (child > 0) {
        kill(-child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        child = -1;
    }
}

static int fail(const char *message) {
    fprintf(stderr, "%s\n", message);
    if (used) fwrite(transcript, 1, used, stderr);
    stop_child();
    return 1;
}

static int append_output(void) {
    if (used == sizeof(transcript) - 1) return -1;
    ssize_t count = read(terminal, transcript + used, sizeof(transcript) - used - 1);
    if (count < 0 && errno == EINTR) return 1;
    if (count < 0 && errno == EIO) return 0;
    if (count < 0) return -1;
    if (count == 0) return 0;
    used += (size_t)count;
    transcript[used] = '\0';
    return 1;
}

static int collect_until_exit(int *status) {
    struct timespec start;
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) return 0;
    const time_t deadline = start.tv_sec + 60;
    for (;;) {
        struct timespec now;
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec >= deadline) return 0;
        struct pollfd ready = {terminal, POLLIN, 0};
        int polled = terminal >= 0 ? poll(&ready, 1, 100) : poll(NULL, 0, 100);
        if (polled < 0 && errno == EINTR) continue;
        if (polled < 0) return 0;
        if (polled > 0 && (ready.revents & (POLLIN | POLLHUP))) {
            int read_status = append_output();
            if (read_status < 0) return 0;
            if (read_status == 0) {
                close(terminal);
                terminal = -1;
            }
        }
        pid_t result = waitpid(child, status, WNOHANG);
        if (result == child) {
            child = -1;
            /* Drain output already queued after process exit without polling EOF forever. */
            while (terminal >= 0 && poll(&ready, 1, 0) > 0 && (ready.revents & (POLLIN | POLLHUP))) {
                int read_status = append_output();
                if (read_status < 0) return 0;
                if (read_status == 0) {
                    close(terminal);
                    terminal = -1;
                }
            }
            return 1;
        }
        if (result < 0 && errno != EINTR) return 0;
    }
    return 0;
}

static const char *last_progress_clear(const char *end) {
    const char *found = NULL;
    const char *cursor = transcript;
    while ((cursor = strstr(cursor, "\r\033[2K")) != NULL && cursor < end) {
        found = cursor;
        ++cursor;
    }
    return found;
}

static int check_startup(const char *mode, int status, const char *artifact) {
    const char *ready = strstr(transcript, artifact ? artifact : "STARTUP_READY");
    char canonical[PATH_MAX];
    if (artifact && realpath(artifact, canonical)) {
        const char *canonical_ready = strstr(transcript, canonical);
        if (canonical_ready && (!ready || canonical_ready > ready)) ready = canonical_ready;
    }
    if (!strcmp(mode, "error")) {
        if (!WIFEXITED(status) || WEXITSTATUS(status) == 0)
            return fail("Startup error did not preserve a failing exit status");
        const char *diagnostic = strstr(transcript, "missingStartupFunction");
        if (!diagnostic) diagnostic = strstr(transcript, "TypeCheck");
        const char *clear = last_progress_clear(diagnostic ? diagnostic : transcript + used);
        if (!diagnostic || !clear || clear >= diagnostic)
            return fail("Startup progress must clear before the startup diagnostic");
        const char *phase = strstr(transcript, "Loading application project...");
        if (phase) {
            for (const char *cursor = phase; cursor < clear; ++cursor) {
                if (*cursor == '\n') return fail("Startup progress must remain on one terminal line");
            }
        }
        return 0;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return fail("Application command did not exit successfully");
    if (!ready) return fail(artifact ? "Build did not announce its artifact path" : "Server fixture did not reach STARTUP_READY");

    const char *phase = strstr(transcript, "Loading application project...");
    if (!phase) return fail("Startup did not report project loading");
    const char *analyze = strstr(phase, "Analyzing ");
    const char *source_count = analyze ? strstr(analyze, " application sources...") : NULL;
    if (!analyze || !source_count || source_count >= ready)
        return fail("Startup did not report the analyzed application source count");
    if (!strcmp(mode, "warm")) {
        if (!strstr(analyze, "Reusing compiled module.")) return fail("Warm startup did not report compiled module reuse");
    } else {
        const char *native = strstr(analyze, "Generating native code (");
        if (!native) return fail("Cold startup did not report native code generation");
        const char *counts = strstr(native, "): ");
        if (!counts || counts >= ready || counts[3] == '\0' || counts[3] == '\r')
            return fail("Cold startup must include native progress counts and source detail");
    }
    const char *clear = last_progress_clear(ready);
    if (!clear || clear >= ready)
        return fail(artifact ? "Build progress must clear before its artifact path" : "Startup progress must clear before STARTUP_READY");
    for (const char *cursor = phase; cursor < clear; ++cursor) {
        if (*cursor == '\n') return fail("Startup progress must remain on one terminal line");
    }
    return 0;
}

int main(int argc, char **argv) {
    if ((argc != 4 && argc != 5 && argc != 6) || (strcmp(argv[3], "cold") && strcmp(argv[3], "warm") && strcmp(argv[3], "error")) ||
        (argc == 5 && strcmp(argv[4], "t")) || (argc == 6 && strcmp(argv[4], "b"))) {
        fprintf(stderr, "Usage: %s <cli> <project> <cold|warm|error> [t | b <artifact>]\n", argv[0]);
        return 2;
    }
    const char *mode = argv[3];
    const char *artifact = argc == 6 ? argv[5] : NULL;
    struct winsize size = {24, 100, 0, 0};
    child = forkpty(&terminal, NULL, NULL, &size);
    if (child < 0) return 1;
    if (child == 0) {
        setenv("TERM", "xterm-256color", 1);
        setenv("LC_ALL", "en_US.UTF-8", 1);
        if (artifact)
            execl(argv[1], argv[1], "b", "--project", argv[2], "--output", artifact, (char *)NULL);
        else if (argc == 5)
            execl(argv[1], argv[1], "t", "--project", argv[2], (char *)NULL);
        else
            execl(argv[1], argv[1], "s", "--project", argv[2], (char *)NULL);
        _exit(127);
    }
    int status = 0;
    if (!collect_until_exit(&status)) return fail("Server startup exceeded 60 seconds or PTY output failed");
    if (used) fwrite(transcript, 1, used, stdout);
    int result = check_startup(mode, status, artifact);
    close(terminal);
    terminal = -1;
    return result;
}

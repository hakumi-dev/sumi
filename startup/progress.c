#define _XOPEN_SOURCE 700
#include <locale.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <wchar.h>

static int progress_visible;

int64_t sumi_startup_terminal(void) {
    const char *term = getenv("TERM");
    return isatty(STDIN_FILENO) && isatty(STDOUT_FILENO) && term && strcmp(term, "dumb") != 0;
}

int64_t sumi_startup_progress(const unsigned char *text, int64_t length) {
    if (!sumi_startup_terminal() || !text || length < 0 || length > 4096) return 0;
    setlocale(LC_CTYPE, "");
    struct winsize size = {0};
    ioctl(STDOUT_FILENO, TIOCGWINSZ, &size);
    int width = size.ws_col > 0 ? size.ws_col - 1 : 79;
    int used = 0;
    size_t offset = 0;
    mbstate_t state = {0};
    fputs("\r\033[2K", stdout);
    while (offset < (size_t)length) {
        wchar_t character;
        size_t count = mbrtowc(&character, (const char *)text + offset, (size_t)length - offset, &state);
        if (count == (size_t)-1 || count == (size_t)-2 || !count) {
            memset(&state, 0, sizeof(state));
            if (used < width) { fputc('?', stdout); ++used; }
            ++offset;
            continue;
        }
        int columns = wcwidth(character);
        if (character < 32 || character == 127 || columns < 0) {
            if (used < width) { fputc('?', stdout); ++used; }
        } else if (used + columns <= width) {
            fwrite(text + offset, 1, count, stdout);
            used += columns;
        } else {
            break;
        }
        offset += count;
    }
    fflush(stdout);
    progress_visible = 1;
    return 1;
}

int64_t sumi_startup_progress_clear(void) {
    if (!progress_visible) return 0;
    fputs("\r\033[2K", stdout);
    fflush(stdout);
    progress_visible = 0;
    return 1;
}

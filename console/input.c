#define _XOPEN_SOURCE 700
#include <histedit.h>
#include <locale.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <wchar.h>

/* Terminal I/O and libedit only. Neri owns candidates, selection and text edits. */
static EditLine *editor;
static History *input_history;
static char label[4097];
static int active, input_event, queued;
static int menu_active, menu_rows, menu_tail, menu_column;
static int pending_byte = -1;
static int input_eof;
static void edit_key(const char *keys);

static int read_byte(void) {
    if (pending_byte >= 0) { int value = pending_byte; pending_byte = -1; return value; }
    unsigned char value;
    ssize_t count;
    do { count = read(STDIN_FILENO, &value, 1); } while (count < 0 && errno == EINTR);
    return count == 1 ? value : -1;
}

/* Disambiguate standalone Escape from terminal key sequences without blocking
   dismissal on a second key. libc supplies locale-aware UTF-8 decoding. */
static int terminal_character(EditLine *edit, wchar_t *output) {
    (void)edit;
    mbstate_t state = {0};
    for (;;) {
        int value = read_byte();
        if (value < 0) { input_eof = 1; return 0; }
        if (value == 4) {
            const LineInfo *line = el_line(edit);
            if (line->buffer == line->lastchar) input_eof = 1;
        }
        if (value == 27 && menu_active) {
            struct pollfd input = {STDIN_FILENO, POLLIN, 0};
            int ready;
            do { ready = poll(&input, 1, 50); } while (ready < 0 && errno == EINTR);
            if (ready > 0) pending_byte = read_byte();
            if (pending_byte != '[' && pending_byte != 'O') { *output = 7; return 1; }
        }
        char byte = (char)value;
        size_t count = mbrtowc(output, &byte, 1, &state);
        if (count == (size_t)-2) continue;
        if (count == (size_t)-1) { memset(&state, 0, sizeof(state)); continue; }
        return 1;
    }
}

static const char *prompt(EditLine *edit) { (void)edit; return label; }
static unsigned char complete_key(EditLine *edit, int key) {
    (void)edit; (void)key; input_event = 2; return CC_NORM;
}
static unsigned char accept_key(EditLine *edit, int key) {
    (void)edit; (void)key; input_event = 5; return CC_NORM;
}
static unsigned char dismiss_key(EditLine *edit, int key) {
    (void)edit; (void)key; input_event = 6; return CC_NORM;
}
static unsigned char down_key(EditLine *edit, int key) {
    (void)key;
    if (menu_active) input_event = 3;
    else { el_push(edit, "\030\016"); queued = 1; }
    return CC_NORM;
}
static unsigned char up_key(EditLine *edit, int key) {
    (void)key;
    if (menu_active) input_event = 4;
    else { el_push(edit, "\030\020"); queued = 1; }
    return CC_NORM;
}

static void menu_keys(int enabled) {
    menu_active = enabled;
    el_set(editor, EL_BIND, "^M", enabled ? "sumi-accept" : "ed-newline", NULL);
    el_set(editor, EL_BIND, "^J", enabled ? "sumi-accept" : "ed-newline", NULL);
}

static void prompt_style(void) {
    int literal = 0;
    for (const char *p = label; *p; ++p) {
        if (*p == 1) literal = !literal;
        else if (literal) putchar(*p);
    }
}

static void erase_menu(void) {
    if (!menu_rows) return;
    if (menu_tail) printf("\033[%dB", menu_tail);
    for (int i = 0; i < menu_rows; ++i) fputs("\033[1B\r\033[2K", stdout);
    printf("\033[%dA\r", menu_rows + menu_tail);
    if (menu_column) printf("\033[%dC", menu_column);
    menu_rows = 0;
    prompt_style();
    fflush(stdout);
}

void sumi_console_initialize(void) {
    setlocale(LC_CTYPE, "");
    editor = el_init("sumi", stdin, stdout, stderr);
    input_history = history_init();
    if (!editor || !input_history) return;
    HistEvent event;
    history(input_history, &event, H_SETSIZE, 500);
    el_set(editor, EL_HIST, history, input_history);
    el_set(editor, EL_EDITOR, "emacs");
    el_set(editor, EL_SIGNAL, 1);
    el_wset(editor, EL_GETCFN, terminal_character);
    el_set(editor, EL_PROMPT_ESC, prompt, 1);
    el_set(editor, EL_ADDFN, "sumi-complete", "Complete", complete_key);
    el_set(editor, EL_ADDFN, "sumi-accept", "Insert selected completion", accept_key);
    el_set(editor, EL_ADDFN, "sumi-dismiss", "Dismiss completions", dismiss_key);
    el_set(editor, EL_ADDFN, "sumi-down", "Next completion or history", down_key);
    el_set(editor, EL_ADDFN, "sumi-up", "Previous completion or history", up_key);
    el_set(editor, EL_BIND, "^I", "sumi-complete", NULL);
    el_set(editor, EL_BIND, "^G", "sumi-dismiss", NULL);
    el_set(editor, EL_BIND, "^[[A", "sumi-up", NULL);
    el_set(editor, EL_BIND, "^[[B", "sumi-down", NULL);
    el_set(editor, EL_BIND, "^[OA", "sumi-up", NULL);
    el_set(editor, EL_BIND, "^[OB", "sumi-down", NULL);
    /* Keep standard cursor/editing sequences while Up/Down can navigate menus. */
    el_set(editor, EL_BIND, "^[[C", "ed-next-char", NULL);
    el_set(editor, EL_BIND, "^[[D", "ed-prev-char", NULL);
    el_set(editor, EL_BIND, "^[OC", "ed-next-char", NULL);
    el_set(editor, EL_BIND, "^[OD", "ed-prev-char", NULL);
    el_set(editor, EL_BIND, "^[[H", "ed-move-to-beg", NULL);
    el_set(editor, EL_BIND, "^[[F", "ed-move-to-end", NULL);
    el_set(editor, EL_BIND, "^[[3~", "ed-delete-next-char", NULL);
    el_set(editor, EL_BIND, "^X^A", "ed-move-to-beg", NULL);
    el_set(editor, EL_BIND, "^X^K", "ed-kill-line", NULL);
    el_set(editor, EL_BIND, "^X^B", "ed-prev-char", NULL);
    el_set(editor, EL_BIND, "^X^N", "ed-next-history", NULL);
    el_set(editor, EL_BIND, "^X^P", "ed-prev-history", NULL);
    el_set(editor, EL_BIND, "^X^R", "ed-redisplay", NULL);
}

int64_t sumi_console_terminal(void) {
    const char *term = getenv("TERM");
    return isatty(STDIN_FILENO) && isatty(STDOUT_FILENO) && term && strcmp(term, "dumb") != 0;
}
int64_t sumi_console_event(void) { return input_event; }
void sumi_console_refresh(void) { if (active) edit_key("\030\022"); }
int64_t sumi_console_cursor(void) {
    const LineInfo *line = el_line(editor);
    return line->cursor - line->buffer;
}

/* Width, clipping and cursor movement are native terminal capabilities. */
static int columns(const char *text, size_t length) {
    mbstate_t state = {0};
    int width = 0;
    while (length) {
        wchar_t c;
        size_t n = mbrtowc(&c, text, length, &state);
        if (n == (size_t)-1 || n == (size_t)-2 || !n) break;
        int w = wcwidth(c);
        width += w > 0 ? w : 0;
        text += n; length -= n;
    }
    return width;
}

int64_t sumi_console_menu(const unsigned char *text, int64_t length) {
    if (!active || length < 0 || length > 65536) return 0;
    erase_menu();
    menu_keys(length != 0);
    if (!length) return 1;
    struct winsize size = {0};
    ioctl(STDOUT_FILENO, TIOCGWINSZ, &size);
    int width = size.ws_col > 1 ? size.ws_col : 80;
    int limit = size.ws_row > 3 ? size.ws_row - 2 : 1;
    if (limit > 8) limit = 8;
    int label_width = 0, literal = 0;
    for (const char *p = label; *p; ++p) {
        if (*p == 1) literal = !literal;
        else if (!literal) ++label_width; /* Sumi prompts have ASCII visible text. */
    }
    const LineInfo *line = el_line(editor);
    int cursor = label_width + columns(line->buffer, (size_t)(line->cursor - line->buffer));
    int end = label_width + columns(line->buffer, (size_t)(line->lastchar - line->buffer));
    menu_column = cursor % width;
    menu_tail = end / width - cursor / width;
    if (menu_tail) printf("\033[%dB", menu_tail);
    size_t offset = 0;
    while (offset < (size_t)length && menu_rows < limit) {
        fputs("\r\n\033[2K", stdout);
        ++menu_rows;
        int used = 0;
        mbstate_t state = {0};
        while (offset < (size_t)length && text[offset] != '\n') {
            /* Only SGR is permitted in supplied menu styling. */
            if (text[offset] == 27 && offset + 1 < (size_t)length && text[offset + 1] == '[') {
                size_t start = offset;
                offset += 2;
                while (offset < (size_t)length && ((text[offset] >= '0' && text[offset] <= '9') || text[offset] == ';')) ++offset;
                if (offset < (size_t)length && text[offset] == 'm') {
                    ++offset;
                    fwrite(text + start, 1, offset - start, stdout);
                }
                continue;
            }
            wchar_t c;
            size_t n = mbrtowc(&c, (const char *)text + offset, (size_t)length - offset, &state);
            if (n == (size_t)-1 || n == (size_t)-2 || !n) { ++offset; memset(&state, 0, sizeof(state)); continue; }
            int w = wcwidth(c);
            if (w >= 0 && used + w < width) fwrite(text + offset, 1, n, stdout);
            used += w > 0 ? w : 0;
            offset += n;
        }
        if (offset < (size_t)length) ++offset;
    }
    printf("\033[%dA\r", menu_rows + menu_tail);
    if (menu_column) printf("\033[%dC", menu_column);
    prompt_style();
    fflush(stdout);
    return 1;
}

static void edit_key(const char *keys) {
    int count;
    el_push(editor, keys);
    (void)el_gets(editor, &count);
}

int64_t sumi_console_replace(const unsigned char *text, int64_t length, int64_t cursor) {
    if (!active || length < 0 || length > 1048576 || cursor < 0 || cursor > length) return 0;
    if (cursor < length && (text[cursor] & 0xc0) == 0x80) return 0;
    char *copy = malloc((size_t)length + 1);
    if (!copy) return 0;
    memcpy(copy, text, (size_t)length);
    copy[length] = '\0';
    if (memchr(copy, '\0', (size_t)length) || memchr(copy, '\n', (size_t)length)) { free(copy); return 0; }
    erase_menu();
    menu_keys(0);
    edit_key("\030\001");
    edit_key("\030\013");
    int inserted = length == 0 ? 0 : el_insertstr(editor, copy);
    for (int64_t i = cursor; i < length; ++i)
        if ((text[i] & 0xc0) != 0x80) edit_key("\030\002");
    free(copy);
    edit_key("\030\022");
    return inserted >= 0;
}

static int waiting_input(int timeout) {
    if (pending_byte >= 0) return 1;
    struct pollfd input = {STDIN_FILENO, POLLIN, 0};
    int result;
    do { result = poll(&input, 1, timeout); } while (result < 0 && errno == EINTR);
    return result > 0;
}

int64_t sumi_console_readline(const unsigned char *text, int64_t text_length, unsigned char *output, int64_t capacity) {
    if (!editor || !input_history || text_length < 0 || text_length > 4096 || capacity < 0) return -3;
    if (!active) {
        memcpy(label, text, (size_t)text_length);
        label[text_length] = '\0';
        for (int64_t i = 0; i < text_length; ++i) if (label[i] == 2) label[i] = 1;
        el_set(editor, EL_UNBUFFERED, 1);
        active = 1;
    }
    input_event = 0;
    for (;;) {
        if (menu_rows) { (void)waiting_input(-1); erase_menu(); }
        int count = 0;
        queued = 0;
        input_eof = 0;
        errno = 0;
        const char *line = el_gets(editor, &count);
        if (queued) continue;
        /* Older libedit reports count=-1, errno=0 after clearing an empty line. */
        if (!input_event && (input_eof || (count < 0 && errno != 0) || (line && count == 1 && line[0] == 4))) {
            erase_menu(); menu_keys(0);
            el_set(editor, EL_UNBUFFERED, 0); active = 0;
            return -1;
        }
        if (!input_event && line && count > 0 && (line[count - 1] == '\n' || line[count - 1] == '\r')) {
            size_t length = (size_t)count - 1;
            int64_t result = length > (size_t)capacity ? -2 : (int64_t)length;
            if (result >= 0) {
                memcpy(output, line, length);
                if (length) {
                    HistEvent event;
                    char *entry = malloc(length + 1);
                    if (entry) {
                        memcpy(entry, line, length); entry[length] = '\0';
                        history(input_history, &event, H_ENTER, entry); free(entry);
                    }
                }
            }
            erase_menu(); menu_keys(0);
            el_set(editor, EL_UNBUFFERED, 0); active = 0;
            return result;
        }
        if (!input_event) {
            menu_keys(0);
            if (waiting_input(60)) continue; /* Coalesce typing/paste bursts. */
            input_event = 1;
        }
        const LineInfo *current = el_line(editor);
        size_t length = (size_t)(current->lastchar - current->buffer);
        if (length > (size_t)capacity) { input_event = 0; continue; }
        memcpy(output, current->buffer, length);
        return -5 - (int64_t)length;
    }
}

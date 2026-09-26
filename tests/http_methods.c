#define _POSIX_C_SOURCE 200809L
/* Native wire-level contracts; Neri currently exposes server-side HTTP sockets. */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "HTTP contract failed at line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
#define CAPACITY (2U * 1024U * 1024U)
struct response { int status; char *data; char *body; size_t length; };
static int port;

static void send_all(int fd, const char *data, size_t length) {
    while (length) {
        ssize_t count = send(fd, data, length, 0);
        if (count < 0 && errno == EINTR) continue;
        CHECK(count > 0);
        data += count;
        length -= (size_t)count;
    }
}

static struct response exchange(const char *data, size_t length, bool half_close, bool fragmented) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(fd >= 0);
    struct timeval deadline = {5, 0};
    CHECK(setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &deadline, sizeof deadline) == 0);
    CHECK(setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &deadline, sizeof deadline) == 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons((unsigned short)port);
    CHECK(inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1);
    CHECK(connect(fd, (struct sockaddr *)&address, sizeof address) == 0);
    if (fragmented) {
        for (size_t offset = 0; offset < length;) {
            size_t chunk = length - offset;
            if (chunk > 13) chunk = 13;
            send_all(fd, data + offset, chunk);
            offset += chunk;
        }
    } else {
        send_all(fd, data, length);
    }
    if (half_close) CHECK(shutdown(fd, SHUT_WR) == 0);
    char *output = malloc(CAPACITY + 1);
    CHECK(output != NULL);
    size_t used = 0;
    for (;;) {
        CHECK(used < CAPACITY);
        ssize_t count = recv(fd, output + used, CAPACITY - used, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count == 0 || (count < 0 && errno == ECONNRESET)) break;
        CHECK(count > 0);
        used += (size_t)count;
    }
    CHECK(close(fd) == 0);
    output[used] = '\0';
    char *body = strstr(output, "\r\n\r\n");
    CHECK(body != NULL);
    *body = '\0';
    body += 4;
    int status = 0;
    CHECK(sscanf(output, "HTTP/1.1 %d", &status) == 1);
    return (struct response){status, output, body, used - (size_t)(body - output)};
}

static bool header(struct response response, const char *name, const char *value) {
    char field[256];
    int length = snprintf(field, sizeof field, "\r\n%s: %s", name, value);
    CHECK(length > 0 && (size_t)length < sizeof field);
    char *found = strstr(response.data, field);
    return found && (found[length] == '\r' || found[length] == '\0');
}

static struct response request(const char *method, const char *path, const char *body, size_t length, const char *extra, bool fragmented) {
    size_t capacity = length + strlen(extra) + 512;
    char *input = malloc(capacity);
    CHECK(input != NULL);
    int head = snprintf(input, capacity, "%s %s HTTP/1.1\r\nHost: localhost\r\nContent-Length: %zu\r\n%s\r\n", method, path, length, extra);
    CHECK(head > 0 && (size_t)head + length < capacity);
    if (length) memcpy(input + head, body, length);
    struct response response = exchange(input, (size_t)head + length, false, fragmented);
    free(input);
    return response;
}

static void expect_body(struct response response, int status, const char *body, size_t length) {
    CHECK(response.status == status);
    CHECK(response.length == length);
    CHECK(length == 0 || memcmp(response.body, body, length) == 0);
    free(response.data);
}

static void expect_status(struct response response, int status) {
    CHECK(response.status == status);
    free(response.data);
}

int main(int argc, char **argv) {
    CHECK(argc == 2);
    port = atoi(argv[1]);
    CHECK(port > 0 && port < 65536);
    CHECK(signal(SIGPIPE, SIG_IGN) != SIG_ERR);
    const char *methods[] = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"};
    const char *utf8 = "dato=水&texto=á";
    for (size_t i = 0; i < sizeof methods / sizeof *methods; ++i) {
        const char *body = i >= 1 && i <= 3 ? utf8 : "";
        char expected[128];
        int length = snprintf(expected, sizeof expected, "%s:42:%s", methods[i], body);
        struct response response = request(methods[i], "/methods/42", body, strlen(body), "", false);
        char size[24];
        snprintf(size, sizeof size, "%d", length);
        CHECK(header(response, "Content-Length", size));
        expect_body(response, 200, expected, (size_t)length);
    }
    struct response head = request("HEAD", "/status/200", "", 0, "", false);
    CHECK(header(head, "Content-Length", "7"));
    CHECK(header(head, "Content-Type", "text/plain; charset=utf-8"));
    expect_body(head, 200, "", 0);
    expect_body(request("HEAD", "/head", "", 0, "", false), 202, "", 0);
    expect_body(request("HEAD", "/missing", "", 0, "", false), 404, "", 0);
    struct response denied = request("DELETE", "/head", "", 0, "", false);
    CHECK(header(denied, "Allow", "GET, HEAD, OPTIONS"));
    expect_status(denied, 405);
    struct response options = request("OPTIONS", "/head", "", 0, "", false);
    CHECK(header(options, "Allow", "GET, HEAD, OPTIONS"));
    expect_body(options, 204, "", 0);
    expect_status(request("POST", "/missing", "", 0, "", false), 404);
    expect_status(request("BREW", "/head", "", 0, "", false), 501);
    expect_body(request("GET", "/allow-injection", "", 0, "", false), 500, "Internal Server Error", 21);
    const char *modified = "data:middleware:application/json";
    expect_body(request("POST", "/middleware", "data", 4, "Content-Type: application/json\r\n", false), 200, modified, strlen(modified));

    char *payload = malloc(1048576);
    CHECK(payload != NULL);
    memset(payload, 'a', 1023);
    memcpy(payload + 1023, "水", 3);
    payload[1026] = '\0';
    memset(payload + 1027, 'z', 2000);
    expect_body(request("POST", "/echo", payload, 3027, "", false), 200, payload, 3027);
    expect_body(request("POST", "/echo", payload, 3027, "", true), 200, payload, 3027);
    memset(payload, 'x', 1048576);
    expect_body(request("POST", "/echo", payload, 1048576, "", false), 200, payload, 1048576);
    free(payload);
    expect_body(request("POST", "/echo", "\xff", 1, "", false), 200, "\xff", 1);
    expect_body(request("POST", "/text", "\xff", 1, "", false), 415, "invalid_utf8", 12);
    const char *json_body = "{\"large\":9007199254740993,\"text\":\"水\"}";
    struct response json_roundtrip = request("POST", "/json-codec", json_body, strlen(json_body), "Content-Type: application/json\r\n", false);
    CHECK(header(json_roundtrip, "Content-Type", "application/json"));
    expect_body(json_roundtrip, 200, json_body, strlen(json_body));
    expect_body(request("POST", "/json-codec", "[", 1, "Content-Type: application/json\r\n", false), 400, "invalid JSON", 12);
    const char *form_body = "name=Ada&name=%E6%B0%B4";
    expect_body(request("POST", "/form-codec", form_body, strlen(form_body), "Content-Type: application/x-www-form-urlencoded; charset=UTF-8\r\n", false), 200, "Ada:水", 7);
    const char binary[] = {0, (char)255, (char)195, 40, 65};
    expect_body(request("POST", "/echo", binary, sizeof binary, "Content-Type: application/octet-stream\r\n", true), 200, binary, sizeof binary);
    const char mutated[] = {66, (char)255, (char)195, 40, 65};
    expect_body(request("GET", "/static-binary?mutate=1", "", 0, "", false), 200, mutated, sizeof mutated);
    const char *binary_paths[] = {"/binary", "/static-binary"};
    for (size_t i = 0; i < sizeof binary_paths / sizeof *binary_paths; ++i) {
        struct response bytes = request("GET", binary_paths[i], "", 0, "", false);
        CHECK(header(bytes, "Content-Length", "5"));
        CHECK(header(bytes, "Content-Type", i == 0 ? "application/octet-stream" : "image/png"));
        expect_body(bytes, 200, binary, sizeof binary);
        struct response binary_head = request("HEAD", binary_paths[i], "", 0, "", false);
        CHECK(header(binary_head, "Content-Length", "5"));
        expect_body(binary_head, 200, "", 0);
    }
    struct response repeated = request("GET", "/headers", "", 0, "X-Tag: first\r\nx-tag: second\r\n", false);
    CHECK(strstr(repeated.data, "\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2") != NULL);
    expect_body(repeated, 200, "first:second", 12);
    struct response duplicate_location = request("GET", "/duplicate-location", "", 0, "", false);
    CHECK(strstr(duplicate_location.data, "\r\nLocation:") == NULL);
    CHECK(strstr(duplicate_location.data, "\r\nlocation:") == NULL);
    expect_body(duplicate_location, 500, "Internal Server Error", 21);
    const char *reserved[] = {"CoNtEnT-LeNgTh", "Transfer-Encoding", "Connection", "Content-Type", "Allow", "X-Request-Id", "X-Content-Type-Options", "Trailer", "Upgrade", "Keep-Alive", "Proxy-Connection", "TE"};
    for (size_t i = 0; i < sizeof reserved / sizeof *reserved; ++i) {
        char path[128];
        snprintf(path, sizeof path, "/reserved-header/%s", reserved[i]);
        struct response invalid_header = request("GET", path, "", 0, "", false);
        CHECK(strstr(invalid_header.data, "injected") == NULL);
        expect_body(invalid_header, 500, "Internal Server Error", 21);
    }
    const struct { const char *fields; int status; } cases[] = {
        {"Content-Length: 1048577\r\n", 413},
        {"Content-Length: 999999999999999999999999\r\n", 413},
        {"Content-Length: -1\r\n", 400},
        {"Content-Length: 1x\r\n", 400},
        {"Content-Length: 1\r\nContent-Length: 1\r\n", 400},
        {"Transfer-Encoding: chunked\r\n", 400},
        {"Transfer-Encoding: chunked\r\nContent-Length: 0\r\n", 400},
        {"Expect: 100-continue\r\n", 417},
        {"Host: other\r\n", 400},
        {"Bad Header: value\r\n", 400},
        {"Folded: value\r\n continuation\r\n", 400}
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; ++i) {
        char input[512];
        int length = snprintf(input, sizeof input, "POST /echo HTTP/1.1\r\nHost: localhost\r\n%s\r\n", cases[i].fields);
        expect_status(exchange(input, (size_t)length, false, false), cases[i].status);
    }
    const char *partial = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nab";
    expect_status(exchange(partial, strlen(partial), true, false), 400);
    struct timespec before, after;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    expect_status(exchange(partial, strlen(partial), false, false), 408);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &after) == 0);
    CHECK((double)(after.tv_sec - before.tv_sec) + (after.tv_nsec - before.tv_nsec) / 1e9 < 4.0);
    char large_header[8300];
    const char *prefix = "POST /echo HTTP/1.1\r\nHost: localhost\r\nX-Large: ";
    size_t prefix_length = strlen(prefix);
    memcpy(large_header, prefix, prefix_length);
    memset(large_header + prefix_length, 'x', 8192);
    expect_status(exchange(large_header, prefix_length + 8192, false, false), 431);
    const char *old = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n";
    expect_status(exchange(old, strlen(old), false, false), 505);
    const char *invalid = "GET /%zz HTTP/1.1\r\nHost: localhost\r\n\r\n";
    expect_status(exchange(invalid, strlen(invalid), false, false), 400);
    puts("Sumi HTTP method and body contracts passed");
    return 0;
}

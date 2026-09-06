"""Exercise compiled Sumi applications over loopback HTTP."""
import contextlib
import http.client
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@contextlib.contextmanager
def server(binary, ready):
    port = free_port()
    with tempfile.TemporaryFile(mode="w+") as log:
        process = subprocess.Popen(
            [binary], cwd=ROOT,
            env={**os.environ, "PORT": str(port), "SUMI_PUBLIC": str(ROOT / "examples/web/public")},
            stdout=log, stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + 5
            while True:
                log.seek(0)
                output = log.read()
                if ready in output:
                    break
                assert process.poll() is None, output
                assert time.monotonic() < deadline, output
                time.sleep(0.02)
            yield port, log
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def request(port, path, method="GET"):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=4)
    try:
        connection.request(method, path)
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()


def events(log):
    log.seek(0)
    return [dict(item.split("=", 1) for item in shlex.split(line))
            for line in log.read().splitlines() if line.startswith("level=")]


site, fixture = sys.argv[1:]
with server(site, "Sumi listening") as (port, log):
    for url, filename, mime in [
        ("/?private=SECRET", "index.html", "text/html; charset=utf-8"),
        ("/assets/site.css", "site.css", "text/css; charset=utf-8"),
        ("/assets/site.js", "site.js", "text/javascript; charset=utf-8"),
    ]:
        status, headers, body = request(port, url)
        assert status == 200
        assert headers["Content-Type"] == mime
        assert body == (ROOT / "examples/web/public" / filename).read_bytes()
        assert int(headers["Content-Length"]) == len(body)
        assert headers["X-Content-Type-Options"] == "nosniff"
    for path in ["/missing", "/../README.md", "/%2e%2e/README.md", "/assets/", "/assets/site.css/"]:
        assert request(port, path)[0] == 404
    status, headers, body = request(port, "/", "HEAD")
    assert status == 405 and headers["Allow"] == "GET" and body == b""
    assert request(port, "/", "POST")[0] == 405
    # A real bind failure must identify both the operation and address.
    failure = subprocess.run([site], cwd=ROOT, env={**os.environ, "PORT": str(port)},
                             capture_output=True, text=True, timeout=5)
    assert failure.returncode == 1
    assert "Cannot bind listener" in failure.stdout and str(port) in failure.stdout
    log.seek(0)
    assert "SECRET" not in log.read()

with server(fixture, "READY") as (port, log):
    observed = {}
    for path, code in [("/failure/PRIVATE", "APP_GREETING_UNAVAILABLE"),
                       ("/invalid", "SUMI_RESPONSE_CONTENT_TYPE"),
                       ("/unicode", "APP_UNICODE")]:
        status, headers, body = request(port, path)
        assert status == 500 and body == b"Internal Server Error"
        assert "Injected" not in headers
        observed[headers["X-Request-Id"]] = code
    status, headers, body = request(port, "/context?key=SECRET")
    assert body == ("key=SECRET:" + headers["X-Request-Id"]).encode()
    # A parser rejection is observable even though no handler runs.
    with socket.create_connection(("127.0.0.1", port), timeout=4) as sock:
        sock.sendall(b"GET / HTTP/1.1\r\n\r\n")
        received = b""
        while chunk := sock.recv(8192):
            received += chunk
        assert received.startswith(b"HTTP/1.1 400 ")
    deadline = time.monotonic() + 2
    while True:
        recorded = events(log)
        completed = [event for event in recorded if event["event"] == "http.request.completed"]
        if len(completed) == 5:
            break
        assert time.monotonic() < deadline, recorded
        time.sleep(0.01)
    for event in completed:
        if event["request_id"] in observed:
            assert event["code"] == observed[event["request_id"]]
            assert event["level"] == "error" and event["status"] == "500"
        assert int(event["duration_ms"]) >= 0
    assert any(event["code"] == "SUMI_HTTP_400" for event in completed)
    assert len({event["request_id"] for event in completed}) == 5
    assert len([event for event in recorded if event["event"] == "http.request.started"]) == 5
    log.seek(0)
    output = log.read()
    assert "PRIVATE" not in output and "SECRET" not in output
    assert 'route="/failure/:name"' in output
    assert 'Diagnóstico: 水?second line' in output

with server(fixture, "READY") as (port, log):
    for status in [204, 205, 304]:
        actual, headers, body = request(port, "/status/" + str(status))
        assert actual == status and body == b""
        if status in [204, 304]:
            assert "Content-Length" not in headers
        else:
            assert headers["Content-Length"] == "0"
    for status in [199, 600]:
        actual, headers, body = request(port, "/status/" + str(status))
        assert actual == 500 and body == b"Internal Server Error"

with tempfile.TemporaryDirectory() as missing:
    failure = subprocess.run([site], cwd=ROOT,
                             env={**os.environ, "SUMI_PUBLIC": missing},
                             capture_output=True, text=True, timeout=5)
    assert failure.returncode == 1
    assert "SUMI_STATIC_READ" in failure.stdout and "index.html" in failure.stdout
    assert "Sumi listening" not in failure.stdout

print("Sumi HTTP contracts passed")

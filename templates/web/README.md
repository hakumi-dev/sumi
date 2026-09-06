# Sumi application

```sh
sumi test
sumi server
sumi build --release
```

The server listens on `127.0.0.1:8080`. Use `--port` to select another port.
`server` and `test` have the short aliases `s` and `t`.

`neri.json` declares library and executable units. Files in `app` and `tests` are
discovered recursively; `main.hk` is the web entry point. References connect the
application to the copied Sumi core and HTTP libraries. `sumi.conf` selects the
server/test units and the public directory.

Optional `.env` and `.env.development`, `.env.test`, or `.env.production` files
supply configuration. Process variables override file values. Use `--environment`
to select an environment explicitly. Keep credentials out of version control.

The generated project includes its own framework source snapshot under
`vendor/sumi`. The compiled executable needs the public assets at runtime.
For direct execution from this directory:

```sh
SUMI_ENV=production SUMI_PUBLIC=public ./build/application
```

# Sumi application

```sh
sumi test
sumi server
sumi build --release
```

The server listens on `127.0.0.1:8080`. Use `--port` to select another port.
`server` and `test` have the short aliases `s` and `t`.

`neri.json` declares source files. `sumi.conf` selects source sets and the public
directory. Rename folders by updating those paths; directory names are not
required by the framework.

Optional `.env` and `.env.development`, `.env.test`, or `.env.production` files
supply configuration. Process variables override file values. Use `--environment`
to select an environment explicitly. Keep credentials out of version control.

The generated project includes its own framework source snapshot under
`vendor/sumi`. The compiled executable needs the public assets at runtime.
For direct execution from this directory:

```sh
SUMI_ENV=production SUMI_PUBLIC=public ./build/application
```

# Build directory layout

`build/` holds local output; it is not part of a Sumi package. Keep these paths
because the packager and local launchers use them:

| Path | Purpose |
| --- | --- |
| `build/packages/` | The package named by `build/latest-package` and its adjacent `.tar.gz` archive. Older generations can be removed. |
| `build/latest-package` | Path to the current completed package, used by the checkout launcher. |
| `build/package-work/` | Stable package staging and compiler input path. Do not relocate it between builds; doing so loses object-cache reuse. |
| `build/package.lock` | Temporary package-build lock. Remove a stale lock only after confirming the builder stopped. |
| `build/console/runtime` | Local link to the Neri runtime used by direct console development. |

`build/cache/` holds disposable compiler caches and temporary test helpers. It
can be removed when no build or test process is using it. Install Neri toolchains
under `~/.neri`, outside this directory.

Do not move `build/package-work/` between builds; its stable path preserves
incremental package compilation. The installed `~/.sumi/bin/sumi` uses its own
package generation under `~/.sumi/packages`.

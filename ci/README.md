# CI setup (watcher only)

The active workflow is `.github/workflows/kernel-watch.yml`. It runs on a
GitHub-hosted runner with only `git`, `curl` and `jq`.

It checks the three channels and writes a Markdown table to the workflow step
summary:

- `stable` — Arch `core/linux` (currently 7.2.15.arch1-1);
- `testing` — Arch `core-testing/linux` (currently 7.3.4.arch1-1);
- `mainline` — AUR `linux-mainline` (currently 7.4rc1-1).

It never builds, signs, publishes or touches SourceForge. Monthly builds and
publication are manual; signing keys, `keys/env.sh`, `config.env` and the
SourceForge SSH key never enter CI.

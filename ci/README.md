# CI setup (prepared)

The example workflow is **not active** because this repository has no remote
yet. It targets a self-hosted runner with these labels:

```text
self-hosted, linux, x64, x-kernel
```

The runner needs:

- `devtools` (`makechrootpkg`, `mkarchroot`), `git`, `gpg`, `rsync`, `sftp`,
  `curl`, `jq`, `python3`, `bsdtar`;
- sudo access for `mkarchroot`/`makechrootpkg` (NOPASSWD if the runner is
  non-interactive);
- `keys/env.sh` and the SourceForge SSH key, kept only on the runner;
- a local `config.env` (gitignored) with the SourceForge paths, or the
  defaults from `config.env.example`.

The `publish` job uses a protected GitHub environment
(`kernel-release`) with required reviewers. The scheduled job only builds and
signs; it never publishes. Signing keys are not stored in GitHub.

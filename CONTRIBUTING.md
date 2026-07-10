# Contributing

Thanks for your interest in improving Trae Superpowers!

## Development setup

No build step, no runtime dependencies. You only need `bash` and `git`.

## Running tests

Tests run fully offline in an isolated `HOME`; they never touch your real Trae
installation or the network.

```bash
# Run the full suite
bash tests/run_all.sh

# Run a single suite
bash tests/test_install.sh
bash tests/test_update.sh
bash tests/test_uninstall.sh
```

To run the installer locally against a fake skills source (no `git clone`, no
writes to real directories):

```bash
SUPERPOWERS_SKILLS_SRC=/path/to/fake HOME=/tmp/fakehome bash install.sh
```

Key environment variables:

- `SUPERPOWERS_SKILLS_SRC` — inject a local skills source (must contain a
  `skills/` subdirectory), skipping `git clone`.
- `SUPERPOWERS_UPSTREAM_URL` — override the upstream repo URL.

## Coding conventions

- **Self-contained scripts.** Each script must run standalone via
  `curl -fsSL ... | bash`; do not `source` external files.
- **Portable bash.** The scripts target the bash shipped with macOS, so avoid
  features unavailable in older bash versions (associative arrays, `mapfile`,
  etc.).
- **One script covers macOS / Linux / Windows** (Git Bash / WSL). Do not add
  PowerShell scripts.
- **Match the existing style.** Follow the structure and comment style of the
  surrounding code.

## Submitting changes

1. Fork the repo and create a feature branch.
2. Add or update tests for behavior changes.
3. Make sure `bash tests/run_all.sh` passes.
4. Open a pull request describing what changed and why.

CI runs the test suite on Linux and macOS plus a `shellcheck` pass on every PR.

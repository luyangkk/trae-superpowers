# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `install.sh` — detect installed Trae variants and copy upstream Superpowers
  skills into each variant's global skills directory, writing a
  `.superpowers-manifest` to track project-owned skills.
- `update.sh` — re-sync installed skills to the latest upstream state as an
  exact mirror: update changed content, remove orphaned skills, and never touch
  skills you installed yourself.
- `uninstall.sh` — remove only the skills this project installed. Prefers the
  manifest for precise, offline removal; falls back to the upstream skill list.
- Bilingual documentation (`README.md` / `README.zh-CN.md`).
- Behavior test suite covering install / update / uninstall, runnable offline in
  an isolated `HOME`.
- Continuous integration running the test suite on Linux and macOS plus a
  `shellcheck` pass.

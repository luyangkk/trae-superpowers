# Security Policy

## Reporting a vulnerability

If you discover a security issue, please open a
[GitHub issue](../../issues) or contact the maintainers privately. We will
respond as quickly as we can.

## About `curl | bash`

The install / update / uninstall commands pipe a remote script into `bash`.
Before running any such command, you are encouraged to review the script:

```bash
# Inspect before executing
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/install.sh
```

The scripts:

- have no runtime dependencies beyond `bash` and `git`;
- only read and write inside your Trae skills directory (`~/._agent*` /
  `~/.trae*`);
- track project-installed skills in a `.superpowers-manifest` file, and restrict
  all deletions to that manifest — they never remove skills you installed
  yourself.

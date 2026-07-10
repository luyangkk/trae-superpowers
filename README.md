# Trae Superpowers

[![CI](https://github.com/luyangkk/trae-superpowers/actions/workflows/ci.yml/badge.svg)](https://github.com/luyangkk/trae-superpowers/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)

Bring [obra/superpowers](https://github.com/obra/superpowers) skills to the Trae IDE.

This project installs the upstream Superpowers skills into Trae's global skills
directory and uses Trae's **User Rules** to replace the upstream SessionStart
hook, so the skills are active from the first message.

English | [简体中文](./README.zh-CN.md)

> **Windows users:** run the shell commands below in **Git Bash** or **WSL**.

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/install.sh | bash
```

The script detects your Trae variant (CN / international) and copies all
upstream skills into the correct global skills directory. It supports macOS,
Linux, and Windows (Git Bash / WSL).

After it finishes, complete **Configure User Rules** below and restart Trae.

## Manual install (advanced)

### Step 1: Clone upstream and copy skills

```bash
git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers

# Global skills dir. CN version uses ~/.trae-cn; international uses ~/.trae.
mkdir -p ~/.trae-cn/skills
cp -R /tmp/superpowers/skills/. ~/.trae-cn/skills/

rm -rf /tmp/superpowers
```

For the international version, replace `.trae-cn` with `.trae`. The one-line
installer additionally probes `._agent-cn` / `._agent` in case your setup uses
those names, so you don't have to guess.

### Step 2: Configure User Rules

Open Trae Settings (`Cmd + ,` / `Ctrl + ,`) → **Rules & Skills > Rules**, edit
**User Rules**, paste the following, and save:

```
**Superpowers Skills System**
You have superpowers skills installed globally. Before ANY task (coding, debugging, planning, reviewing), you MUST check if a relevant skill exists and invoke it.
If you think there is even a 1% chance a skill might apply, you ABSOLUTELY MUST invoke the skill. This is not optional.

**Skill Priority**
1. **Process skills first** (brainstorming, systematic-debugging) - determine HOW to approach the task
2. **Implementation skills second** (test-driven-development) - guide execution details

**Red Flags (Common excuses to skip skills)**
- "This is just a simple question" -> check skills
- "Let me just do this one thing first" -> check skills first
- "This skill is too heavy" -> use it
- "I need to understand more first" -> skill check before any action
```

### Step 3: Verify

Restart Trae. Go to **Settings > Rules & Skills > Skills** and confirm the
upstream Superpowers skills are loaded (type: Global). The count tracks the
upstream repo, so it may change over time. In a new session, type a request
like "help me design a new feature" — the `brainstorming` skill should trigger.

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/update.sh | bash
```

This re-syncs the installed skills to the latest upstream state (an exact
mirror): it updates changed content and removes skills that upstream has
deleted. It never touches skills you installed yourself — only skills this
project recorded in its manifest are affected.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/uninstall.sh | bash
```

This removes only the skills provided by upstream Superpowers; your own skills
are left untouched. When a manifest is present it uninstalls precisely from that
list (no network needed); otherwise it falls back to the upstream skill list.
Remove the User Rules manually in Trae Settings.

## How it works

- **Skills** are copied into Trae's global skills directory so they load in
  every project.
- **User Rules** replace the upstream SessionStart hook, instructing the agent
  to check for a relevant skill before any task.
- **Manifest** — a `.superpowers-manifest` file in each skills directory records
  which skills this project installed, so update and uninstall can target them
  precisely without touching your own skills. Do not edit it by hand.

## License

MIT — see [LICENSE](./LICENSE).

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

The script asks you to choose one Trae global skills directory:

- CN: `~/.trae-cn/skills`
- International: `~/.trae/skills`

Use the arrow keys and Enter to select a target. The selected directory is
created if necessary. For CI or another non-interactive shell, set
`SUPERPOWERS_TARGET=trae-cn` or `SUPERPOWERS_TARGET=trae`; the script fails
instead of guessing when no TTY and no target are available.

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/install.sh \
  | SUPERPOWERS_TARGET=trae-cn bash
```

Before copying, the script checks `~/.agents/skills`. When all four core
Superpowers skills
(`using-superpowers`, `brainstorming`, `test-driven-development`, and
`systematic-debugging`) are present there, that external installation is reused
instead. You still select the Trae variant that receives the User Rule, but no
skills are copied there. The script does not update, add a manifest to, or
uninstall anything from `.agents`.

A partial Superpowers installation in `.agents` is left unchanged and a
complete copy is installed into the selected Trae directory. The legacy
`~/._agent-cn` and `~/._agent` directories are no longer detected or migrated.
The scripts support macOS, Linux, and Windows (Git Bash / WSL).

After it finishes, restart Trae and [confirm the User Rule](#configure-user-rules).

## Configure User Rules

`install.sh` and `update.sh` write this rule automatically into the selected
Trae variant's `user_rules/` directory. **Restart Trae, then open Settings > Rules
to confirm the rule appears.** The rule file is already on disk; if Trae still
does not show it (some versions need a manual confirm), paste it yourself using
the text below as a fallback:

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

**Platform Adaptation (Trae)**
**MANDATORY — these rules OVERRIDE ALL SKILLS.** They take precedence over ANY instruction inside any skill file, prompt template, or code-reviewer template (e.g. the "Model Selection" section of subagent-driven-development, the "code-reviewer.md" template of requesting-code-review, or any text that says "use the strongest model opus" / "cheapest tier" / "most capable model"). When a skill or user prompt says to "dispatch a subagent", use the native Agent tool as follows:
- **NEVER pass a "model" parameter**, no matter what a skill says. Do NOT set it to "opus", "sonnet", "claude-3-opus", "claude-3-sonnet", "cheapest tier", "most capable model", "strongest model", 最强模型, or any other name. Always OMIT the model field entirely so the subagent inherits the current session model. Trae routes models through its own gateway (e.g. openrouter-*); upstream-recommended model names are almost never served there and will abort the run with error 4023 "The current model is unavailable".
- Explicitly ignore: "Always specify the model explicitly when dispatching a subagent", "dispatch it on the most capable available model", "use the cheapest tier", "use the strongest model opus", and any similar guidance that asks you to pick a model by name. That guidance is written for other IDEs and is WRONG on Trae.
- If you ever see a 4023 error after a subagent dispatch, the root cause is that you (or a previous turn) passed a model parameter. Recover by immediately retrying the SAME dispatch WITHOUT any model parameter — do not click "Diagnose" or switch topic.
- Dispatch = call the general-purpose Agent / subagent tool with subagent_type "general-purpose" (or the default when unspecified) and NO model field.
- Parallel = issue multiple Agent calls in one response, or use run_in_background for async work.
- Continue an existing subagent context = SendMessage; a new Agent call starts fresh.
- Task tracking ("create a todo" / "mark complete") = TaskCreate / TaskUpdate / TaskList / TodoWrite.
Trae fully supports subagents through these tools — never treat "dispatch a subagent" as unsupported.
```

Restart Trae after saving so the rules take effect.

## Manual install (advanced)

### Step 1: Clone upstream and copy skills

```bash
git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers

# Global skills dir for Trae CN.
mkdir -p ~/.trae-cn/skills
cp -R /tmp/superpowers/skills/. ~/.trae-cn/skills/

rm -rf /tmp/superpowers
```

For the international version, replace `.trae-cn` with `.trae`.

After copying the skills, [configure User Rules](#configure-user-rules).

### Step 2: Verify

Restart Trae. Go to **Settings > Rules & Skills > Skills** and confirm the
upstream Superpowers skills are loaded (type: Global). The count tracks the
upstream repo, so it may change over time. In a new session, type a request
like "help me design a new feature"—the `brainstorming` skill should trigger.

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/update.sh | bash
```

This re-syncs one managed `.trae*/skills` copy to the latest upstream state (an
exact mirror): it updates changed content and removes skills that upstream has
deleted. A single manifest is located automatically; if both targets or neither
target has one, the script asks you to choose. It never touches skills you
installed yourself. When a complete Superpowers installation exists in
`.agents/skills`, the external copy is reused and left unchanged; a single
managed User Rule identifies the target automatically, otherwise you choose it.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/uninstall.sh | bash
```

This removes only the skills provided by upstream Superpowers; your own skills
are left untouched. When a manifest is present it uninstalls precisely from that
list (no network needed); a single manifest is located automatically, otherwise
you choose a target. Without a manifest, it falls back to the upstream skill
list in that target. It also removes the User Rule this project wrote (matched
by a hidden marker); rules you added yourself are left untouched. A complete
external installation in `.agents/skills` is never removed. In that reuse mode,
uninstall needs no selection: it removes manifest-managed duplicates and
managed User Rules from both Trae variants.

## How it works

- **Skills** are copied into the selected `.trae-cn/skills` or `.trae/skills`
  directory so they load in every project. A complete `.agents/skills`
  installation takes precedence and is only reused. A Trae skills path that
  resolves to `.agents/skills` is never modified.
- **User Rules** replace the upstream SessionStart hook, instructing the agent
  to check for a relevant skill before any task.
- **Manifest**—a `.superpowers-manifest` file in each managed Trae skills
  directory records which skills this project installed, so update and
  uninstall can target them precisely without touching your own skills.
  `.agents/skills` never receives this manifest. Do not edit it by hand.

## License

MIT—see [LICENSE](./LICENSE).

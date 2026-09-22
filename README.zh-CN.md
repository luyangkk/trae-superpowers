# Trae Superpowers

[![CI](https://github.com/luyangkk/trae-superpowers/actions/workflows/ci.yml/badge.svg)](https://github.com/luyangkk/trae-superpowers/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)

让 [obra/superpowers](https://github.com/obra/superpowers) 的技能在 Trae IDE 中生效。

本工程把 upstream Superpowers 的 skills 安装到 Trae 的全局技能目录,并用 Trae 的
**User Rules** 替代 upstream 原生的 SessionStart Hook,使技能从第一条消息起即可生效。

[English](./README.md) | 简体中文

> **Windows 用户:** 请在 **Git Bash** 或 **WSL** 中运行下列 shell 命令。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/install.sh | bash
```

脚本会让你从以下两个 Trae 全局技能目录中选择一个:

- 国内版:`~/.trae-cn/skills`
- 国际版:`~/.trae/skills`

使用方向键和 Enter 选择目标,所选目录不存在时会自动创建。CI 等非交互环境须设置
`SUPERPOWERS_TARGET=trae-cn` 或 `SUPERPOWERS_TARGET=trae`;没有 TTY 且未指定目标时,
脚本会报错,不会擅自选择默认目录。

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/install.sh \
  | SUPERPOWERS_TARGET=trae-cn bash
```

复制前,脚本会检查 `~/.agents/skills`。如果其中
同时存在 `using-superpowers`、`brainstorming`、`test-driven-development` 和
`systematic-debugging` 四个核心 Skill,脚本会直接复用这套外部安装,不会更新、
写入 manifest 或卸载 `.agents` 中的任何内容。此时仍需选择一个 Trae 版本来写入
User Rule,但不会向该目录复制 Skill。

如果 `.agents` 只有部分核心 Skill,脚本会保留原内容,并把完整副本安装到所选 Trae 目录。
旧的 `~/._agent-cn` 与 `~/._agent` 已不再探测,也不会自动迁移。脚本支持 macOS、
Linux 和 Windows(Git Bash / WSL)。

完成后请重启 Trae,并[确认 User Rules](#配置-user-rules)已出现。

## 配置 User Rules

`install.sh` 与 `update.sh` 会把该规则自动写入所选 Trae 变体的 `user_rules/`
目录。**重启 Trae 后,打开 设置 > Rules 确认规则已出现。** 规则文件已写入磁盘;
若 Trae 仍未显示(部分版本需手动确认一次),可用下方文本手动粘贴作为回退:

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

保存后重启 Trae,规则即可生效。其中 **Platform Adaptation (Trae)** 一段为**强制优先级最高**规则,覆盖任何 skill 内部的模型选择指令(包括 `subagent-driven-development` 的 "Model Selection"、`requesting-code-review/code-reviewer.md` 中的"用最强模型 opus"等表述)。核心要求:**派发子代理时永远不要传 `model` 参数**,让子代理继承当前会话模型;上游推荐的 `sonnet`/`opus` 等模型名在 Trae 网关(如 `openrouter-*`)下无法解析,会触发 4023 "The current model is unavailable" 导致对话中断。若遇到 4023,直接去掉 model 参数重试即可。

## 手动安装(进阶)

### Step 1: 克隆 upstream 并复制 Skills

```bash
git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers

# Trae 国内版全局技能目录。
mkdir -p ~/.trae-cn/skills
cp -R /tmp/superpowers/skills/. ~/.trae-cn/skills/

rm -rf /tmp/superpowers
```

国际版请把 `.trae-cn` 换成 `.trae`。

复制完技能后,请[配置 User Rules](#配置-user-rules)。

### Step 2: 验证安装

重启 Trae。进入 **Settings > Rules & Skills > Skills**,确认 upstream Superpowers
的技能已加载(类型为 Global)。数量随上游仓库变化,可能变动。新建会话输入类似
「帮我设计一个新功能」的指令,应触发 `brainstorming` 技能。

## 更新

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/update.sh | bash
```

把一个由本工程管理的 `.trae*/skills` 副本精确镜像到上游最新状态:更新变动内容,
并移除上游已删除的 skill。只有一处 manifest 时自动定位;两处都有或都没有时要求
选择目标。脚本不会触碰用户自有 skill。如果 `.agents/skills` 已有完整
Superpowers,脚本会直接复用且不更新该外部副本;只有一处托管 User Rule 时自动定位,
否则要求选择目标。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/uninstall.sh | bash
```

仅移除 upstream Superpowers 提供的技能,不会动你自己的技能。只有一处 manifest 时
自动定位;两处都有或都没有时要求选择目标。存在 manifest 时按清单精确卸载(无需联网);
否则在所选目标中回退到上游清单。同时移除本工程写入的 User Rules 规则(按隐藏标记
匹配),你自己添加的规则不受影响。完整的 `.agents/skills` 外部安装永远不会被删除;
处于复用模式时无需选择,脚本会清理两种 Trae 目录中由 manifest 管理的重复副本及
全部托管 User Rule。

## 工作原理

- **Skills** 被复制到所选的 `.trae-cn/skills` 或 `.trae/skills`,使其在所有项目
  中加载。完整的 `.agents/skills` 安装优先,脚本只复用它。任何解析到
  `.agents/skills` 的 Trae 软链接路径都不会被修改。
- **User Rules** 替代 upstream 的 SessionStart Hook,要求 agent 在任何任务前先检查
  是否有匹配的技能。
- **Manifest** —— 每个由本工程管理的 Trae skills 目录下,
  `.superpowers-manifest` 文件记录本工程装入了哪些 skill,使更新与卸载能精确定位
  它们,不影响你自己的 skill。`.agents/skills` 不会写入该文件。请勿手动编辑。

## 许可证

MIT —— 见 [LICENSE](./LICENSE)。

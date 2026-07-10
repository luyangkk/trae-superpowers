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

脚本会自动探测你的 Trae 版本(国内版 / 国际版),把全部 upstream skills 复制到正确的
全局技能目录。支持 macOS、Linux 和 Windows(Git Bash / WSL)。

完成后请[配置 User Rules](#配置-user-rules)并重启 Trae。

## 配置 User Rules

这一步对**两种安装方式都必需**。User Rules 替代 upstream 原生的 SessionStart
Hook,要求 agent 在任何任务前先检查是否有匹配的技能。

打开 Trae 设置(`Cmd + ,` / `Ctrl + ,`)→ **Rules & Skills > Rules**,编辑
**User Rules**,粘贴以下内容并保存:

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
When a skill says to "dispatch a subagent" (e.g. subagent-driven-development, dispatching-parallel-agents), use the native Agent tool:
- Dispatch = call the Agent tool with subagent_type "general-purpose". Do NOT pass a model parameter — let the subagent inherit the current session model. Trae routes models through its own gateway (e.g. openrouter-*), so hard-coded names like "sonnet"/"opus" that other Superpowers docs recommend are often unavailable and abort the run with error 4023 "The current model is unavailable".
- Ignore the "always specify the model explicitly" instruction in subagent-driven-development's Model Selection section when on Trae; it assumes model names Trae may not serve.
- Parallel = issue multiple Agent calls in one response, or use run_in_background for async work.
- Continue an existing subagent's context = SendMessage; a new Agent call starts fresh.
- Task tracking ("create a todo / mark complete") = TaskCreate / TaskUpdate / TaskList.
Trae fully supports subagents through these tools — never treat "dispatch a subagent" as unsupported.
```

保存后重启 Trae,规则即可生效。其中 **Platform Adaptation (Trae)** 一段告诉 agent:遇到
subagent 类技能(如 subagent-driven-development)时,用原生 `Agent` 工具派发子代理、**且不要
指定 model**,避免因传入 `sonnet`/`opus` 等 Trae 网关无法解析的模型名而报 4023、对话中断。

## 手动安装(进阶)

### Step 1: 克隆 upstream 并复制 Skills

```bash
git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers

# 全局技能目录。国内版用 ~/._agent-cn;国际版用 ~/._agent。
mkdir -p ~/._agent-cn/skills
cp -R /tmp/superpowers/skills/. ~/._agent-cn/skills/

rm -rf /tmp/superpowers
```

国际版请把 `._agent-cn` 换成 `._agent`。一键脚本还会额外探测 `.trae-cn` / `.trae`,
以兼容使用这些命名的环境,你无需自己判断。

复制完技能后,请[配置 User Rules](#配置-user-rules)。

### Step 2: 验证安装

重启 Trae。进入 **Settings > Rules & Skills > Skills**,确认 upstream Superpowers
的技能已加载(类型为 Global)。数量随上游仓库变化,可能变动。新建会话输入类似
「帮我设计一个新功能」的指令,应触发 `brainstorming` 技能。

## 更新

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/update.sh | bash
```

把已安装的 skills 精确镜像到上游最新状态:更新变动内容,并移除上游已删除的
skill。绝不触碰你自己安装的 skill —— 只有本工程 manifest 记录过的 skill 才会
被同步。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/luyangkk/trae-superpowers/main/uninstall.sh | bash
```

仅移除 upstream Superpowers 提供的技能,不会动你自己的技能。存在 manifest 时按清单
精确卸载(无需联网);否则回退到上游清单。User Rules 需在 Trae 设置中手动移除。

## 工作原理

- **Skills** 被复制到 Trae 全局技能目录,使其在所有项目中加载。
- **User Rules** 替代 upstream 的 SessionStart Hook,要求 agent 在任何任务前先检查
  是否有匹配的技能。
- **Manifest** —— 每个 skills 目录下的 `.superpowers-manifest` 文件记录本工程装入了
  哪些 skill,使更新与卸载能精确定位它们,不影响你自己的 skill。请勿手动编辑。

## 许可证

MIT —— 见 [LICENSE](./LICENSE)。

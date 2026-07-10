# Trae Superpowers

让 [obra/superpowers](https://github.com/obra/superpowers) 的技能在 Trae IDE 中生效。

本工程把 upstream Superpowers 的 skills 安装到 Trae 的全局技能目录,并用 Trae 的
**User Rules** 替代 upstream 原生的 SessionStart Hook,使技能从第一条消息起即可生效。

[English](./README.md) | 简体中文

> **Windows 用户:** 请在 **Git Bash** 或 **WSL** 中运行下列 shell 命令。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/trae-superpowers/main/install.sh | bash
```

脚本会自动探测你的 Trae 版本(国内版 / 国际版),把全部 upstream skills 复制到正确的
全局技能目录。支持 macOS、Linux 和 Windows(Git Bash / WSL)。

完成后请按下方「配置 User Rules」操作并重启 Trae。

## 手动安装(进阶)

### Step 1: 克隆 upstream 并复制 Skills

```bash
git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers

# 全局技能目录。国内版用 ~/.trae-cn;国际版用 ~/.trae。
mkdir -p ~/.trae-cn/skills
cp -R /tmp/superpowers/skills/. ~/.trae-cn/skills/

rm -rf /tmp/superpowers
```

国际版请把 `.trae-cn` 换成 `.trae`。一键脚本还会额外探测 `._agent-cn` / `._agent`,
以兼容使用这些命名的环境,你无需自己判断。

### Step 2: 配置 User Rules

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
```

### Step 3: 验证安装

重启 Trae。进入 **Settings > Rules & Skills > Skills**,确认 upstream Superpowers
的技能已加载(类型为 Global)。数量随上游仓库变化,可能变动。新建会话输入类似
「帮我设计一个新功能」的指令,应触发 `brainstorming` 技能。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/trae-superpowers/main/uninstall.sh | bash
```

仅移除 upstream Superpowers 提供的技能,不会动你自己的技能。User Rules 需在 Trae
设置中手动移除。

## 工作原理

- **Skills** 被复制到 Trae 全局技能目录,使其在所有项目中加载。
- **User Rules** 替代 upstream 的 SessionStart Hook,要求 agent 在任何任务前先检查
  是否有匹配的技能。

## 许可证

MIT —— 见 [LICENSE](./LICENSE)。

# Trae Superpowers 安装工程 — 设计文档

- 日期:2026-07-10
- 状态:已通过 brainstorming 评审,待用户确认后进入 writing-plans

## 1. 目标

让 Trae IDE 支持 upstream 项目 [obra/superpowers](https://github.com/obra/superpowers)。
本工程提供安装脚本与分步指导,把 upstream 的 skills 装入 Trae 的全局 skills 目录,
并通过 Trae 的 User Rules 机制替代 upstream 原生的 SessionStart Hook。

## 2. 已确认的关键决策

| # | 决策点 | 结论 |
|---|--------|------|
| 1 | 支持的 Trae 变体 | 同时支持国内版与国际版 |
| 2 | 双语范围 | 仅项目文档双语(README);脚本输出与 skills 内容保持英文原样 |
| 3 | 安装分发方式 | 主推 `curl -fsSL <raw>/install.sh \| bash` 一行流 |
| 4 | skills 写入方式 | `cp -r` 直接写入(跟随软链接落到真实目标,与 upstream 官方一致) |
| 5 | User Rules | 手动配置(脚本不写入用户配置目录),文档提供完整可粘贴文本 |
| 6 | 原方案 Step 3(改 description) | 删除。与 User Rules 功能重叠;sed 改 YAML frontmatter 脆弱;当前 upstream description 已是扩展版 |
| 7 | 卸载 | 提供配套 `uninstall.sh` |
| 8 | 操作系统 | 支持 macOS、Windows、Linux |
| 9 | 路径策略 | 多候选探测:每个变体探测一组候选目录,存在即装 |

## 3. 环境事实(官方文档 + 本机验证)

### 官方文档路径(权威)

据 Trae 官方文档(docs.trae.ai / 火山引擎文档),全局技能目录为:

- 国内版(CN):`~/.trae-cn/skills`(macOS/Linux);`%userprofile%\.trae-cn\skills`(Windows)
- 国际版(intl):`~/.trae/skills`(macOS/Linux);`%userprofile%\.trae\skills`(Windows)
- **macOS 与 Linux 路径完全相同**,因此 Linux 无需任何平台专属逻辑。

来源:
- Trae Skills 官方文档:https://docs.trae.ai/solo/skills
- 火山引擎技能文档:https://www.volcengine.com/docs/86677/2172396
- 社区一键装 skills 工具 sdd-env-cn(路径对照):https://www.npmjs.com/package/sdd-env-cn

### 本机验证发现的别名

本机存在多套目录互为**软链接别名**,均指向同一真实目标:
`~/.trae-cn/skills` → `~/.agents/skills`,且与 `~/.trae-cn/skills` 指向一致(受 `.skill-lock.json` 管理)。

结论:官方命名为 `._agent-cn` / `._agent`;`.trae-cn` / `.trae` 是部分环境的别名。
脚本采用**多候选探测**同时覆盖两套命名,保证跨环境可用。

### 其它事实

- 通过 `cp` 写入 skills 目录是 upstream 官方安装方式,可行且稳妥。
- User Rules 实际存储为用户配置目录下的多个独立 `*.md` 文件,不是单一文件——因此脚本不自动写入,交由用户在设置界面操作。

## 4. 项目结构

```
trae-superpowers/
├── LICENSE
├── README.md              # 英文(默认)
├── README.zh-CN.md        # 中文
├── install.sh             # curl|bash 一行流目标
├── uninstall.sh           # 配套卸载
└── docs/
    └── superpowers/specs/ # 本设计文档所在
```

一键命令形如:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/trae-superpowers/main/install.sh | bash
```

## 5. install.sh 核心逻辑

```
1. 探测已安装的 Trae 变体 —— 对每个变体探测一组候选 skills 目录:
     CN 候选:   ~/.trae-cn/skills, ~/.trae-cn/skills
     intl 候选: ~/.trae/skills,    ~/.trae/skills
   候选中首个存在的父目录即视为该变体已安装。
2. 对命中的目标目录,解析真实路径(跟随软链接)。
3. git clone --depth 1 upstream superpowers → 临时目录。
4. cp -r <tmp>/skills/* → 各命中变体的 skills 目录。
5. 清理临时目录。
6. 打印后续步骤(User Rules 手动配置指引 + 重启提示)。
```

关键防护:

- 所有候选目录都不存在 → 报错并退出(提示未检测到 Trae 安装)。
- `git clone` 失败 → 清理临时目录并退出。
- `cp` 写入前打印将写入哪些目标目录。
- 临时目录使用 `mktemp -d`,`trap` 确保异常时也清理。
- 同一变体多个候选同时命中(互为软链接)时只写一次,避免重复。

## 6. uninstall.sh 核心逻辑

```
1. 用与 install 相同的多候选探测,找出已安装的变体目标目录。
2. 重新获取 upstream skills 清单(或按已知清单)确定哪些是本工程装入的。
3. 从各变体 skills 目录移除对应 skills。
4. 打印提示:User Rules 需用户在设置界面手动移除。
```

安全约束:仅移除 upstream superpowers 提供的 skills,不触碰用户其它 skills;删除前打印将删除的清单。

## 7. 文档内容(README 双语,结构一致)

1. 项目简介 —— 说明「让 Trae 支持 superpowers」是什么、解决什么。
2. 一键安装 —— curl 命令。
3. 手动安装(进阶)—— 分步骤,使用官方路径 + 别名说明:
   - Step 1:克隆 upstream 并复制 skills(区分 CN `._agent-cn` / intl `._agent`,并说明 `.trae-cn` 别名)。
   - Step 2:配置 User Rules(附完整可粘贴文本)。
   - Step 3:验证安装。
4. 配置 User Rules —— 完整文本块。
5. 验证安装 —— 重启 → 查看 Skills 面板(类型 Global)→ 新会话测试(输入「帮我设计一个新功能」应触发 brainstorming)。
   - **不写死数量**:表述为「确认 upstream 全部 skills 已加载(数量随上游变化)」。
6. 卸载说明 / 常见问题。

## 8. User Rules 文本(供文档引用)

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

## 9. 支持的操作系统

Trae IDE 发行 macOS、Windows 与 Linux(.deb / .rpm),故:

- **macOS**:原生运行 `install.sh` / `uninstall.sh`(bash/zsh)。
- **Linux**:原生运行同一套脚本;全局技能路径与 macOS 完全相同(`~/.trae-cn/skills` 等)。
- **Windows**:在 **Git Bash 或 WSL** 中运行同一套 `install.sh` / `uninstall.sh`。
  bash 环境下 `$HOME` 路径可正常解析,无需第二套脚本。

单一 bash 脚本覆盖三个系统。README 双语均在开头标注「Windows 用户请在 Git Bash 或 WSL 中运行」。

## 10. 非目标(YAGNI)

- 不翻译 skills 内容。
- 不自动写入 User Rules。
- 不修改 upstream skill 文件(含 description)。
- 不写 Windows 原生 PowerShell 脚本(Windows 经 Git Bash / WSL 复用 bash 脚本)。

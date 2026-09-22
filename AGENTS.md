# CLAUDE.md

本文件为在此仓库工作的 AI 编码代理提供指引。

## 项目概述

`trae-superpowers` 把上游 [obra/superpowers](https://github.com/obra/superpowers) 的 skills
装入 Trae IDE 的全局 skills 目录；若共享的 `~/.agents/skills` 已有完整 Superpowers，
则直接复用且不接管。项目用 Trae 的 **User Rules** 替代上游原生的 SessionStart Hook，
使 skills 从第一条消息起即生效。

产物是三个自包含的 bash 脚本（`install.sh` / `update.sh` / `uninstall.sh`）加双语文档，没有构建产物、
没有运行时依赖。

## 常用命令

```bash
# 运行全部行为测试（离线、隔离 HOME，不触碰真实环境）
bash tests/run_all.sh

# 单独运行某个测试
bash tests/test_install.sh
bash tests/test_update.sh
bash tests/test_uninstall.sh

# 本地离线跑安装/卸载脚本（用假 skills 源，避免真的 git clone 与写入真实目录）
SUPERPOWERS_SKILLS_SRC=/path/to/fake HOME=/tmp/fakehome bash install.sh
```

关键环境变量：

- `SUPERPOWERS_SKILLS_SRC`：注入本地 skills 源（其下需有 `skills/` 子目录），跳过 `git clone`，
  测试与本地验证均依赖它。
- `SUPERPOWERS_UPSTREAM_URL`：覆盖上游仓库地址，默认 `https://github.com/obra/superpowers.git`。

## 架构与关键文件

- [install.sh](./install.sh)：通过方向键菜单或 `SUPERPOWERS_TARGET` 单选 Trae 目标 → 优先复用
  完整的 `.agents/skills`，否则获取上游 skills 源 → `cp -R` 写入所选 skills 目录并写
  manifest。核心函数 `select_target` / `target_skills_dir` / `agents_superpowers_state` /
  `resolve_src` / `copy_skills` / `write_manifest`。
- [update.sh](./update.sh)：普通模式下唯一 manifest 自动定位，两处都有或都没有时单选；完整
  `.agents` 存在时改由唯一托管 Rule 自动定位，歧义时单选。选定目标后清理孤儿并逐 skill
  清替（先删后拷），最后覆盖写 manifest。
- [uninstall.sh](./uninstall.sh)：完整 `.agents` 存在时无需选择，保留外部安装并清理两个 Trae
  目录中 manifest 管理的副本及托管 Rule；普通模式下唯一 manifest 自动定位，歧义时单选，
  再优先按 manifest 逐名删除（离线可用），无 manifest 时回退到上游 skills 清单。
- [tests/test_helpers.bash](./tests/test_helpers.bash)：断言与隔离环境辅助（`make_temp_home`、
  `make_fake_src`、`assert_*`、`finish_tests`）。兼容 bash 3.2，不用关联数组。
- [docs/superpowers/specs/2026-07-10-trae-superpowers-design.md](./docs/superpowers/specs/2026-07-10-trae-superpowers-design.md)：
  设计文档，记录所有已确认决策与路径依据。改动行为前先读它。
- [README.md](./README.md) / [README.zh-CN.md](./README.zh-CN.md)：英文默认 + 中文，结构须保持一致。

### 支持的 Trae 变体目录

两个候选根目录（`$HOME` 下）：`.trae-cn`（CN）、`.trae`（intl）。每次安装只选择一个目标，
目录不存在时自动创建；再次选择另一目标不会迁移或清理旧目标。`._agent-cn` / `._agent`
不再探测、迁移或清理。

`~/.agents/skills` 是只读复用源。仅当 `using-superpowers`、`brainstorming`、
`test-driven-development`、`systematic-debugging` 四个目录下的 `SKILL.md` 同时存在时，
才视为完整 Superpowers。完整时 install/update 不获取上游、不修改 `.agents`，只在定位或
选择的 Trae 目标中清理 manifest 副本并维护 User Rule；uninstall 永不删除 `.agents`，并
清理两种 Trae 目录中的托管痕迹。残缺安装保持原样，并走正常 Trae 目录安装或更新。

## 关键约定与约束

- **脚本自包含**：脚本要能被 `curl -fsSL ... | bash` 直接执行，禁止 `source` 外部文件。
- **兼容 bash 3.2**（macOS 自带）：不使用关联数组、`mapfile` 等 4.x 特性。
- **隐藏目录名用八进制字节转义构造**（`\056`="."）：本环境实测会改写连续词元
  `dot-trae`，直接写字面量会被污染。新增/修改隐藏目录名必须沿用此写法。
- **单一 bash 脚本覆盖 macOS / Linux / Windows**：Linux 路径与 macOS 相同；Windows 走
  Git Bash / WSL 复用同一脚本，不写 PowerShell 脚本。
- **代码注释用中文**（跟随现有脚本风格），面向用户的脚本输出与文档（除中文 README 外）用英文。
- **删除前先打印清单**：`install.sh` 写入前打印目标目录，`uninstall.sh` 删除前打印将删的 skill。
- **manifest 追踪**：每个 skills 目录根下 `.superpowers-manifest`（纯文本，每行一个 skill 名）
  记录本工程装入的 skill。install/update 写入，uninstall 优先据此删除；孤儿删除严格限定
  manifest 范围，不触碰用户自有 skill。`.agents/skills` 永不写 manifest。
- **自动写入 User Rules**：install/update 把完整版 Superpowers 规则写入各变体
  `user_rules/rule-*.md`，以标记 `<!-- trae-superpowers-managed-rule -->` 识别，
  幂等覆盖；uninstall 按标记对称删除。只碰带标记文件，不触碰用户自有规则。
  `RULE_BODY` 以 install.sh 为准，update.sh 逐字一致。生效不承诺免重启（需 UI 验收）。
- **非交互选择**：无 TTY 时必须设置 `SUPERPOWERS_TARGET=trae-cn|trae`；禁止静默默认。
- **外部目录护栏**：若所选 `.trae*/skills` 的真实路径指向 `.agents/skills`，任何普通模式的
  安装、更新或卸载都必须拒绝，确保 `.agents` 永不被间接修改。

## 非目标（YAGNI）

- 不翻译 skills 内容。
- **不修改上游 skill 文件（含 SKILL.md 的 description）**：用 `sed` 改 YAML frontmatter 脆弱，
  且与 User Rules 功能重叠——触发增强一律靠 User Rules。

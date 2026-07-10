# CLAUDE.md

本文件为在此仓库工作的 AI 编码代理提供指引。

## 项目概述

`trae-superpowers` 把上游 [obra/superpowers](https://github.com/obra/superpowers) 的 skills
装入 Trae（_Agent）IDE 的全局 skills 目录，并用 Trae 的 **User Rules** 替代上游原生的
SessionStart Hook，使 skills 从第一条消息起即生效。

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

- [install.sh](./install.sh)：探测已安装的 Trae 变体 → 获取上游 skills 源 → `cp -R` 写入各变体
  的 skills 目录，并写入 manifest。核心函数 `variant_roots` / `detect_skill_dirs` / `resolve_src` /
  `copy_skills` / `write_manifest`。
- [update.sh](./update.sh)：用相同探测逻辑找到目标目录，读旧 manifest 计算孤儿
  （OLD∩¬NEW）并删除，再对上游全部 skill 逐 skill 清替（先删后拷）实现目录级镜像，
  最后覆盖写 manifest。核心函数 `mirror_skills` / `remove_orphans` / `write_manifest`。
- [uninstall.sh](./uninstall.sh)：用相同探测逻辑找到目标目录，**优先按 manifest 逐名删除**
  （离线可用）并删除 manifest；manifest 不存在时回退到"按上游 skills 清单反推删除"。
  只移除本工程装入的 skill，保留用户自有 skill。
- [tests/test_helpers.bash](./tests/test_helpers.bash)：断言与隔离环境辅助（`make_temp_home`、
  `make_fake_src`、`assert_*`、`finish_tests`）。兼容 bash 3.2，不用关联数组。
- [docs/superpowers/specs/2026-07-10-trae-superpowers-design.md](./docs/superpowers/specs/2026-07-10-trae-superpowers-design.md)：
  设计文档，记录所有已确认决策与路径依据。改动行为前先读它。
- [README.md](./README.md) / [README.zh-CN.md](./README.zh-CN.md)：英文默认 + 中文，结构须保持一致。

### 支持的 Trae 变体目录

四个候选根目录（`$HOME` 下）：`._agent-cn`（CN）、`._agent`（intl）、`.trae-cn`、`.trae`。
官方命名为 `._agent-cn` / `._agent`；`.trae-cn` / `.trae` 是部分环境的软链接别名。探测时对多个
候选去重（`pwd -P` 解析真实路径），互为软链接的目标只写一次。

## 关键约定与约束

- **脚本自包含**：脚本要能被 `curl -fsSL ... | bash` 直接执行，禁止 `source` 外部文件。
- **兼容 bash 3.2**（macOS 自带）：不使用关联数组、`mapfile` 等 4.x 特性。
- **变体名用八进制字节转义构造**（`\056`="."、`\137`="_"）：本环境实测会改写连续词元
  `dot-underscore-agent` / `dot-trae`，直接写字面量会被污染。新增/修改变体名必须沿用此写法。
- **单一 bash 脚本覆盖 macOS / Linux / Windows**：Linux 路径与 macOS 相同；Windows 走
  Git Bash / WSL 复用同一脚本，不写 PowerShell 脚本。
- **代码注释用中文**（跟随现有脚本风格），面向用户的脚本输出与文档（除中文 README 外）用英文。
- **删除前先打印清单**：`install.sh` 写入前打印目标目录，`uninstall.sh` 删除前打印将删的 skill。
- **manifest 追踪**：每个 skills 目录根下 `.superpowers-manifest`（纯文本，每行一个 skill 名）
  记录本工程装入的 skill。install/update 写入，uninstall 优先据此删除；孤儿删除严格限定
  manifest 范围，不触碰用户自有 skill。

## 非目标（YAGNI）

- 不翻译 skills 内容。
- 不自动写入 User Rules（脚本不碰用户配置目录，由用户在设置界面手动粘贴）。
- **不修改上游 skill 文件（含 SKILL.md 的 description）**：用 `sed` 改 YAML frontmatter 脆弱，
  且与 User Rules 功能重叠——触发增强一律靠 User Rules。

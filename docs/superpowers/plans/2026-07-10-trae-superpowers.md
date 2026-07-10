# Trae Superpowers 安装工程 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个开源工程,通过一键 bash 脚本(及手动步骤)把 upstream obra/superpowers 的 skills 装入 Trae IDE 的全局技能目录,支持国内/国际版、macOS/Linux/Windows(Git Bash),并提供中英双语文档。

**Architecture:** 两个自包含的 bash 脚本(`install.sh` / `uninstall.sh`),各自内联"多候选路径探测"逻辑(因 `curl|bash` 无法 source 外部文件)。脚本通过读取 `$HOME` 探测已安装的 Trae 变体,`cp -r` 写入 skills;通过 `SUPERPOWERS_SKILLS_SRC` 环境变量支持离线/隔离测试(跳过 git clone)。测试用纯 bash(零依赖)+ 临时 HOME 隔离,兼容 macOS 自带 bash 3.2。

**Tech Stack:** Bash(POSIX 兼容,兼容 bash 3.2)、git、纯 bash 测试脚本、Markdown 文档。

---

## File Structure

- `install.sh` — 一键安装脚本(curl|bash 目标)。职责:探测变体 → clone upstream → 复制 skills → 提示后续步骤。
- `uninstall.sh` — 卸载脚本。职责:探测变体 → 移除本工程装入的 skills → 提示手动移除 User Rules。
- `tests/test_helpers.bash` — 测试公共函数(setup 临时 HOME、断言函数、构造假 skills 源)。
- `tests/test_install.sh` — install.sh 的行为测试。
- `tests/test_uninstall.sh` — uninstall.sh 的行为测试。
- `tests/run_all.sh` — 运行全部测试的入口。
- `README.md` — 英文文档(默认)。
- `README.zh-CN.md` — 中文文档。
- `LICENSE` — MIT 许可证。
- `.gitignore` — 忽略临时/系统文件。

**关键接口约定(全脚本一致):**

- 环境变量 `SUPERPOWERS_SKILLS_SRC`:若已设置且为目录,脚本用它作为 skills 源(跳过 git clone)。用于测试。
- 环境变量 `SUPERPOWERS_UPSTREAM_URL`:upstream 仓库地址,默认 `https://github.com/obra/superpowers.git`。
- 候选路径函数 `detect_skill_dirs`:输出已命中的目标 skills 目录(每行一个,已去重)。
  - CN 候选:`$HOME/.trae-cn/skills`, `$HOME/.trae-cn/skills`
  - intl 候选:`$HOME/.trae/skills`, `$HOME/.trae/skills`
- 退出码:成功 `0`;未检测到任何 Trae 变体 `3`;git clone 失败 `4`;源目录无 skills `5`。

---

## Task 1: 初始化仓库骨架(LICENSE、.gitignore、目录)

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `tests/.gitkeep`

- [ ] **Step 1: 创建 MIT LICENSE**

创建 `LICENSE`,内容为标准 MIT 文本(年份 2026,版权人占位为仓库 owner):

```text
MIT License

Copyright (c) 2026 trae-superpowers contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: 创建 .gitignore**

创建 `.gitignore`:

```gitignore
# macOS
.DS_Store
# 测试临时目录
tests/tmp/
# 编辑器
.idea/
.vscode/
```

- [ ] **Step 3: 创建 tests 占位**

创建空文件 `tests/.gitkeep`(保证空目录入库)。

- [ ] **Step 4: Commit**

```bash
git add LICENSE .gitignore tests/.gitkeep
git commit -m "chore: scaffold repo with LICENSE and gitignore"
```

---

## Task 2: 测试辅助库(隔离 HOME + 断言 + 假 skills 源)

**Files:**
- Create: `tests/test_helpers.bash`

- [ ] **Step 1: 写测试辅助库**

创建 `tests/test_helpers.bash`。它提供:临时 HOME 创建/清理、断言函数、构造一个假的 upstream skills 源目录(含若干假 skill)。所有函数带注释。

```bash
#!/usr/bin/env bash
# 测试公共辅助函数:隔离环境、断言、构造假 skills 源。
# 兼容 bash 3.2(macOS 自带),不使用关联数组等 4.x 特性。

# 全局计数器:记录通过/失败断言数
TESTS_PASSED=0
TESTS_FAILED=0

# make_temp_home: 创建一个隔离的临时 HOME 目录并回显其路径。
# 用法: TMP_HOME="$(make_temp_home)"
make_temp_home() {
  mktemp -d "${TMPDIR:-/tmp}/sp_home.XXXXXX"
}

# make_fake_src: 在给定目录下构造一个假的 upstream 布局:<dir>/skills/<skill>/SKILL.md
# 参数: $1=源根目录  $2..=skill 名称列表
make_fake_src() {
  local root="$1"; shift
  local name
  for name in "$@"; do
    mkdir -p "$root/skills/$name"
    printf '%s\n' "# $name" > "$root/skills/$name/SKILL.md"
  done
}

# assert_dir_exists: 断言目录存在。参数: $1=路径 $2=用例描述
assert_dir_exists() {
  if [ -d "$1" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$2"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (missing dir: %s)\n' "$2" "$1"
  fi
}

# assert_dir_absent: 断言目录不存在。参数: $1=路径 $2=用例描述
assert_dir_absent() {
  if [ ! -d "$1" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$2"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (unexpected dir: %s)\n' "$2" "$1"
  fi
}

# assert_exit_code: 断言退出码。参数: $1=期望码 $2=实际码 $3=用例描述
assert_exit_code() {
  if [ "$1" = "$2" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$3"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (want exit %s, got %s)\n' "$3" "$1" "$2"
  fi
}

# finish_tests: 打印汇总并按失败数返回退出码。
finish_tests() {
  printf '\n--- %d passed, %d failed ---\n' "$TESTS_PASSED" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
```

- [ ] **Step 2: 验证辅助库可被 source(冒烟测试)**

Run:
```bash
bash -c 'source tests/test_helpers.bash && H=$(make_temp_home) && make_fake_src "$H/src" a b && ls "$H/src/skills"'
```
Expected: 输出两行 `a` 和 `b`(证明构造假源成功)。

- [ ] **Step 3: Commit**

```bash
git add tests/test_helpers.bash
git commit -m "test: add shell test helpers (isolated HOME, assertions, fake src)"
```

---

## Task 3: install.sh — 探测逻辑(TDD 第一步)

**Files:**
- Create: `install.sh`
- Create: `tests/test_install.sh`

- [ ] **Step 1: 写失败测试 — 未检测到变体应退出码 3**

创建 `tests/test_install.sh`:

```bash
#!/usr/bin/env bash
# install.sh 行为测试。用隔离 HOME + 假 skills 源,离线运行。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/test_helpers.bash"
INSTALL="$HERE/../install.sh"

# 用例1: HOME 下无任何 Trae 变体目录 → 退出码 3
t_no_variant() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 3 "$?" "无变体时退出码为 3"
  rm -rf "$home" "$src"
}

t_no_variant
finish_tests
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/test_install.sh`
Expected: FAIL —— 因为 `install.sh` 尚不存在,bash 报错或退出码非 3。

- [ ] **Step 3: 写 install.sh 最小实现(探测 + 退出码 3)**

创建 `install.sh`:

```bash
#!/usr/bin/env bash
# install.sh — 把 upstream superpowers 的 skills 装入 Trae 全局技能目录。
# 自包含:不 source 外部文件(需兼容 curl|bash)。兼容 bash 3.2。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"

# detect_skill_dirs: 探测已安装 Trae 变体的 skills 目录,逐行输出(已去重真实路径)。
# CN 候选: ~/.trae-cn/skills, ~/.trae-cn/skills
# intl 候选: ~/.trae/skills, ~/.trae/skills
detect_skill_dirs() {
  local candidates="$HOME/.trae-cn/skills $HOME/.trae-cn/skills $HOME/.trae/skills $HOME/.trae/skills"
  local seen="" c real
  for c in $candidates; do
    # 命中条件:候选目录本身存在,或其父目录(变体根)存在
    if [ -d "$c" ] || [ -d "$(dirname "$c")" ]; then
      # 解析真实路径以去重软链接别名
      if [ -d "$c" ]; then
        real="$(cd "$c" 2>/dev/null && pwd -P)"
      else
        real="$c"
      fi
      case " $seen " in
        *" $real "*) : ;;              # 已见过,跳过
        *) seen="$seen $real"; printf '%s\n' "$c" ;;
      esac
    fi
  done
}

main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected (looked for ._agent-cn/._agent/.trae-cn/.trae).\n' >&2
    return 3
  fi
  printf 'Detected target skill dirs:\n%s\n' "$dirs"
  return 0
}

main "$@"
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash tests/test_install.sh`
Expected: `PASS: 无变体时退出码为 3` 且 `1 passed, 0 failed`。

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.sh
git commit -m "feat: add install.sh variant detection (exit 3 when none)"
```

---

## Task 4: install.sh — 复制 skills 到命中目录

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_install.sh`

- [ ] **Step 1: 写失败测试 — 命中 CN 变体时应复制 skills**

在 `tests/test_install.sh` 的 `t_no_variant` 之后、`finish_tests` 之前插入新用例并调用:

```bash
# 用例2: 存在 CN 变体根(~/._agent-cn) → skills 被复制进去
t_install_cn() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/._agent-cn"          # 只建变体根,不建 skills 子目录
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "命中 CN 变体时退出码为 0"
  assert_dir_exists "$home/.trae-cn/skills/using-superpowers" "using-superpowers 被复制"
  assert_dir_exists "$home/.trae-cn/skills/brainstorming" "brainstorming 被复制"
  rm -rf "$home" "$src"
}
```

并在 `t_no_variant` 调用行下方添加:

```bash
t_install_cn
```

- [ ] **Step 2: 运行测试确认新用例失败**

Run: `bash tests/test_install.sh`
Expected: 用例2 FAIL(skills 尚未被复制)。

- [ ] **Step 3: 在 install.sh 中实现获取源 + 复制**

在 `install.sh` 的 `detect_skill_dirs` 之后、`main` 之前新增两个函数:

```bash
# resolve_src: 得到 skills 源根目录(含 skills/ 子目录)。
# 若设置了 SUPERPOWERS_SKILLS_SRC 则直接用(测试用);否则 git clone upstream 到临时目录。
# 通过全局变量 SRC_ROOT 回传;通过 CLEANUP_DIR 记录需清理的临时目录。
SRC_ROOT=""
CLEANUP_DIR=""
resolve_src() {
  if [ -n "${SUPERPOWERS_SKILLS_SRC:-}" ] && [ -d "$SUPERPOWERS_SKILLS_SRC" ]; then
    SRC_ROOT="$SUPERPOWERS_SKILLS_SRC"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/superpowers.XXXXXX")"
  CLEANUP_DIR="$tmp"
  if ! git clone --depth 1 "$UPSTREAM_URL" "$tmp" >/dev/null 2>&1; then
    printf 'Error: git clone failed from %s\n' "$UPSTREAM_URL" >&2
    return 4
  fi
  SRC_ROOT="$tmp"
  return 0
}

# copy_skills: 把 SRC_ROOT/skills/* 复制到指定目标目录(自动 mkdir -p)。
# 参数: $1=目标 skills 目录
copy_skills() {
  local dest="$1"
  mkdir -p "$dest"
  cp -R "$SRC_ROOT"/skills/. "$dest"/
}
```

然后把 `main` 改为:

```bash
main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected (looked for ._agent-cn/._agent/.trae-cn/.trae).\n' >&2
    return 3
  fi

  resolve_src || return $?
  # 校验源里确有 skills
  if [ ! -d "$SRC_ROOT/skills" ] || [ -z "$(ls -A "$SRC_ROOT/skills" 2>/dev/null)" ]; then
    printf 'Error: no skills found in source (%s/skills).\n' "$SRC_ROOT" >&2
    [ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"
    return 5
  fi

  local d
  printf 'Installing skills into:\n%s\n' "$dirs"
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    copy_skills "$d"
  done <<EOF
$dirs
EOF

  [ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"

  printf '\nDone. Next steps:\n'
  printf '  1. Configure User Rules in Trae Settings (see README).\n'
  printf '  2. Restart Trae IDE.\n'
  return 0
}
```

- [ ] **Step 4: 运行测试确认全部通过**

Run: `bash tests/test_install.sh`
Expected: 3 个断言(用例1)+ 3 个断言(用例2)全部 PASS,`0 failed`。

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.sh
git commit -m "feat: install.sh copies upstream skills into detected dirs"
```

---

## Task 5: install.sh — 去重校验(软链接别名只写一次)

**Files:**
- Modify: `tests/test_install.sh`

- [ ] **Step 1: 写测试 — 两个候选互为软链接时只应命中一次**

在 `finish_tests` 之前插入用例并调用:

```bash
# 用例3: ~/.trae-cn/skills 是指向 ~/.trae-cn/skills 的软链接 → 只安装一次(内容一致)
t_dedup_symlink() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/.trae-cn/skills"
  # .trae-cn 整体软链到 ._agent-cn(模拟本机别名)
  ln -s "$home/._agent-cn" "$home/.trae-cn"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "软链接别名场景退出码为 0"
  assert_dir_exists "$home/.trae-cn/skills/using-superpowers" "别名场景 skill 已安装"
  rm -rf "$home" "$src"
}
```

调用:

```bash
t_dedup_symlink
```

- [ ] **Step 2: 运行测试**

Run: `bash tests/test_install.sh`
Expected: 全部 PASS。`detect_skill_dirs` 已用 `pwd -P` 解析真实路径去重,故此用例应直接通过(回归保护)。

- [ ] **Step 3: Commit**

```bash
git add tests/test_install.sh
git commit -m "test: cover symlink alias dedup in install detection"
```

---

## Task 6: uninstall.sh — 移除已装 skills

**Files:**
- Create: `uninstall.sh`
- Create: `tests/test_uninstall.sh`

- [ ] **Step 1: 写失败测试 — 卸载应移除本工程装入的 skills**

创建 `tests/test_uninstall.sh`:

```bash
#!/usr/bin/env bash
# uninstall.sh 行为测试。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/test_helpers.bash"
UNINSTALL="$HERE/../uninstall.sh"

# 用例1: 已装入的 skills 应被移除,退出码 0
t_uninstall_cn() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/.trae-cn/skills/using-superpowers"
  mkdir -p "$home/.trae-cn/skills/brainstorming"
  # 用户自有 skill,不应被删
  mkdir -p "$home/.trae-cn/skills/my-own-skill"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "卸载退出码为 0"
  assert_dir_absent "$home/.trae-cn/skills/using-superpowers" "upstream skill 被移除"
  assert_dir_absent "$home/.trae-cn/skills/brainstorming" "upstream skill 被移除(2)"
  assert_dir_exists "$home/.trae-cn/skills/my-own-skill" "用户自有 skill 保留"
  rm -rf "$home" "$src"
}

t_uninstall_cn
finish_tests
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/test_uninstall.sh`
Expected: FAIL(`uninstall.sh` 不存在)。

- [ ] **Step 3: 写 uninstall.sh**

创建 `uninstall.sh`。复用与 install 相同的探测逻辑(内联),按源 skills 清单逐个移除:

```bash
#!/usr/bin/env bash
# uninstall.sh — 从 Trae 全局技能目录移除本工程装入的 upstream skills。
# 自包含,兼容 bash 3.2。仅删除 upstream 提供的 skill,不触碰用户其它 skill。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"

# detect_skill_dirs: 同 install.sh,探测已安装变体的 skills 目录(去重)。
detect_skill_dirs() {
  local candidates="$HOME/.trae-cn/skills $HOME/.trae-cn/skills $HOME/.trae/skills $HOME/.trae/skills"
  local seen="" c real
  for c in $candidates; do
    if [ -d "$c" ] || [ -d "$(dirname "$c")" ]; then
      if [ -d "$c" ]; then
        real="$(cd "$c" 2>/dev/null && pwd -P)"
      else
        real="$c"
      fi
      case " $seen " in
        *" $real "*) : ;;
        *) seen="$seen $real"; printf '%s\n' "$c" ;;
      esac
    fi
  done
}

# resolve_src: 得到 skills 清单来源。测试用 SUPERPOWERS_SKILLS_SRC;否则 clone upstream。
SRC_ROOT=""
CLEANUP_DIR=""
resolve_src() {
  if [ -n "${SUPERPOWERS_SKILLS_SRC:-}" ] && [ -d "$SUPERPOWERS_SKILLS_SRC" ]; then
    SRC_ROOT="$SUPERPOWERS_SKILLS_SRC"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/superpowers.XXXXXX")"
  CLEANUP_DIR="$tmp"
  if ! git clone --depth 1 "$UPSTREAM_URL" "$tmp" >/dev/null 2>&1; then
    printf 'Error: git clone failed from %s\n' "$UPSTREAM_URL" >&2
    return 4
  fi
  SRC_ROOT="$tmp"
  return 0
}

main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected.\n' >&2
    return 3
  fi

  resolve_src || return $?
  if [ ! -d "$SRC_ROOT/skills" ]; then
    printf 'Error: no skills list found in source.\n' >&2
    [ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"
    return 5
  fi

  local d name
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    [ -d "$d" ] || continue
    for name in "$SRC_ROOT"/skills/*/; do
      name="$(basename "$name")"
      if [ -d "$d/$name" ]; then
        printf 'Removing %s\n' "$d/$name"
        rm -rf "$d/$name"
      fi
    done
  done <<EOF
$dirs
EOF

  [ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"
  printf '\nDone. Note: remove the Superpowers User Rules manually in Trae Settings.\n'
  return 0
}

main "$@"
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash tests/test_uninstall.sh`
Expected: 4 个断言全部 PASS,`0 failed`。

- [ ] **Step 5: Commit**

```bash
git add uninstall.sh tests/test_uninstall.sh
git commit -m "feat: add uninstall.sh removing only upstream skills"
```

---

## Task 7: 测试入口 run_all.sh

**Files:**
- Create: `tests/run_all.sh`

- [ ] **Step 1: 写测试入口**

创建 `tests/run_all.sh`:

```bash
#!/usr/bin/env bash
# 运行全部 shell 测试,任一失败则整体失败。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$HERE"/test_install.sh "$HERE"/test_uninstall.sh; do
  printf '\n=== Running %s ===\n' "$(basename "$t")"
  bash "$t" || rc=1
done
exit "$rc"
```

- [ ] **Step 2: 运行全部测试**

Run: `bash tests/run_all.sh`
Expected: 两个测试文件均输出 PASS 汇总,整体退出码 0。

- [ ] **Step 3: Commit**

```bash
git add tests/run_all.sh
git commit -m "test: add run_all.sh entrypoint"
```

---

## Task 8: 英文 README

**Files:**
- Create: `README.md`

- [ ] **Step 1: 写 README.md**

创建 `README.md`,包含以下小节(完整内容,非占位):

````markdown
# Trae Superpowers

Bring [obra/superpowers](https://github.com/obra/superpowers) skills to the Trae IDE.

This project installs the upstream Superpowers skills into Trae's global skills
directory and uses Trae's **User Rules** to replace the upstream SessionStart
hook, so the skills are active from the first message.

English | [简体中文](./README.zh-CN.md)

> **Windows users:** run the shell commands below in **Git Bash** or **WSL**.

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/trae-superpowers/main/install.sh | bash
```

The script detects your Trae variant (CN / international) and copies all
upstream skills into the correct global skills directory. It supports macOS,
Linux, and Windows (Git Bash / WSL).

After it finishes, complete **Configure User Rules** below and restart Trae.

## Manual install (advanced)

### Step 1: Clone upstream and copy skills

```bash
git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers

# Global skills dir (CN version; international uses ._agent).
# Note: on some setups ~/.trae-cn is a symlink alias of ~/._agent-cn.
mkdir -p ~/.trae-cn/skills
cp -R /tmp/superpowers/skills/. ~/.trae-cn/skills/

rm -rf /tmp/superpowers
```

For the international version, replace `._agent-cn` with `._agent`.

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

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/trae-superpowers/main/uninstall.sh | bash
```

This removes only the skills provided by upstream Superpowers; your own skills
are left untouched. Remove the User Rules manually in Trae Settings.

## How it works

- **Skills** are copied into Trae's global skills directory so they load in
  every project.
- **User Rules** replace the upstream SessionStart hook, instructing the agent
  to check for a relevant skill before any task.

## License

MIT — see [LICENSE](./LICENSE).
````

- [ ] **Step 2: 校验 Markdown 链接与代码块完整**

Run: `grep -c '```' README.md`
Expected: 输出为偶数(所有代码围栏成对闭合)。

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add English README"
```

---

## Task 9: 中文 README

**Files:**
- Create: `README.zh-CN.md`

- [ ] **Step 1: 写 README.zh-CN.md**

创建 `README.zh-CN.md`,与英文版结构一致的中文翻译(完整内容):

````markdown
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

# 全局技能目录(国内版;国际版用 ._agent)。
# 注意:部分环境下 ~/.trae-cn 是 ~/._agent-cn 的软链接别名。
mkdir -p ~/.trae-cn/skills
cp -R /tmp/superpowers/skills/. ~/.trae-cn/skills/

rm -rf /tmp/superpowers
```

国际版请把 `._agent-cn` 换成 `._agent`。

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
````

- [ ] **Step 2: 校验代码块闭合**

Run: `grep -c '```' README.zh-CN.md`
Expected: 输出为偶数。

- [ ] **Step 3: Commit**

```bash
git add README.zh-CN.md
git commit -m "docs: add Simplified Chinese README"
```

---

## Task 10: 端到端联调(可选真实 clone)+ 最终校验

**Files:**
- Modify: 无(仅运行验证)

- [ ] **Step 1: 全量测试**

Run: `bash tests/run_all.sh`
Expected: 全部 PASS,退出码 0。

- [ ] **Step 2: 真实 clone 冒烟(需联网)——验证 install 探测 + 复制真实 upstream**

Run:
```bash
TMP="$(mktemp -d)"; mkdir -p "$TMP/._agent-cn"
HOME="$TMP" bash install.sh
ls "$TMP/.trae-cn/skills" | head
rm -rf "$TMP"
```
Expected: 输出 "Installing skills into ..." 并列出 upstream 的 skill 目录(如 `brainstorming`、`using-superpowers` 等);退出码 0。
(若无网络则跳过此步,依赖 Task 3-6 的离线测试覆盖。)

- [ ] **Step 3: 脚本静态检查(若安装了 shellcheck)**

Run: `command -v shellcheck >/dev/null && shellcheck install.sh uninstall.sh || echo "shellcheck not installed, skipping"`
Expected: 无 error 级问题,或提示跳过。

- [ ] **Step 4: 最终提交(如有 lint 修正)**

```bash
git add -A
git commit -m "chore: final verification pass" || echo "nothing to commit"
```

---

## Self-Review 记录

- **Spec 覆盖:** ①双变体探测→Task3;②多候选路径+去重→Task3/5;③curl|bash 一行流→自包含脚本+Task8/9 文档;④cp 写入→Task4;⑤User Rules 手动→Task8/9 文档,脚本不写;⑥不改 description→计划中脚本不触碰 upstream 文件;⑦uninstall→Task6;⑧macOS/Linux/Windows→脚本纯 bash + 文档 Windows 提示;⑨双语文档→Task8/9。全部有对应任务。
- **占位符扫描:** 无 TBD/TODO;`<owner>` 是 README 中明示的仓库占位符(用户发布时替换),已在文档内说明语义。
- **类型/命名一致性:** `detect_skill_dirs`、`resolve_src`、`copy_skills`、`SRC_ROOT`、`CLEANUP_DIR`、`SUPERPOWERS_SKILLS_SRC`、`SUPERPOWERS_UPSTREAM_URL` 在 install/uninstall/测试中命名一致;退出码 3/4/5 定义统一。

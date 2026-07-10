# Skill 更新能力 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 trae-superpowers 新增 `update.sh`，通过 manifest 机制精确镜像上游 skills（更新内容 + 删除孤儿），并让 install/uninstall 联动读写 manifest。

**Architecture:** 在每个变体 skills 目录根下维护纯文本 manifest（`.superpowers-manifest`，每行一个 skill 名），作为 install/update/uninstall 三脚本共享的"本工程装入清单"。install 复制后写 manifest；update 读旧 manifest 算孤儿（OLD∩¬NEW）删除、逐 skill 清替、写新 manifest；uninstall 优先按 manifest 删除，缺失时回退旧逻辑。孤儿删除严格限定 manifest 范围，绝不触碰用户自有 skill。

**Tech Stack:** 纯 bash（兼容 bash 3.2，macOS 自带）、无外部依赖、自包含脚本（可 `curl | bash`）；测试用隔离 HOME + 假 skills 源离线运行。

---

## 文件结构

- **Modify** `tests/test_helpers.bash`：新增 `assert_file_exists` / `assert_file_absent` / `assert_file_contains`。
- **Modify** `install.sh`：`copy_skills` 后新增 `write_manifest`。
- **Create** `update.sh`：精确镜像更新脚本（自包含，内联共享函数）。
- **Modify** `uninstall.sh`：优先按 manifest 删除，缺失时回退现有逻辑。
- **Create** `tests/test_update.sh`：update 行为测试。
- **Modify** `tests/test_install.sh`：install 后断言 manifest 生成。
- **Modify** `tests/test_uninstall.sh`：新增"按 manifest 卸载"用例。
- **Modify** `tests/run_all.sh`：把 `test_update.sh` 加入循环。
- **Modify** `README.md` / `README.zh-CN.md`：新增 Update 章节 + manifest 说明。
- **Modify** `CLAUDE.md`：补 update.sh 命令与架构说明。

**Manifest 约定（贯穿全计划）**
- 文件名常量：`.superpowers-manifest`
- 位置：变体 skills 目录根下，如 `$dst/.superpowers-manifest`
- 格式：纯文本，每行一个 skill 名，无元数据。

---

## Task 1: 测试 helper 新增文件断言

**Files:**
- Modify: `tests/test_helpers.bash`

- [ ] **Step 1: 在 test_helpers.bash 的 assert_dir_absent 之后、finish_tests 之前插入三个文件断言函数**

在 [tests/test_helpers.bash](../../../tests/test_helpers.bash) 中，`assert_dir_absent` 函数结束（第 46 行 `}`）之后插入：

```bash
# assert_file_exists: 断言文件存在。参数: $1=路径 $2=用例描述
assert_file_exists() {
  if [ -f "$1" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$2"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (missing file: %s)\n' "$2" "$1"
  fi
}

# assert_file_absent: 断言文件不存在。参数: $1=路径 $2=用例描述
assert_file_absent() {
  if [ ! -f "$1" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$2"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (unexpected file: %s)\n' "$2" "$1"
  fi
}

# assert_file_contains: 断言文件按整行包含某字符串。参数: $1=路径 $2=期望整行内容 $3=用例描述
assert_file_contains() {
  if [ -f "$1" ] && grep -qx "$2" "$1"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$3"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (file %s missing line: %s)\n' "$3" "$1" "$2"
  fi
}
```

- [ ] **Step 2: 语法检查通过**

Run: `bash -n tests/test_helpers.bash`
Expected: 无输出、退出码 0（语法正确）。

- [ ] **Step 3: 现有测试仍全绿（回归保护）**

Run: `bash tests/run_all.sh`
Expected: 末尾打印各测试的 `--- N passed, 0 failed ---`，整体退出码 0。

- [ ] **Step 4: Commit**

```bash
git add tests/test_helpers.bash
git commit -m "test: add file assertion helpers for manifest checks"
```

---

## Task 2: install.sh 写 manifest（先写测试）

**Files:**
- Modify: `tests/test_install.sh`
- Modify: `install.sh`

- [ ] **Step 1: 在 test_install.sh 的 t_variant_case 中追加 manifest 断言**

在 [tests/test_install.sh](../../../tests/test_install.sh) 的 `t_variant_case`（第 27-37 行）里，`assert_dir_exists ".../brainstorming" ...` 那行之后、`rm -rf "$home" "$src"` 之前插入：

```bash
  assert_file_exists "$home/$root/skills/.superpowers-manifest" "$label: manifest 已生成"
  assert_file_contains "$home/$root/skills/.superpowers-manifest" "using-superpowers" "$label: manifest 含 using-superpowers"
  assert_file_contains "$home/$root/skills/.superpowers-manifest" "brainstorming" "$label: manifest 含 brainstorming"
```

- [ ] **Step 2: 运行 install 测试，确认新断言 FAIL**

Run: `bash tests/test_install.sh`
Expected: 出现 `FAIL: ...: manifest 已生成 (missing file: ...)` 等失败行，末尾 failed 计数 > 0。

- [ ] **Step 3: 在 install.sh 中新增 MANIFEST 常量与 write_manifest 函数**

在 [install.sh](../../../install.sh) 中，`UPSTREAM_URL=...` 那行（第 10 行）之后新增常量：

```bash
# manifest 文件名:记录本工程装入的 skill 名单,供 update/uninstall 精确定位。
MANIFEST=".superpowers-manifest"
```

在 `copy_skills` 函数（第 63-67 行）之后新增：

```bash
# write_manifest: 把源目录下所有 skill 名逐行写入目标 skills 目录的 manifest。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
write_manifest() {
  local src="$1" dst="$2" entry name
  : > "$dst/$MANIFEST"                    # 清空/新建 manifest
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    printf '%s\n' "$name" >> "$dst/$MANIFEST"
  done
}
```

- [ ] **Step 4: 在 install.sh 的安装循环里调用 write_manifest**

在 [install.sh](../../../install.sh) 的 `while` 安装循环（第 90-96 行）中，`copy_skills "$src" "$d"` 那行之后新增一行：

```bash
    write_manifest "$src" "$d"
```

修改后该循环体应为：

```bash
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf 'Installing skills into: %s\n' "$d"
    copy_skills "$src" "$d"
    write_manifest "$src" "$d"
  done <<EOF
$dirs
EOF
```

- [ ] **Step 5: 运行 install 测试，确认全绿**

Run: `bash tests/test_install.sh`
Expected: 全部 `PASS`，末尾 `--- N passed, 0 failed ---`，退出码 0。

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/test_install.sh
git commit -m "feat: write manifest on install to track project-owned skills"
```

---

## Task 3: update.sh 骨架 —— 无变体报错（先写测试）

**Files:**
- Create: `tests/test_update.sh`
- Create: `update.sh`

- [ ] **Step 1: 创建 tests/test_update.sh，只含"无变体退出码 3"用例**

Create `tests/test_update.sh`：

```bash
#!/usr/bin/env bash
# update.sh 行为测试。用隔离 HOME + 假 skills 源,离线运行。
# 变体名用八进制字节转义构造,规避环境对连续词元的改写。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/test_helpers.bash"
UPDATE="$HERE/../update.sh"

V_AGENT_CN="$(printf '\056\137agent-cn')"
MANIFEST=".superpowers-manifest"

# 用例1: HOME 下无任何变体 → 退出码 3
t_no_variant() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 3 "$?" "无变体时退出码为 3"
  rm -rf "$home" "$src"
}

t_no_variant
finish_tests
```

- [ ] **Step 2: 运行 update 测试，确认因脚本不存在而 FAIL**

Run: `bash tests/test_update.sh`
Expected: FAIL —— `bash` 报 `update.sh: No such file or directory`，`$?` 非 3，断言失败计数 > 0。

- [ ] **Step 3: 创建 update.sh 骨架（共享函数 + 无变体报错）**

Create `update.sh`：

```bash
#!/usr/bin/env bash
# update.sh — 把 Trae 全局技能目录里本工程装入的 skills 精确镜像到 upstream 最新状态。
# 精确镜像:覆盖同名内容 + 删除上游已移除的孤儿 skill(仅限 manifest 记录范围)。
# 自包含:不 source 外部文件(需兼容 curl|bash)。兼容 bash 3.2。
#
# 注意:变体目录名一律用八进制字节转义构造(\056=".", \137="_"),
# 规避部分环境对连续词元 dot-underscore-agent / dot-trae 的改写。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"
# manifest 文件名:记录本工程装入的 skill 名单。
MANIFEST=".superpowers-manifest"

# variant_roots: 逐行输出四个受支持的 Trae 变体根目录名。
variant_roots() {
  printf '%s\n' "$(printf '\056\137agent-cn')"
  printf '%s\n' "$(printf '\056\137agent')"
  printf '%s\n' "$(printf '\056trae-cn')"
  printf '%s\n' "$(printf '\056trae')"
}

# detect_skill_dirs: 探测已安装变体的 skills 目录(去重真实路径)。同 install.sh。
detect_skill_dirs() {
  local seen="" root c real
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    c="$HOME/$root/skills"
    if [ -d "$c" ] || [ -d "$HOME/$root" ]; then
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
  done <<EOF
$(variant_roots)
EOF
}

# resolve_src: 返回上游 skills 源目录(内含各 skill 子目录)。
# 测试可用 SUPERPOWERS_SKILLS_SRC 注入本地源以离线运行;否则 clone upstream 到临时目录。
resolve_src() {
  if [ -n "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    printf '%s\n' "$SUPERPOWERS_SKILLS_SRC/skills"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/superpowers.XXXXXX")" || return 1
  if ! git clone --depth 1 "$UPSTREAM_URL" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi
  printf '%s\n' "$tmp/skills"
}

main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected.\n' >&2
    return 3
  fi
  printf 'Detected target skill dirs:\n%s\n' "$dirs"
  return 0
}

main "$@"
```

- [ ] **Step 4: 运行 update 测试，确认全绿**

Run: `bash tests/test_update.sh`
Expected: `PASS: 无变体时退出码为 3`，末尾 `--- 1 passed, 0 failed ---`，退出码 0。

- [ ] **Step 5: Commit**

```bash
git add update.sh tests/test_update.sh
git commit -m "feat: add update.sh skeleton with variant detection"
```

---

## Task 4: update.sh 基本更新 —— 覆盖并新增 skill（先写测试）

**Files:**
- Modify: `tests/test_update.sh`
- Modify: `update.sh`

- [ ] **Step 1: 在 test_update.sh 中新增"基本更新"用例并注册**

在 [tests/test_update.sh](../../../tests/test_update.sh) 的 `t_no_variant` 函数之后新增：

```bash
# 用例2: 旧装 A,B → 新源 A,B,C。全部就位,manifest 含三者。
t_basic_update() {
  local home; home="$(make_temp_home)"
  # 预置:变体已装 A,B 且 manifest 记录二者
  mkdir -p "$home/$V_AGENT_CN/skills/skill-a"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-b"
  printf 'skill-a\nskill-b\n' > "$home/$V_AGENT_CN/skills/$MANIFEST"
  # 新上游源含 A,B,C
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a skill-b skill-c
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "基本更新退出码为 0"
  assert_dir_exists "$home/$V_AGENT_CN/skills/skill-a" "更新后 skill-a 存在"
  assert_dir_exists "$home/$V_AGENT_CN/skills/skill-b" "更新后 skill-b 存在"
  assert_dir_exists "$home/$V_AGENT_CN/skills/skill-c" "新增 skill-c 存在"
  assert_file_contains "$home/$V_AGENT_CN/skills/$MANIFEST" "skill-c" "manifest 含新增 skill-c"
  rm -rf "$home" "$src"
}
```

并在文件末尾 `finish_tests` 之前，把 `t_no_variant` 一行改为两行：

```bash
t_no_variant
t_basic_update
finish_tests
```

- [ ] **Step 2: 运行 update 测试，确认新用例 FAIL**

Run: `bash tests/test_update.sh`
Expected: `t_basic_update` 相关断言 FAIL（skill-c 不存在、manifest 未更新），failed 计数 > 0。

- [ ] **Step 3: 在 update.sh 中新增 mirror_skills 与 write_manifest，并在 main 里对每个变体调用**

在 [update.sh](../../../update.sh) 的 `resolve_src` 函数之后新增两个函数：

```bash
# mirror_skills: 对新源里每个 skill 做逐 skill 清替(先删后拷),实现目录级镜像。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
mirror_skills() {
  local src="$1" dst="$2" entry name
  mkdir -p "$dst"
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    rm -rf "$dst/$name"
    cp -R "$src/$name" "$dst/$name"
  done
}

# write_manifest: 把源目录下所有 skill 名逐行写入目标 manifest(覆盖)。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
write_manifest() {
  local src="$1" dst="$2" entry name
  : > "$dst/$MANIFEST"
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    printf '%s\n' "$name" >> "$dst/$MANIFEST"
  done
}
```

- [ ] **Step 4: 扩充 main：获取源并对每个变体镜像 + 写 manifest**

把 [update.sh](../../../update.sh) 的 `main` 函数整体替换为：

```bash
main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected.\n' >&2
    return 3
  fi
  printf 'Detected target skill dirs:\n%s\n' "$dirs"

  local src
  if ! src="$(resolve_src)"; then
    printf 'Error: failed to obtain superpowers skills source.\n' >&2
    return 4
  fi
  if [ ! -d "$src" ]; then
    printf 'Error: skills source not found: %s\n' "$src" >&2
    [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ] && rm -rf "$(dirname "$src")"
    return 4
  fi

  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf 'Updating skills in: %s\n' "$d"
    mirror_skills "$src" "$d"
    write_manifest "$src" "$d"
  done <<EOF
$dirs
EOF

  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    rm -rf "$(dirname "$src")"
  fi

  printf 'Done. Skills updated to latest upstream.\n'
  return 0
}
```

- [ ] **Step 5: 运行 update 测试，确认全绿**

Run: `bash tests/test_update.sh`
Expected: 全部 `PASS`，末尾 `--- N passed, 0 failed ---`，退出码 0。

- [ ] **Step 6: Commit**

```bash
git add update.sh tests/test_update.sh
git commit -m "feat: mirror upstream skills and rewrite manifest on update"
```

---

## Task 5: update.sh 删除孤儿 skill（先写测试）

**Files:**
- Modify: `tests/test_update.sh`
- Modify: `update.sh`

- [ ] **Step 1: 在 test_update.sh 中新增"删孤儿"与"不误伤用户 skill"两个用例并注册**

在 [tests/test_update.sh](../../../tests/test_update.sh) 的 `t_basic_update` 之后新增：

```bash
# 用例3: 旧 manifest 有 A,B → 新源只有 A。B 是孤儿应删,A 保留,manifest 只剩 A。
t_remove_orphan() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-a"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-b"
  printf 'skill-a\nskill-b\n' > "$home/$V_AGENT_CN/skills/$MANIFEST"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "删孤儿退出码为 0"
  assert_dir_exists "$home/$V_AGENT_CN/skills/skill-a" "保留仍在上游的 skill-a"
  assert_dir_absent "$home/$V_AGENT_CN/skills/skill-b" "删除上游已移除的孤儿 skill-b"
  assert_file_absent "$home/$V_AGENT_CN/skills/skill-b/SKILL.md" "孤儿 skill-b 内容一并清除"
  rm -rf "$home" "$src"
}

# 用例4: 用户自有 skill(未记入 manifest)不得被删。
t_keep_user_skill() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-a"
  mkdir -p "$home/$V_AGENT_CN/skills/my-own"     # 用户自有,未入 manifest
  printf 'skill-a\n' > "$home/$V_AGENT_CN/skills/$MANIFEST"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "保留用户 skill 场景退出码为 0"
  assert_dir_exists "$home/$V_AGENT_CN/skills/my-own" "用户自有 skill 保留"
  assert_dir_exists "$home/$V_AGENT_CN/skills/skill-a" "upstream skill-a 保留"
  rm -rf "$home" "$src"
}
```

并把末尾注册段改为：

```bash
t_no_variant
t_basic_update
t_remove_orphan
t_keep_user_skill
finish_tests
```

- [ ] **Step 2: 运行 update 测试，确认孤儿用例 FAIL**

Run: `bash tests/test_update.sh`
Expected: `t_remove_orphan` 的 `skill-b` 断言 FAIL（skill-b 仍在），failed 计数 > 0；`t_keep_user_skill` 应已 PASS（当前实现不删任何东西）。

- [ ] **Step 3: 在 update.sh 中新增 remove_orphans 函数**

在 [update.sh](../../../update.sh) 的 `write_manifest` 函数之后新增：

```bash
# remove_orphans: 删除孤儿 skill —— 旧 manifest 记录过、但新源已不再提供的 skill。
# 严格限定 manifest 范围,绝不触碰未记录的用户自有 skill。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
remove_orphans() {
  local src="$1" dst="$2" name
  [ -f "$dst/$MANIFEST" ] || return 0     # 无旧 manifest → 无孤儿可删(降级)
  while IFS= read -r name; do
    [ -n "$name" ] || continue            # 跳过空行
    if [ ! -d "$src/$name" ]; then        # 旧记录的 skill 已不在新源 → 孤儿
      printf 'Removing orphan skill: %s\n' "$dst/$name"
      rm -rf "$dst/$name"
    fi
  done < "$dst/$MANIFEST"
}
```

- [ ] **Step 4: 在 main 的变体循环里，先删孤儿再镜像**

把 [update.sh](../../../update.sh) `main` 里的变体循环体改为（在 `mirror_skills` 之前调用 `remove_orphans`）：

```bash
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf 'Updating skills in: %s\n' "$d"
    remove_orphans "$src" "$d"
    mirror_skills "$src" "$d"
    write_manifest "$src" "$d"
  done <<EOF
$dirs
EOF
```

- [ ] **Step 5: 运行 update 测试，确认全绿**

Run: `bash tests/test_update.sh`
Expected: 全部 `PASS`，末尾 `--- N passed, 0 failed ---`，退出码 0。

- [ ] **Step 6: Commit**

```bash
git add update.sh tests/test_update.sh
git commit -m "feat: remove orphan skills within manifest scope on update"
```

---

## Task 6: update.sh 处理 skill 内文件镜像与 manifest 缺失降级（先写测试）

**Files:**
- Modify: `tests/test_update.sh`
- Modify: `update.sh`（预计无需改动，验证已满足）

- [ ] **Step 1: 在 test_update.sh 中新增"skill 内文件镜像"与"manifest 缺失降级"两个用例并注册**

在 [tests/test_update.sh](../../../tests/test_update.sh) 的 `t_keep_user_skill` 之后新增：

```bash
# 用例5: skill 内被上游删的文件应消失,新文件应出现(逐 skill 清替=目录级镜像)。
t_intra_skill_mirror() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-a"
  printf 'old\n' > "$home/$V_AGENT_CN/skills/skill-a/old.md"   # 上游将删除此文件
  printf 'skill-a\n' > "$home/$V_AGENT_CN/skills/$MANIFEST"
  # 新源的 skill-a 只有 SKILL.md 与 new.md,没有 old.md
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  printf 'new\n' > "$src/skills/skill-a/new.md"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "skill 内镜像退出码为 0"
  assert_file_absent "$home/$V_AGENT_CN/skills/skill-a/old.md" "上游已删文件 old.md 消失"
  assert_file_exists "$home/$V_AGENT_CN/skills/skill-a/new.md" "上游新增文件 new.md 存在"
  rm -rf "$home" "$src"
}

# 用例6: 无 manifest(老用户首次 update)→ 不删任何东西,全量镜像并补写 manifest。
t_missing_manifest_degrade() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-a"
  mkdir -p "$home/$V_AGENT_CN/skills/my-own"     # 无 manifest,用户 skill 不应被删
  # 故意不创建 manifest 文件
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a skill-c
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "manifest 缺失降级退出码为 0"
  assert_dir_exists "$home/$V_AGENT_CN/skills/my-own" "无 manifest 时用户 skill 保留"
  assert_dir_exists "$home/$V_AGENT_CN/skills/skill-c" "无 manifest 时仍写入新 skill"
  assert_file_exists "$home/$V_AGENT_CN/skills/$MANIFEST" "无 manifest 时补写 manifest"
  assert_file_contains "$home/$V_AGENT_CN/skills/$MANIFEST" "skill-a" "补写的 manifest 含 skill-a"
  rm -rf "$home" "$src"
}
```

并把末尾注册段改为：

```bash
t_no_variant
t_basic_update
t_remove_orphan
t_keep_user_skill
t_intra_skill_mirror
t_missing_manifest_degrade
finish_tests
```

- [ ] **Step 2: 运行 update 测试，确认两个新用例结果**

Run: `bash tests/test_update.sh`
Expected: 两个新用例应**直接 PASS**（`mirror_skills` 的先删后拷已实现 skill 内镜像；`remove_orphans` 在无 manifest 时 `return 0` 已实现降级）。若全绿，本任务无需改 update.sh，跳到 Step 4。

- [ ] **Step 3: （仅当 Step 2 有 FAIL 时）修正 update.sh**

若 `t_intra_skill_mirror` FAIL：检查 `mirror_skills` 是否确实先 `rm -rf "$dst/$name"` 再 `cp -R`。
若 `t_missing_manifest_degrade` FAIL：检查 `remove_orphans` 首行 `[ -f "$dst/$MANIFEST" ] || return 0` 是否存在。
修正后重跑 `bash tests/test_update.sh` 直到全绿。

- [ ] **Step 4: Commit**

```bash
git add tests/test_update.sh
git commit -m "test: cover intra-skill mirroring and manifest-missing degrade"
```

---

## Task 7: uninstall.sh 优先按 manifest 删除，缺失时回退（先写测试）

**Files:**
- Modify: `tests/test_uninstall.sh`
- Modify: `uninstall.sh`

- [ ] **Step 1: 在 test_uninstall.sh 中新增"按 manifest 卸载"用例并注册**

在 [tests/test_uninstall.sh](../../../tests/test_uninstall.sh) 的 `t_uninstall_cn` 之后新增。注意新用例故意**不注入 SUPERPOWERS_SKILLS_SRC**，以验证 manifest 存在时无需上游源即可卸载：

```bash
MANIFEST=".superpowers-manifest"

# 用例2: manifest 存在时,按 manifest 逐名删除,无需上游源;manifest 本身也被删,用户 skill 保留。
t_uninstall_by_manifest() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-a"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-b"
  mkdir -p "$home/$V_AGENT_CN/skills/my-own"      # 用户自有,不在 manifest
  printf 'skill-a\nskill-b\n' > "$home/$V_AGENT_CN/skills/$MANIFEST"
  # 不设置 SUPERPOWERS_SKILLS_SRC:验证 manifest 路径离线可用
  HOME="$home" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "按 manifest 卸载退出码为 0"
  assert_dir_absent "$home/$V_AGENT_CN/skills/skill-a" "manifest 记录的 skill-a 被删"
  assert_dir_absent "$home/$V_AGENT_CN/skills/skill-b" "manifest 记录的 skill-b 被删"
  assert_dir_exists "$home/$V_AGENT_CN/skills/my-own" "用户自有 skill 保留"
  assert_file_absent "$home/$V_AGENT_CN/skills/$MANIFEST" "manifest 文件被删除"
  rm -rf "$home"
}
```

并把末尾注册段改为：

```bash
t_uninstall_cn
t_uninstall_by_manifest
finish_tests
```

- [ ] **Step 2: 运行 uninstall 测试，确认新用例 FAIL**

Run: `bash tests/test_uninstall.sh`
Expected: `t_uninstall_by_manifest` FAIL —— 当前 uninstall.sh 无 SUPERPOWERS_SKILLS_SRC 会尝试 git clone（离线环境失败）而报错退出，且 manifest 未被删。failed 计数 > 0。

- [ ] **Step 3: 在 uninstall.sh 中新增 MANIFEST 常量与 remove_by_manifest 函数**

在 [uninstall.sh](../../../uninstall.sh) 的 `UPSTREAM_URL=...`（第 9 行）之后新增：

```bash
# manifest 文件名:本工程装入 skill 的清单;优先据此精确卸载。
MANIFEST=".superpowers-manifest"
```

在 `resolve_src` 函数（第 43-55 行）之后新增：

```bash
# remove_by_manifest: 按目标目录内 manifest 逐名删除本工程装入的 skill,并删 manifest。
# 参数: $1=目标 skills 目录。返回 0 表示已按 manifest 处理;返回 1 表示无 manifest(交由回退)。
remove_by_manifest() {
  local dst="$1" name
  [ -f "$dst/$MANIFEST" ] || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -d "$dst/$name" ]; then
      printf 'Removing: %s\n' "$dst/$name"
      rm -rf "$dst/$name"
    fi
  done < "$dst/$MANIFEST"
  rm -f "$dst/$MANIFEST"
  return 0
}
```

- [ ] **Step 4: 重构 uninstall.sh 的 main —— manifest 优先，缺失才回退到上游清单**

把 [uninstall.sh](../../../uninstall.sh) 的 `main` 函数整体替换为：

```bash
main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected.\n' >&2
    return 3
  fi

  # 第一遍:凡有 manifest 的目标目录,直接按 manifest 卸载(离线可用)。
  # 收集仍需回退处理(无 manifest)的目标目录到 fallback_dirs。
  local d fallback_dirs=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || continue
    if remove_by_manifest "$d"; then
      : # 已按 manifest 处理
    else
      fallback_dirs="$fallback_dirs
$d"
    fi
  done <<EOF
$dirs
EOF

  # 若所有目标都已按 manifest 处理完,无需获取上游清单。
  if [ -z "$(printf '%s' "$fallback_dirs" | tr -d '[:space:]')" ]; then
    printf 'Done. Note: remove the Superpowers User Rules manually in Trae settings.\n'
    return 0
  fi

  # 第二遍(回退):无 manifest 的目标,沿用"按上游清单反推删除"。
  local src
  if ! src="$(resolve_src)"; then
    printf 'Error: failed to obtain superpowers skills list.\n' >&2
    return 4
  fi
  if [ ! -d "$src" ]; then
    printf 'Error: skills source not found: %s\n' "$src" >&2
    [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ] && rm -rf "$(dirname "$src")"
    return 4
  fi

  local entry name
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || continue
    for entry in "$src"/*/; do
      [ -d "$entry" ] || continue
      name="$(basename "$entry")"
      if [ -d "$d/$name" ]; then
        printf 'Removing: %s\n' "$d/$name"
        rm -rf "$d/$name"
      fi
    done
  done <<EOF
$fallback_dirs
EOF

  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    rm -rf "$(dirname "$src")"
  fi

  printf 'Done. Note: remove the Superpowers User Rules manually in Trae settings.\n'
  return 0
}
```

- [ ] **Step 5: 运行 uninstall 测试，确认全绿（含向后兼容的旧用例）**

Run: `bash tests/test_uninstall.sh`
Expected: `t_uninstall_cn`（回退路径，有注入源）与 `t_uninstall_by_manifest`（manifest 路径，无源）均 PASS，末尾 `--- N passed, 0 failed ---`。

- [ ] **Step 6: Commit**

```bash
git add uninstall.sh tests/test_uninstall.sh
git commit -m "feat: prefer manifest for uninstall, fall back to upstream list"
```

---

## Task 8: 注册 test_update.sh 到 run_all.sh 并全量回归

**Files:**
- Modify: `tests/run_all.sh`

- [ ] **Step 1: 把 test_update.sh 加入 run_all.sh 的循环**

把 [tests/run_all.sh](../../../tests/run_all.sh) 第 6 行的 `for` 循环改为包含 update 测试：

```bash
for t in "$HERE"/test_install.sh "$HERE"/test_update.sh "$HERE"/test_uninstall.sh; do
```

- [ ] **Step 2: 运行全部测试，确认整体全绿**

Run: `bash tests/run_all.sh`
Expected: 依次打印 `=== Running test_install.sh ===`、`=== Running test_update.sh ===`、`=== Running test_uninstall.sh ===`，每个末尾 `--- N passed, 0 failed ---`，整体退出码 0。

- [ ] **Step 3: Commit**

```bash
git add tests/run_all.sh
git commit -m "test: register test_update.sh in run_all"
```

---

## Task 9: 文档 —— README 双语新增 Update 章节与 manifest 说明

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`

- [ ] **Step 1: 在 README.md 的 Uninstall 章节之前插入 Update 章节**

在 [README.md](../../../README.md) 的 `## Uninstall`（第 71 行）之前插入：

```markdown
## Update

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/trae-superpowers/main/update.sh | bash
```

This re-syncs the installed skills to the latest upstream state (an exact
mirror): it updates changed content and removes skills that upstream has
deleted. It never touches skills you installed yourself — only skills this
project recorded in its manifest are affected.

```

- [ ] **Step 2: 在 README.md 的 "How it works" 补充 manifest 说明**

在 [README.md](../../../README.md) 的 `## How it works` 列表（第 82-85 行）中，`- **User Rules** ...` 那条之后新增一条：

```markdown
- **Manifest** — a `.superpowers-manifest` file in each skills directory records
  which skills this project installed, so update and uninstall can target them
  precisely without touching your own skills. Do not edit it by hand.
```

- [ ] **Step 3: 更新 README.md 的 Uninstall 说明为 manifest 优先**

把 [README.md](../../../README.md) Uninstall 章节的说明段（第 76-78 行）替换为：

```markdown
This removes only the skills provided by upstream Superpowers; your own skills
are left untouched. When a manifest is present it uninstalls precisely from that
list (no network needed); otherwise it falls back to the upstream skill list.
Remove the User Rules manually in Trae Settings.
```

- [ ] **Step 4: 在 README.zh-CN.md 对应位置做等价中文改动**

打开 [README.zh-CN.md](../../../README.zh-CN.md)，在其"卸载"章节之前插入等价的"更新"章节：

```markdown
## 更新

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/trae-superpowers/main/update.sh | bash
```

把已安装的 skills 精确镜像到上游最新状态:更新变动内容,并移除上游已删除的
skill。绝不触碰你自己安装的 skill —— 只有本工程 manifest 记录过的 skill 才会
被同步。

```

在"工作原理"列表中新增一条：

```markdown
- **Manifest** —— 每个 skills 目录下的 `.superpowers-manifest` 文件记录本工程
  装入了哪些 skill,使更新与卸载能精确定位它们,不影响你自己的 skill。请勿手动编辑。
```

并把"卸载"章节说明更新为：manifest 存在时按清单精确卸载(无需联网),否则回退到上游清单。

- [ ] **Step 5: 校验两份 README 结构一致**

Run: `grep -n '^## ' README.md; echo '---'; grep -n '^## ' README.zh-CN.md`
Expected: 两份文件的二级标题顺序一一对应（英文与中文标题数量、顺序一致，均新增了 Update/更新 章节）。

- [ ] **Step 6: Commit**

```bash
git add README.md README.zh-CN.md
git commit -m "docs: document update command and manifest mechanism"
```

---

## Task 10: 文档 —— 更新 CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

> 注:`CLAUDE.md` 当前为未跟踪文件。本任务将其纳入版本管理并补充 update 相关说明。

- [ ] **Step 1: 在 CLAUDE.md 常用命令区补 update 测试命令**

在 [CLAUDE.md](../../../CLAUDE.md) 的"单独运行某个测试"代码块中，`bash tests/test_uninstall.sh` 之后新增一行：

```bash
bash tests/test_update.sh
```

- [ ] **Step 2: 在 CLAUDE.md 架构与关键文件区补 update.sh 与 manifest 说明**

在 [CLAUDE.md](../../../CLAUDE.md) 的 `[uninstall.sh]` 条目之后新增：

```markdown
- [update.sh](./update.sh):用相同探测逻辑找到目标目录,读旧 manifest 计算孤儿
  (OLD∩¬NEW)并删除,再对上游全部 skill 逐 skill 清替(先删后拷)实现目录级镜像,
  最后覆盖写 manifest。核心函数 `mirror_skills` / `remove_orphans` / `write_manifest`。
```

并在"关键约定与约束"区新增一条：

```markdown
- **manifest 追踪**:每个 skills 目录根下 `.superpowers-manifest`(纯文本,每行一个
  skill 名)记录本工程装入的 skill。install/update 写入,uninstall 优先据此删除;
  孤儿删除严格限定 manifest 范围,不触碰用户自有 skill。
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add update.sh and manifest notes to CLAUDE.md"
```

---

## Task 11: 最终全量回归与手动冒烟

**Files:** 无（仅验证）

- [ ] **Step 1: 全量测试回归**

Run: `bash tests/run_all.sh`
Expected: 三个测试文件全部 `--- N passed, 0 failed ---`，整体退出码 0。

- [ ] **Step 2: 语法检查所有脚本**

Run: `for f in install.sh update.sh uninstall.sh; do bash -n "$f" && echo "OK: $f"; done`
Expected: `OK: install.sh`、`OK: update.sh`、`OK: uninstall.sh` 三行，无语法错误。

- [ ] **Step 3: 端到端手动冒烟（install → update → uninstall，全离线注入源）**

Run（一条命令，用假源与临时 HOME 走完三脚本）:

```bash
SMOKE="$(mktemp -d)"; SRC="$(mktemp -d)"; \
mkdir -p "$SMOKE/$(printf '\056\137agent-cn')"; \
mkdir -p "$SRC/skills/alpha" "$SRC/skills/beta"; \
printf '# alpha\n' > "$SRC/skills/alpha/SKILL.md"; \
printf '# beta\n' > "$SRC/skills/beta/SKILL.md"; \
HOME="$SMOKE" SUPERPOWERS_SKILLS_SRC="$SRC" bash install.sh; \
echo '--- manifest after install ---'; cat "$SMOKE/$(printf '\056\137agent-cn')/skills/.superpowers-manifest"; \
rm -rf "$SRC/skills/beta"; mkdir -p "$SRC/skills/gamma"; printf '# gamma\n' > "$SRC/skills/gamma/SKILL.md"; \
HOME="$SMOKE" SUPERPOWERS_SKILLS_SRC="$SRC" bash update.sh; \
echo '--- skills after update ---'; ls "$SMOKE/$(printf '\056\137agent-cn')/skills"; \
HOME="$SMOKE" bash uninstall.sh; \
echo '--- skills after uninstall ---'; ls "$SMOKE/$(printf '\056\137agent-cn')/skills"; \
rm -rf "$SMOKE" "$SRC"
```

Expected:
- install 后 manifest 含 `alpha`、`beta`。
- update 后 skills 目录含 `alpha`、`gamma`（`beta` 作为孤儿被删）。
- uninstall 后 skills 目录为空（`alpha`、`gamma` 均被删，manifest 也被删）。

- [ ] **Step 4: 若冒烟发现问题，回到对应 Task 修正；否则完成**

无 commit（纯验证任务）。若前述步骤全部符合预期，则本计划实现完成。

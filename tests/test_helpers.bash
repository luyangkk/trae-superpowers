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

# make_fake_agents_superpowers: 在隔离 HOME 的 .agents/skills 下构造 Superpowers skills。
# 仅传 HOME 时创建四个核心 skill;额外参数存在时只创建参数指定的 skill,用于残缺安装测试。
make_fake_agents_superpowers() {
  local home="$1"; shift
  if [ "$#" -eq 0 ]; then
    set -- using-superpowers brainstorming test-driven-development systematic-debugging
  fi
  make_fake_src "$home/.agents" "$@"
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
# 用 grep -qxF:-x 整行匹配、-F 视参数为字面量(避免 ** 等被当正则解析报错)。
assert_file_contains() {
  if [ -f "$1" ] && grep -qxF "$2" "$1"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$3"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (file %s missing line: %s)\n' "$3" "$1" "$2"
  fi
}

# assert_file_absent_line: 断言文件不含某整行(或文件不存在)。参数: $1=路径 $2=不期望整行 $3=用例描述
assert_file_absent_line() {
  if [ ! -f "$1" ] || ! grep -qxF "$2" "$1"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf 'PASS: %s\n' "$3"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL: %s (file %s unexpectedly contains line: %s)\n' "$3" "$1" "$2"
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

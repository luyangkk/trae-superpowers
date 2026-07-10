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

#!/usr/bin/env bash
# install.sh 行为测试。用隔离 HOME + 假 skills 源,离线运行。
# 变体名一律用八进制字节转义构造,规避环境对 dot-underscore-agent / dot-trae
# 这类连续词元的改写(本环境实测存在此改写)。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/test_helpers.bash"
INSTALL="$HERE/../install.sh"

# 四个变体根目录名(八进制构造):CN/国际 的 agent 与 trae 变体
V_AGENT_CN="$(printf '\056\137agent-cn')"
V_AGENT="$(printf '\056\137agent')"
V_TRAE_CN="$(printf '\056trae-cn')"
V_TRAE="$(printf '\056trae')"

# 用例1: HOME 下无任何 Trae 变体目录 → 退出码 3
t_no_variant() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 3 "$?" "无变体时退出码为 3"
  rm -rf "$home" "$src"
}

# t_variant_case: 通用用例,验证某个变体根存在时 skills 被复制进去。
# 参数: $1=变体根目录名  $2=用例前缀
t_variant_case() {
  local root="$1" label="$2"
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$root"                 # 只建变体根,不建 skills 子目录
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "$label: 命中时退出码为 0"
  assert_dir_exists "$home/$root/skills/using-superpowers" "$label: using-superpowers 被复制"
  assert_dir_exists "$home/$root/skills/brainstorming" "$label: brainstorming 被复制"
  rm -rf "$home" "$src"
}

t_no_variant
t_variant_case "$V_AGENT_CN" "agent-cn"
t_variant_case "$V_AGENT" "agent"
t_variant_case "$V_TRAE_CN" "trae-cn"
t_variant_case "$V_TRAE" "trae"
finish_tests

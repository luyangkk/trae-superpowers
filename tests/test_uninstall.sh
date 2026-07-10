#!/usr/bin/env bash
# uninstall.sh 行为测试。变体名用八进制字节转义构造,规避环境词元改写。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/test_helpers.bash"
UNINSTALL="$HERE/../uninstall.sh"

V_AGENT_CN="$(printf '\056\137agent-cn')"

# 用例1: 已装入的 upstream skills 应被移除,用户自有 skill 保留,退出码 0
t_uninstall_cn() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/using-superpowers"
  mkdir -p "$home/$V_AGENT_CN/skills/brainstorming"
  mkdir -p "$home/$V_AGENT_CN/skills/my-own-skill"   # 用户自有,不应被删
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "卸载退出码为 0"
  assert_dir_absent "$home/$V_AGENT_CN/skills/using-superpowers" "upstream skill 被移除"
  assert_dir_absent "$home/$V_AGENT_CN/skills/brainstorming" "upstream skill 被移除(2)"
  assert_dir_exists "$home/$V_AGENT_CN/skills/my-own-skill" "用户自有 skill 保留"
  rm -rf "$home" "$src"
}

t_uninstall_cn
finish_tests

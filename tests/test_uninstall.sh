#!/usr/bin/env bash
# uninstall.sh 行为测试。变体名用八进制字节转义构造,规避环境词元改写。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/test_helpers.bash
source "$HERE/test_helpers.bash"
UNINSTALL="$HERE/../uninstall.sh"

V_AGENT_CN="$(printf '\056\137agent-cn')"
MANIFEST=".superpowers-manifest"

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

# 用例2: manifest 存在时,按 manifest 逐名删除,无需上游源;manifest 本身也被删,用户 skill 保留。
# 同时覆盖 manifest 早退成功路径:该路径调用 remove_all_managed_rules,带标记规则应被删除。
t_uninstall_by_manifest() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-a"
  mkdir -p "$home/$V_AGENT_CN/skills/skill-b"
  mkdir -p "$home/$V_AGENT_CN/skills/my-own"      # 用户自有,不在 manifest
  printf 'skill-a\nskill-b\n' > "$home/$V_AGENT_CN/skills/$MANIFEST"
  # 预置带标记规则文件:断言 manifest 早退路径也会删规则
  mkdir -p "$home/$V_AGENT_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nbody\n' > "$home/$V_AGENT_CN/user_rules/rule-managed.md"
  # 不设置 SUPERPOWERS_SKILLS_SRC:验证 manifest 路径离线可用
  HOME="$home" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "按 manifest 卸载退出码为 0"
  assert_dir_absent "$home/$V_AGENT_CN/skills/skill-a" "manifest 记录的 skill-a 被删"
  assert_dir_absent "$home/$V_AGENT_CN/skills/skill-b" "manifest 记录的 skill-b 被删"
  assert_dir_exists "$home/$V_AGENT_CN/skills/my-own" "用户自有 skill 保留"
  assert_file_absent "$home/$V_AGENT_CN/skills/$MANIFEST" "manifest 文件被删除"
  assert_file_absent "$home/$V_AGENT_CN/user_rules/rule-managed.md" "manifest 早退路径也删除带标记规则"
  rm -rf "$home"
}

# 用例3: 卸载删除带标记的规则文件,但保留用户自有规则。
t_uninstall_removes_managed_rule() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills" "$home/$V_AGENT_CN/user_rules"
  # 本工程写入的带标记规则
  printf '<!-- trae-superpowers-managed-rule -->\nbody\n' > "$home/$V_AGENT_CN/user_rules/rule-managed.md"
  # 用户自有规则(无标记)
  printf 'my own rule\n' > "$home/$V_AGENT_CN/user_rules/rule-mine.md"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "卸载退出码为 0"
  assert_file_absent "$home/$V_AGENT_CN/user_rules/rule-managed.md" "带标记规则被删除"
  assert_file_contains "$home/$V_AGENT_CN/user_rules/rule-mine.md" "my own rule" "用户自有规则保留"
  rm -rf "$home" "$src"
}

t_uninstall_cn
t_uninstall_by_manifest
t_uninstall_removes_managed_rule
finish_tests

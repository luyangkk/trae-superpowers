#!/usr/bin/env bash
# uninstall.sh 行为测试。使用隔离 HOME,避免触碰真实安装。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/test_helpers.bash
source "$HERE/test_helpers.bash"
UNINSTALL="$HERE/../uninstall.sh"

V_TRAE_CN="$(printf '\056trae-cn')"
V_TRAE="$(printf '\056trae')"
MANIFEST=".superpowers-manifest"

# t_uninstall_fallback: 无 manifest 时按显式目标和上游清单删除,保留用户 Skill。
t_uninstall_fallback() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/using-superpowers"
  mkdir -p "$home/$V_TRAE_CN/skills/brainstorming"
  mkdir -p "$home/$V_TRAE_CN/skills/my-own-skill"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "无 manifest 回退卸载退出码为 0"
  assert_dir_absent "$home/$V_TRAE_CN/skills/using-superpowers" "上游 skill 被移除"
  assert_dir_absent "$home/$V_TRAE_CN/skills/brainstorming" "第二个上游 skill 被移除"
  assert_dir_exists "$home/$V_TRAE_CN/skills/my-own-skill" "用户自有 skill 保留"
  rm -rf "$home" "$src"
}

# t_no_manifest_without_target: 无 manifest、无 TTY 且未指定目标时必须失败。
t_no_manifest_without_target() {
  local home; home="$(make_temp_home)"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$home/missing" \
    bash "$UNINSTALL" </dev/null >/dev/null 2>&1
  assert_exit_code 2 "$?" "无 manifest 且无目标时退出码为 2"
  rm -rf "$home"
}

# t_uninstall_by_manifest: manifest 存在时可离线精确卸载。
t_uninstall_by_manifest() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-b"
  mkdir -p "$home/$V_TRAE_CN/skills/my-own"
  printf 'skill-a\nskill-b\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  mkdir -p "$home/$V_TRAE_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nbody\n' > "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  HOME="$home" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "按 manifest 卸载退出码为 0"
  assert_dir_absent "$home/$V_TRAE_CN/skills/skill-a" "manifest 中 skill-a 被删除"
  assert_dir_absent "$home/$V_TRAE_CN/skills/skill-b" "manifest 中 skill-b 被删除"
  assert_dir_exists "$home/$V_TRAE_CN/skills/my-own" "用户自有 skill 保留"
  assert_file_absent "$home/$V_TRAE_CN/skills/$MANIFEST" "manifest 被删除"
  assert_file_absent "$home/$V_TRAE_CN/user_rules/rule-managed.md" "托管规则被删除"
  rm -rf "$home"
}

# t_two_manifests_uninstalls_selected: 两处都有 manifest 时只卸载显式选择的目标。
t_two_manifests_uninstalls_selected() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a" "$home/$V_TRAE/skills/skill-a"
  printf 'skill-a\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  printf 'skill-a\n' > "$home/$V_TRAE/skills/$MANIFEST"
  HOME="$home" SUPERPOWERS_TARGET=trae bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "双 manifest 显式选择卸载成功"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-a" "未选目标保持不变"
  assert_dir_absent "$home/$V_TRAE/skills/skill-a" "所选目标已卸载"
  assert_file_exists "$home/$V_TRAE_CN/skills/$MANIFEST" "未选目标 manifest 保留"
  assert_file_absent "$home/$V_TRAE/skills/$MANIFEST" "所选目标 manifest 删除"
  rm -rf "$home"
}

# t_reused_agents_uninstall: 复用 .agents 时清理两处 manifest 与所有托管 Rule,无需选择。
t_reused_agents_uninstall() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a"
  mkdir -p "$home/$V_TRAE_CN/skills/my-own"
  printf 'skill-a\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  mkdir -p "$home/$V_TRAE/skills/using-superpowers" "$home/$V_TRAE/user_rules"
  printf 'using-superpowers\n' > "$home/$V_TRAE/skills/$MANIFEST"
  mkdir -p "$home/$V_TRAE_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nbody\n' > "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  printf '<!-- trae-superpowers-managed-rule -->\nbody\n' > "$home/$V_TRAE/user_rules/rule-managed.md"
  make_fake_agents_superpowers "$home"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$home/missing" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "复用 .agents 卸载退出码为 0"
  assert_dir_absent "$home/$V_TRAE_CN/skills/skill-a" "Trae manifest 管理的 skill 被删除"
  assert_dir_exists "$home/$V_TRAE_CN/skills/my-own" "Trae 用户 skill 保留"
  assert_dir_absent "$home/$V_TRAE/skills/using-superpowers" "第二处 manifest 管理的 skill 被删除"
  assert_file_exists "$home/.agents/skills/using-superpowers/SKILL.md" ".agents Superpowers 保留"
  assert_file_absent "$home/$V_TRAE_CN/user_rules/rule-managed.md" "国内版托管规则被删除"
  assert_file_absent "$home/$V_TRAE/user_rules/rule-managed.md" "托管规则仍被删除"
  rm -rf "$home"
}

# t_reuse_preserves_agents_alias: Trae skills 指向 .agents 时 uninstall 不得间接删除外部安装。
t_reuse_preserves_agents_alias() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nbody\n' > "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  make_fake_agents_superpowers "$home"
  printf 'using-superpowers\n' > "$home/.agents/skills/$MANIFEST"
  ln -s "$home/.agents/skills" "$home/$V_TRAE_CN/skills"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$home/missing" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "uninstall 复用 .agents 软链接场景退出码为 0"
  assert_file_exists "$home/.agents/skills/using-superpowers/SKILL.md" "uninstall 保留外部 skill"
  assert_file_exists "$home/.agents/skills/$MANIFEST" "uninstall 不删除外部 manifest"
  assert_file_absent "$home/$V_TRAE_CN/user_rules/rule-managed.md" "uninstall 仍删除托管规则"
  rm -rf "$home"
}

# t_uninstall_removes_managed_rule: 所选目标卸载删除托管规则并保留用户规则。
t_uninstall_removes_managed_rule() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills" "$home/$V_TRAE_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nbody\n' > "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  printf 'my own rule\n' > "$home/$V_TRAE_CN/user_rules/rule-mine.md"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "规则卸载场景退出码为 0"
  assert_file_absent "$home/$V_TRAE_CN/user_rules/rule-managed.md" "带标记规则被删除"
  assert_file_contains "$home/$V_TRAE_CN/user_rules/rule-mine.md" "my own rule" "用户自有规则保留"
  rm -rf "$home" "$src"
}

# t_refuses_agents_alias_uninstall: 普通卸载不得经 Trae 软链接删除 .agents 内容。
t_refuses_agents_alias_uninstall() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN" "$home/.agents/skills/skill-a"
  printf 'keep\n' > "$home/.agents/skills/skill-a/state"
  printf 'skill-a\n' > "$home/.agents/skills/$MANIFEST"
  ln -s "$home/.agents/skills" "$home/$V_TRAE_CN/skills"
  HOME="$home" bash "$UNINSTALL" >/dev/null 2>&1
  assert_exit_code 5 "$?" "指向 .agents 的卸载目标被拒绝"
  assert_file_contains "$home/.agents/skills/skill-a/state" "keep" ".agents skill 未被删除"
  assert_file_exists "$home/.agents/skills/$MANIFEST" ".agents manifest 未被删除"
  rm -rf "$home"
}

t_uninstall_fallback
t_no_manifest_without_target
t_uninstall_by_manifest
t_two_manifests_uninstalls_selected
t_reused_agents_uninstall
t_reuse_preserves_agents_alias
t_uninstall_removes_managed_rule
t_refuses_agents_alias_uninstall
finish_tests

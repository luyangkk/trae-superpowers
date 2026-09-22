#!/usr/bin/env bash
# update.sh 行为测试。用隔离 HOME + 假 skills 源,离线运行。
# 目录名用八进制字节转义构造,兼容环境词元处理。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/test_helpers.bash
source "$HERE/test_helpers.bash"
UPDATE="$HERE/../update.sh"

V_TRAE_CN="$(printf '\056trae-cn')"
V_TRAE="$(printf '\056trae')"
MANIFEST=".superpowers-manifest"

# t_no_manifest_without_target: 无 manifest、无 TTY 且未指定目标时必须失败。
t_no_manifest_without_target() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" </dev/null >/dev/null 2>&1
  assert_exit_code 2 "$?" "无 manifest 且无目标时退出码为 2"
  rm -rf "$home" "$src"
}

# t_no_manifest_uses_target: 无 manifest 时显式目标会创建目录并完成更新。
t_no_manifest_uses_target() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "无 manifest 时显式目标更新成功"
  assert_dir_exists "$home/$V_TRAE/skills/using-superpowers" "显式目标目录已创建"
  assert_file_exists "$home/$V_TRAE/skills/$MANIFEST" "显式目标 manifest 已写入"
  rm -rf "$home" "$src"
}

# t_basic_update: 旧装 A、B,新源 A、B、C 时全部就位并刷新 manifest。
t_basic_update() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a" "$home/$V_TRAE_CN/skills/skill-b"
  printf 'skill-a\nskill-b\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a skill-b skill-c
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "基本更新退出码为 0"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-a" "更新后 skill-a 存在"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-b" "更新后 skill-b 存在"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-c" "新增 skill-c 存在"
  assert_file_contains "$home/$V_TRAE_CN/skills/$MANIFEST" "skill-c" "manifest 含新增 skill-c"
  rm -rf "$home" "$src"
}

# t_two_manifests_updates_selected: 两处都有 manifest 时只更新显式选择的目标。
t_two_manifests_updates_selected() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a" "$home/$V_TRAE/skills/skill-a"
  printf 'skill-a\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  printf 'skill-a\n' > "$home/$V_TRAE/skills/$MANIFEST"
  printf 'cn-old\n' > "$home/$V_TRAE_CN/skills/skill-a/state"
  printf 'intl-old\n' > "$home/$V_TRAE/skills/skill-a/state"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  printf 'new\n' > "$src/skills/skill-a/state"
  HOME="$home" SUPERPOWERS_TARGET=trae SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "双 manifest 显式选择更新成功"
  assert_file_contains "$home/$V_TRAE_CN/skills/skill-a/state" "cn-old" "未选目标保持不变"
  assert_file_contains "$home/$V_TRAE/skills/skill-a/state" "new" "所选目标完成更新"
  rm -rf "$home" "$src"
}

# t_remove_orphan: 旧 manifest 中已被上游移除的 Skill 会被删除。
t_remove_orphan() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a" "$home/$V_TRAE_CN/skills/skill-b"
  printf 'skill-a\nskill-b\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "删孤儿退出码为 0"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-a" "保留仍在上游的 skill-a"
  assert_dir_absent "$home/$V_TRAE_CN/skills/skill-b" "删除上游已移除的 skill-b"
  assert_file_absent_line "$home/$V_TRAE_CN/skills/$MANIFEST" "skill-b" "manifest 不再含 skill-b"
  rm -rf "$home" "$src"
}

# t_keep_user_skill: 未写入 manifest 的用户 Skill 不会被删除。
t_keep_user_skill() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a" "$home/$V_TRAE_CN/skills/my-own"
  printf 'skill-a\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "保留用户 skill 场景退出码为 0"
  assert_dir_exists "$home/$V_TRAE_CN/skills/my-own" "用户自有 skill 保留"
  rm -rf "$home" "$src"
}

# t_intra_skill_mirror: Skill 内已从上游删除的文件不会残留。
t_intra_skill_mirror() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a"
  printf 'old\n' > "$home/$V_TRAE_CN/skills/skill-a/old.md"
  printf 'skill-a\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  printf 'new\n' > "$src/skills/skill-a/new.md"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "skill 内镜像退出码为 0"
  assert_file_absent "$home/$V_TRAE_CN/skills/skill-a/old.md" "旧文件被移除"
  assert_file_exists "$home/$V_TRAE_CN/skills/skill-a/new.md" "新文件已写入"
  rm -rf "$home" "$src"
}

# t_missing_manifest_degrade: 显式选择的首次 update 不删除未知目录并补写 manifest。
t_missing_manifest_degrade() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a" "$home/$V_TRAE_CN/skills/my-own"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a skill-c
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "manifest 缺失降级退出码为 0"
  assert_dir_exists "$home/$V_TRAE_CN/skills/my-own" "无 manifest 时用户 skill 保留"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-c" "无 manifest 时新增 skill"
  assert_file_exists "$home/$V_TRAE_CN/skills/$MANIFEST" "无 manifest 时补写 manifest"
  rm -rf "$home" "$src"
}

# t_reuses_complete_agents: 完整 .agents 下唯一托管 Rule 自动定位并清理同目录副本。
t_reuses_complete_agents() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a" "$home/$V_TRAE_CN/skills/my-own"
  printf 'skill-a\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  mkdir -p "$home/$V_TRAE_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nold\n' > "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  make_fake_agents_superpowers "$home"
  printf 'external\n' > "$home/.agents/skills/using-superpowers/external.txt"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$home/missing" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "完整 .agents 复用更新退出码为 0"
  assert_dir_absent "$home/$V_TRAE_CN/skills/skill-a" "Trae 托管副本被清理"
  assert_file_absent "$home/$V_TRAE_CN/skills/$MANIFEST" "Trae manifest 被清理"
  assert_dir_exists "$home/$V_TRAE_CN/skills/my-own" "Trae 用户 skill 保留"
  assert_file_exists "$home/.agents/skills/using-superpowers/external.txt" ".agents 内容未被更新"
  local marked; marked="$(grep -rl 'trae-superpowers-managed-rule' "$home/$V_TRAE_CN/user_rules" 2>/dev/null | head -1)"
  assert_file_exists "$marked" "复用更新仍刷新 User Rule"
  rm -rf "$home"
}

# t_agents_ambiguous_rules_uses_target: 完整 .agents 且两边都有托管 Rule 时按显式目标刷新。
t_agents_ambiguous_rules_uses_target() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/user_rules" "$home/$V_TRAE/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\ncn-old\n' > "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  printf '<!-- trae-superpowers-managed-rule -->\nintl-old\n' > "$home/$V_TRAE/user_rules/rule-managed.md"
  make_fake_agents_superpowers "$home"
  HOME="$home" SUPERPOWERS_TARGET=trae SUPERPOWERS_SKILLS_SRC="$home/missing" \
    bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "双托管 Rule 时显式选择更新成功"
  assert_file_contains "$home/$V_TRAE_CN/user_rules/rule-managed.md" "cn-old" "未选 Rule 保持不变"
  assert_file_contains "$home/$V_TRAE/user_rules/rule-managed.md" "**Superpowers Skills System**" "所选 Rule 已刷新"
  rm -rf "$home"
}

# t_reuse_preserves_agents_alias: Trae skills 指向 .agents 时 update 不得间接清理外部安装。
t_reuse_preserves_agents_alias() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN"
  make_fake_agents_superpowers "$home"
  printf 'using-superpowers\n' > "$home/.agents/skills/$MANIFEST"
  ln -s "$home/.agents/skills" "$home/$V_TRAE_CN/skills"
  mkdir -p "$home/$V_TRAE_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nold\n' > "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$home/missing" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "update 复用 .agents 软链接场景退出码为 0"
  assert_file_exists "$home/.agents/skills/using-superpowers/SKILL.md" "update 保留外部 skill"
  assert_file_exists "$home/.agents/skills/$MANIFEST" "update 不删除外部 manifest"
  rm -rf "$home"
}

# t_partial_agents_updates_trae: 残缺 .agents 不阻断正常 Trae 更新。
t_partial_agents_updates_trae() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/skill-a"
  printf 'skill-a\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  make_fake_agents_superpowers "$home" using-superpowers
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a skill-b
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "残缺 .agents 正常更新 Trae"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-b" "新 skill 写入 Trae"
  assert_file_exists "$home/.agents/skills/using-superpowers/SKILL.md" "残缺 .agents 保留"
  rm -rf "$home" "$src"
}

# t_refuses_agents_alias_update: 普通更新不得经 Trae 软链接修改 .agents。
t_refuses_agents_alias_update() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN" "$home/.agents/skills/skill-a"
  printf 'old\n' > "$home/.agents/skills/skill-a/state"
  printf 'skill-a\n' > "$home/.agents/skills/$MANIFEST"
  ln -s "$home/.agents/skills" "$home/$V_TRAE_CN/skills"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a
  printf 'new\n' > "$src/skills/skill-a/state"
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 5 "$?" "指向 .agents 的更新目标被拒绝"
  assert_file_contains "$home/.agents/skills/skill-a/state" "old" ".agents 内容未被镜像"
  assert_file_exists "$home/.agents/skills/$MANIFEST" ".agents manifest 未被删除"
  rm -rf "$home" "$src"
}

# t_update_writes_user_rule: 普通更新会刷新托管 User Rule。
t_update_writes_user_rule() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$UPDATE" >/dev/null 2>&1
  assert_exit_code 0 "$?" "update 写规则退出码为 0"
  local marked; marked="$(grep -rl 'trae-superpowers-managed-rule' "$home/$V_TRAE_CN/user_rules" 2>/dev/null | head -1)"
  assert_file_exists "$marked" "update 后存在带标记规则"
  assert_file_contains "$marked" "**Platform Adaptation (Trae)**" "规则含 Trae 适配段"
  rm -rf "$home" "$src"
}

t_no_manifest_without_target
t_no_manifest_uses_target
t_basic_update
t_two_manifests_updates_selected
t_remove_orphan
t_keep_user_skill
t_intra_skill_mirror
t_missing_manifest_degrade
t_reuses_complete_agents
t_agents_ambiguous_rules_uses_target
t_reuse_preserves_agents_alias
t_partial_agents_updates_trae
t_refuses_agents_alias_update
t_update_writes_user_rule
finish_tests

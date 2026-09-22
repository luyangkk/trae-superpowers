#!/usr/bin/env bash
# install.sh 行为测试。用隔离 HOME + 假 skills 源,离线运行。
# 目录名用八进制字节转义构造,规避环境对 dot-trae 等连续词元的改写。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/test_helpers.bash
source "$HERE/test_helpers.bash"
INSTALL="$HERE/../install.sh"

V_TRAE_CN="$(printf '\056trae-cn')"
V_TRAE="$(printf '\056trae')"
MANIFEST=".superpowers-manifest"

# t_target_case: 显式目标会创建对应 Trae 目录并只安装到该目录。
# 参数: $1=环境变量值 $2=变体根目录名 $3=用例前缀
t_target_case() {
  local target="$1" root="$2" label="$3"
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_TARGET="$target" SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "$label: 显式目标安装成功"
  assert_dir_exists "$home/$root/skills/using-superpowers" "$label: using-superpowers 被复制"
  assert_dir_exists "$home/$root/skills/brainstorming" "$label: brainstorming 被复制"
  assert_file_exists "$home/$root/skills/$MANIFEST" "$label: manifest 已生成"
  rm -rf "$home" "$src"
}

# t_no_target_without_tty: 无 TTY 且未指定目标时必须失败,不能静默选默认值。
t_no_target_without_tty() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TTY=/dev/null SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" </dev/null >/dev/null 2>&1
  assert_exit_code 2 "$?" "无 TTY 且无目标时退出码为 2"
  assert_dir_absent "$home/$V_TRAE_CN" "失败时不创建国内版目录"
  assert_dir_absent "$home/$V_TRAE" "失败时不创建国际版目录"
  rm -rf "$home" "$src"
}

# t_invalid_target: 非法 SUPERPOWERS_TARGET 必须失败。
t_invalid_target() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=invalid SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 2 "$?" "非法目标退出码为 2"
  rm -rf "$home" "$src"
}

# t_only_selected_variant: 两个 Trae 目录都存在时只写入用户选择的目标。
t_only_selected_variant() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN" "$home/$V_TRAE"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "双变体场景安装成功"
  assert_dir_absent "$home/$V_TRAE_CN/skills/using-superpowers" "未选择的国内版未写入"
  assert_dir_exists "$home/$V_TRAE/skills/using-superpowers" "选择的国际版已写入"
  rm -rf "$home" "$src"
}

# t_reinstall_other_target_keeps_old: 再次安装到另一目录时不迁移或清理旧目录。
t_reinstall_other_target_keeps_old() {
  local home; home="$(make_temp_home)"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  HOME="$home" SUPERPOWERS_TARGET=trae SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "切换目标重复安装成功"
  assert_file_exists "$home/$V_TRAE_CN/skills/$MANIFEST" "旧目标 manifest 保留"
  assert_file_exists "$home/$V_TRAE/skills/$MANIFEST" "新目标 manifest 已写入"
  rm -rf "$home" "$src"
}

# t_reuses_complete_agents: 完整 .agents 被直接复用,只在所选 Trae 目录写规则。
t_reuses_complete_agents() {
  local home; home="$(make_temp_home)"
  make_fake_agents_superpowers "$home"
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$home/missing" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "完整 .agents 复用场景退出码为 0"
  assert_dir_absent "$home/$V_TRAE_CN/skills/using-superpowers" "复用时不向 Trae 复制 skill"
  assert_file_absent "$home/$V_TRAE_CN/skills/$MANIFEST" "复用时不写 Trae manifest"
  assert_file_exists "$home/.agents/skills/using-superpowers/SKILL.md" ".agents 内容保持存在"
  local marked; marked="$(grep -rl 'trae-superpowers-managed-rule' "$home/$V_TRAE_CN/user_rules" 2>/dev/null | head -1)"
  assert_file_exists "$marked" "复用时仍写入 Trae User Rule"
  assert_dir_absent "$home/$V_TRAE/user_rules" "未选择的变体不写规则"
  rm -rf "$home"
}

# t_reuse_cleans_selected_duplicate: 复用 .agents 时只清理所选目录中 manifest 管理的副本。
t_reuse_cleans_managed_duplicate() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/using-superpowers"
  mkdir -p "$home/$V_TRAE_CN/skills/my-own"
  mkdir -p "$home/$V_TRAE/skills/using-superpowers"
  printf 'using-superpowers\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  printf 'using-superpowers\n' > "$home/$V_TRAE/skills/$MANIFEST"
  make_fake_agents_superpowers "$home"
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$home/missing" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "复用清理旧副本场景退出码为 0"
  assert_dir_absent "$home/$V_TRAE_CN/skills/using-superpowers" "manifest 管理的重复副本被清理"
  assert_file_absent "$home/$V_TRAE_CN/skills/$MANIFEST" "旧 manifest 被清理"
  assert_dir_exists "$home/$V_TRAE_CN/skills/my-own" "未记录的用户 skill 保留"
  assert_file_exists "$home/$V_TRAE/skills/$MANIFEST" "未选择目录的 manifest 保留"
  rm -rf "$home"
}

# t_reuse_preserves_agents_alias: Trae skills 指向 .agents 时不得经由别名清理外部安装。
t_reuse_preserves_agents_alias() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN"
  make_fake_agents_superpowers "$home"
  printf 'using-superpowers\n' > "$home/.agents/skills/$MANIFEST"
  ln -s "$home/.agents/skills" "$home/$V_TRAE_CN/skills"
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$home/missing" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "复用 .agents 软链接场景退出码为 0"
  assert_file_exists "$home/.agents/skills/using-superpowers/SKILL.md" "软链接场景保留外部 skill"
  assert_file_exists "$home/.agents/skills/$MANIFEST" "软链接场景不删除外部 manifest"
  rm -rf "$home"
}

# t_partial_agents_installs_trae: 残缺 .agents 不被接管,完整副本安装到 Trae。
t_partial_agents_installs_trae() {
  local home; home="$(make_temp_home)"
  make_fake_agents_superpowers "$home" using-superpowers brainstorming test-driven-development
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers brainstorming
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "残缺 .agents 场景退出码为 0"
  assert_file_exists "$home/.agents/skills/using-superpowers/SKILL.md" "残缺 .agents 内容保留"
  assert_dir_exists "$home/$V_TRAE_CN/skills/brainstorming" "完整副本安装到 Trae"
  assert_file_exists "$home/$V_TRAE_CN/skills/$MANIFEST" "Trae manifest 已生成"
  rm -rf "$home" "$src"
}

# t_refuses_agents_alias_install: Trae skills 指向 .agents 时不得写入外部目录。
t_refuses_agents_alias_install() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN" "$home/.agents/skills/external"
  printf 'keep\n' > "$home/.agents/skills/external/data"
  ln -s "$home/.agents/skills" "$home/$V_TRAE_CN/skills"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 5 "$?" "指向 .agents 的安装目标被拒绝"
  assert_file_contains "$home/.agents/skills/external/data" "keep" ".agents 原内容保持不变"
  assert_dir_absent "$home/.agents/skills/using-superpowers" ".agents 未写入新 skill"
  rm -rf "$home" "$src"
}

# t_refuses_agents_root_alias_install: Trae 根目录指向 .agents 时不得创建外部 skills 或规则。
t_refuses_agents_root_alias_install() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/.agents"
  ln -s "$home/.agents" "$home/$V_TRAE_CN"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 5 "$?" "指向 .agents 根目录的安装目标被拒绝"
  assert_dir_absent "$home/.agents/skills" ".agents 下未创建 skills"
  assert_dir_absent "$home/.agents/user_rules" ".agents 下未创建 user_rules"
  rm -rf "$home" "$src"
}

# t_reuse_rejects_agents_rule_alias: 复用模式也不得经 Trae 根目录别名写 .agents User Rule。
t_reuse_rejects_agents_rule_alias() {
  local home; home="$(make_temp_home)"
  make_fake_agents_superpowers "$home"
  ln -s "$home/.agents" "$home/$V_TRAE_CN"
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$home/missing" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 5 "$?" "复用模式拒绝 .agents 根目录别名"
  assert_dir_absent "$home/.agents/user_rules" "复用模式未向 .agents 写规则"
  rm -rf "$home"
}

# t_reuse_skips_unsafe_manifest_name: 复用清理不会按越界 manifest 删除 skills 外目录。
t_reuse_skips_unsafe_manifest_name() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills" "$home/$V_TRAE_CN/victim"
  printf 'keep\n' > "$home/$V_TRAE_CN/victim/data"
  printf '../victim\n' > "$home/$V_TRAE_CN/skills/$MANIFEST"
  make_fake_agents_superpowers "$home"
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$home/missing" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "复用清理忽略不安全 manifest 名称"
  assert_file_contains "$home/$V_TRAE_CN/victim/data" "keep" "复用清理保留 skills 外目录"
  rm -rf "$home"
}

# t_manifest_write_replaces_symlink: 写 manifest 时替换软链接本身,不得覆盖 .agents 文件。
t_manifest_write_replaces_symlink() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills" "$home/.agents"
  printf 'keep\n' > "$home/.agents/external-manifest"
  ln -s "$home/.agents/external-manifest" "$home/$V_TRAE_CN/skills/$MANIFEST"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "manifest 软链接场景安装成功"
  assert_file_contains "$home/.agents/external-manifest" "keep" ".agents 外部文件未被覆盖"
  assert_file_contains "$home/$V_TRAE_CN/skills/$MANIFEST" "using-superpowers" "目标 manifest 已写入"
  rm -rf "$home" "$src"
}

# t_manifest_rm_failure_stops_replace: 删除 manifest 软链接失败时不得继续向其目标目录移动文件。
t_manifest_rm_failure_stops_replace() {
  local home; home="$(make_temp_home)"
  local fakebin; fakebin="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills" "$home/.agents/external-dir"
  ln -s "$home/.agents/external-dir" "$home/$V_TRAE_CN/skills/$MANIFEST"
  # shellcheck disable=SC2016 # 变量由生成的假 rm 脚本在运行时展开。
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$1" = "-f" ] && [ "$2" = "$BLOCK_RM_PATH" ]; then exit 1; fi' \
    'exec /bin/rm "$@"' > "$fakebin/rm"
  chmod +x "$fakebin/rm"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" PATH="$fakebin:$PATH" BLOCK_RM_PATH="$home/$V_TRAE_CN/skills/$MANIFEST" \
    SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 4 "$?" "删除 manifest 链接失败时安装返回错误"
  assert_dir_empty "$home/.agents/external-dir" "删除链接失败时 .agents 目标目录保持为空"
  rm -rf "$home" "$src" "$fakebin"
}

# t_manifest_write_failure_returns_error: 临时 manifest 写入失败时不得移动半成品。
t_manifest_write_failure_returns_error() {
  local home; home="$(make_temp_home)"
  local fakebin; fakebin="$(make_temp_home)"
  mkdir -p "$home/.agents/external-dir"
  # shellcheck disable=SC2016 # 变量由生成的假 mktemp 脚本在运行时展开。
  printf '%s\n' '#!/usr/bin/env bash' \
    'rm -f "$FAKE_TMP_PATH"' \
    'ln -s "$FAKE_TMP_TARGET" "$FAKE_TMP_PATH"' \
    'printf "%s\n" "$FAKE_TMP_PATH"' > "$fakebin/mktemp"
  chmod +x "$fakebin/mktemp"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" PATH="$fakebin:$PATH" FAKE_TMP_PATH="$fakebin/write-target" \
    FAKE_TMP_TARGET="$home/.agents/external-dir" SUPERPOWERS_TARGET=trae-cn \
    SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 4 "$?" "临时 manifest 写入失败时安装返回错误"
  assert_file_absent "$home/$V_TRAE_CN/skills/$MANIFEST" "写入失败时不发布 manifest"
  rm -rf "$home" "$src" "$fakebin"
}

# t_rule_write_replaces_symlink: 刷新 Rule 时替换软链接本身,不得覆盖 .agents 文件。
t_rule_write_replaces_symlink() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/user_rules" "$home/.agents"
  printf '<!-- trae-superpowers-managed-rule -->\nkeep\n' > "$home/.agents/external-rule.md"
  ln -s "$home/.agents/external-rule.md" "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "Rule 软链接场景安装成功"
  assert_file_contains "$home/.agents/external-rule.md" "keep" ".agents 外部 Rule 未被覆盖"
  assert_file_contains "$home/$V_TRAE_CN/user_rules/rule-managed.md" "**Superpowers Skills System**" "目标 Rule 已刷新"
  rm -rf "$home" "$src"
}

# t_rule_rm_failure_returns_error: 无法安全替换 Rule 软链接时安装必须返回错误。
t_rule_rm_failure_returns_error() {
  local home; home="$(make_temp_home)"
  local fakebin; fakebin="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/user_rules" "$home/.agents"
  printf '<!-- trae-superpowers-managed-rule -->\nkeep\n' > "$home/.agents/external-rule.md"
  ln -s "$home/.agents/external-rule.md" "$home/$V_TRAE_CN/user_rules/rule-managed.md"
  # shellcheck disable=SC2016 # 变量由生成的假 rm 脚本在运行时展开。
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$1" = "-f" ] && [ "$2" = "$BLOCK_RM_PATH" ]; then exit 1; fi' \
    'exec /bin/rm "$@"' > "$fakebin/rm"
  chmod +x "$fakebin/rm"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" PATH="$fakebin:$PATH" BLOCK_RM_PATH="$home/$V_TRAE_CN/user_rules/rule-managed.md" \
    SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 4 "$?" "删除 Rule 链接失败时安装返回错误"
  assert_file_contains "$home/.agents/external-rule.md" "keep" "Rule 替换失败时 .agents 文件不变"
  rm -rf "$home" "$src" "$fakebin"
}

# t_reinstall_no_nesting: 重复安装刷新顶层内容且不产生嵌套目录。
t_reinstall_no_nesting() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills/using-superpowers"
  printf 'old\n' > "$home/$V_TRAE_CN/skills/using-superpowers/SKILL.md"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  printf 'new\n' > "$src/skills/using-superpowers/SKILL.md"
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "重复安装退出码为 0"
  assert_dir_absent "$home/$V_TRAE_CN/skills/using-superpowers/using-superpowers" "重复安装不产生嵌套目录"
  assert_file_contains "$home/$V_TRAE_CN/skills/using-superpowers/SKILL.md" "new" "重复安装刷新顶层内容"
  rm -rf "$home" "$src"
}

# t_copy_failure_skips_manifest: 复制失败的 skill 不写入 manifest,其余 skill 正常。
t_copy_failure_skips_manifest() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/skills"
  printf 'iamfile\n' > "$home/$V_TRAE_CN/skills/skill-b"
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a skill-b
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "复制失败场景退出码为 0"
  assert_dir_exists "$home/$V_TRAE_CN/skills/skill-a" "未受影响的 skill-a 正常安装"
  assert_file_contains "$home/$V_TRAE_CN/skills/$MANIFEST" "skill-a" "manifest 含成功的 skill-a"
  assert_file_absent_line "$home/$V_TRAE_CN/skills/$MANIFEST" "skill-b" "manifest 不含失败的 skill-b"
  rm -rf "$home" "$src"
}

# t_writes_user_rule: 正常安装会写入带标记的完整 User Rule。
t_writes_user_rule() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  local marked; marked="$(grep -rl 'trae-superpowers-managed-rule' "$home/$V_TRAE_CN/user_rules" 2>/dev/null | head -1)"
  assert_file_exists "$marked" "user_rules 下存在带标记的规则文件"
  assert_file_contains "$marked" "**Superpowers Skills System**" "规则含 Superpowers 触发段"
  assert_file_contains "$marked" "**Platform Adaptation (Trae)**" "规则含 Trae 适配段"
  rm -rf "$home" "$src"
}

# t_user_rule_idempotent: 已有托管规则时覆盖原文件并收敛为唯一。
t_user_rule_idempotent() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/user_rules"
  printf '<!-- trae-superpowers-managed-rule -->\nold body\n' > "$home/$V_TRAE_CN/user_rules/rule-existing.md"
  printf '<!-- trae-superpowers-managed-rule -->\nold duplicate\n' > "$home/$V_TRAE_CN/user_rules/rule-duplicate.md"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  local n marked
  n="$(grep -rl 'trae-superpowers-managed-rule' "$home/$V_TRAE_CN/user_rules" 2>/dev/null | wc -l | tr -d ' ')"
  marked="$(grep -rl 'trae-superpowers-managed-rule' "$home/$V_TRAE_CN/user_rules" 2>/dev/null | head -1)"
  assert_exit_code 1 "$n" "托管规则收敛为唯一"
  assert_file_exists "$marked" "收敛后托管规则文件存在"
  assert_file_contains "$marked" "**Superpowers Skills System**" "托管规则内容已刷新"
  rm -rf "$home" "$src"
}

# t_user_rule_preserves_user_files: 安装不修改无托管标记的用户规则。
t_user_rule_preserves_user_files() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_TRAE_CN/user_rules"
  printf 'my own rule\n' > "$home/$V_TRAE_CN/user_rules/rule-mine.md"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_TARGET=trae-cn SUPERPOWERS_SKILLS_SRC="$src" \
    bash "$INSTALL" >/dev/null 2>&1
  assert_file_contains "$home/$V_TRAE_CN/user_rules/rule-mine.md" "my own rule" "用户自有规则内容保留"
  rm -rf "$home" "$src"
}

t_target_case trae-cn "$V_TRAE_CN" "trae-cn"
t_target_case trae "$V_TRAE" "trae"
t_no_target_without_tty
t_invalid_target
t_only_selected_variant
t_reinstall_other_target_keeps_old
t_reuses_complete_agents
t_reuse_cleans_managed_duplicate
t_reuse_preserves_agents_alias
t_partial_agents_installs_trae
t_refuses_agents_alias_install
t_refuses_agents_root_alias_install
t_reuse_rejects_agents_rule_alias
t_reuse_skips_unsafe_manifest_name
t_manifest_write_replaces_symlink
t_manifest_rm_failure_stops_replace
t_manifest_write_failure_returns_error
t_rule_write_replaces_symlink
t_rule_rm_failure_returns_error
t_reinstall_no_nesting
t_copy_failure_skips_manifest
t_writes_user_rule
t_user_rule_idempotent
t_user_rule_preserves_user_files
finish_tests

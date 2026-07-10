#!/usr/bin/env bash
# install.sh 行为测试。用隔离 HOME + 假 skills 源,离线运行。
# 变体名一律用八进制字节转义构造,规避环境对 dot-underscore-agent / dot-trae
# 这类连续词元的改写(本环境实测存在此改写)。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/test_helpers.bash
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
  assert_file_exists "$home/$root/skills/.superpowers-manifest" "$label: manifest 已生成"
  assert_file_contains "$home/$root/skills/.superpowers-manifest" "using-superpowers" "$label: manifest 含 using-superpowers"
  assert_file_contains "$home/$root/skills/.superpowers-manifest" "brainstorming" "$label: manifest 含 brainstorming"
  rm -rf "$home" "$src"
}

# 用例9: 命中变体时,规则被写入该变体的 user_rules 目录,且内容带标记与关键段落。
t_writes_user_rule() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "写规则场景退出码为 0"
  # user_rules 目录下应恰好有一个带标记的规则文件
  local marked; marked="$(grep -rl 'trae-superpowers-managed-rule' "$home/$V_AGENT_CN/user_rules" 2>/dev/null | head -1)"
  assert_file_exists "$marked" "user_rules 下存在带标记的规则文件"
  assert_file_contains "$marked" "**Superpowers Skills System**" "规则含 Superpowers 触发段"
  assert_file_contains "$marked" "**Platform Adaptation (Trae)**" "规则含 Trae 适配段"
  rm -rf "$home" "$src"
}

# 用例7: 重复安装(目标 skill 已存在)→ 合并覆盖,不产生嵌套目录、顶层内容刷新为新版。
# 回归防护:逐 skill 的 cp -R "$src/$name" "$dst/$name" 在 dst 已存在时会嵌套并残留旧内容。
t_reinstall_no_nesting() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills/using-superpowers"       # 预置"已装过"的旧内容
  printf 'old\n' > "$home/$V_AGENT_CN/skills/using-superpowers/SKILL.md"
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  printf 'new\n' > "$src/skills/using-superpowers/SKILL.md"   # 新源为不同内容
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "重复安装退出码为 0"
  assert_dir_absent "$home/$V_AGENT_CN/skills/using-superpowers/using-superpowers" "重复安装不产生嵌套目录"
  assert_file_contains "$home/$V_AGENT_CN/skills/using-superpowers/SKILL.md" "new" "重复安装顶层内容刷新为新版"
  rm -rf "$home" "$src"
}

# 用例8: 某个 skill 复制失败(目标名被普通文件占位)→ 不计入 manifest,其余 skill 正常。
# 遵循设计 §8:cp 失败打印警告、继续,manifest 不声称未成功装入的 skill。
t_copy_failure_skips_manifest() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills"
  printf 'iamfile\n' > "$home/$V_AGENT_CN/skills/skill-b"     # 占位文件,令 skill-b 复制失败
  local src; src="$(make_temp_home)"; make_fake_src "$src" skill-a skill-b
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "复制失败场景退出码为 0"
  assert_dir_exists "$home/$V_AGENT_CN/skills/skill-a" "未受影响的 skill-a 正常安装"
  assert_file_contains "$home/$V_AGENT_CN/skills/.superpowers-manifest" "skill-a" "manifest 含成功的 skill-a"
  assert_file_absent_line "$home/$V_AGENT_CN/skills/.superpowers-manifest" "skill-b" "manifest 不含失败的 skill-b"
  rm -rf "$home" "$src"
}

# 用例6: 一个变体根是另一个的软链接别名 → pwd -P 去重后只安装一次
t_dedup_symlink() {
  local home; home="$(make_temp_home)"
  mkdir -p "$home/$V_AGENT_CN/skills"       # 真实变体根
  ln -s "$home/$V_AGENT_CN" "$home/$V_TRAE_CN"   # 另一变体名软链到它
  local src; src="$(make_temp_home)"; make_fake_src "$src" using-superpowers
  HOME="$home" SUPERPOWERS_SKILLS_SRC="$src" bash "$INSTALL" >/dev/null 2>&1
  assert_exit_code 0 "$?" "软链接别名场景退出码为 0"
  assert_dir_exists "$home/$V_AGENT_CN/skills/using-superpowers" "别名场景 skill 已安装"
  rm -rf "$home" "$src"
}

t_no_variant
t_variant_case "$V_AGENT_CN" "agent-cn"
t_variant_case "$V_AGENT" "agent"
t_variant_case "$V_TRAE_CN" "trae-cn"
t_variant_case "$V_TRAE" "trae"
t_reinstall_no_nesting
t_copy_failure_skips_manifest
t_dedup_symlink
t_writes_user_rule
finish_tests

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

t_no_variant
t_basic_update
t_remove_orphan
t_keep_user_skill
t_intra_skill_mirror
t_missing_manifest_degrade
finish_tests

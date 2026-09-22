#!/usr/bin/env bash
# uninstall.sh — 从 Trae 全局技能目录移除本工程装入的 upstream skills。
# 自包含,兼容 bash 3.2。仅删除 upstream 提供的 skill,不触碰用户其它 skill。
#
# 注意:隐藏目录名用八进制字节转义构造(\056="."),规避部分环境
# 对连续词元 dot-trae 的改写。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"
# manifest 文件名:本工程装入 skill 的清单;优先据此精确卸载。
MANIFEST=".superpowers-manifest"

# MARKER: 本工程写入 User Rules 的标记;卸载据此精确删除,不触碰用户自有规则。
MARKER="<!-- trae-superpowers-managed-rule -->"

# log: 统一日志输出。参数: $1=级别(INFO/WARN/ERROR) $2..=消息。
# ERROR 走 stderr,其余走 stdout,便于 grep 过滤与错误重定向;不带时间戳保持简洁。
log() {
  local level="$1"; shift
  case "$level" in
    ERROR) printf '[%s] %s\n' "$level" "$*" >&2 ;;
    *)     printf '[%s] %s\n' "$level" "$*" ;;
  esac
}

# target_root: 把公开目标名转换为 HOME 下的 Trae 根目录名。
# 参数: $1=trae-cn|trae。非法值返回 1。
target_root() {
  case "$1" in
    trae-cn) printf '\056trae-cn\n' ;;
    trae)    printf '\056trae\n' ;;
    *)       return 1 ;;
  esac
}

# select_target: 从环境变量或 /dev/tty 选择唯一 Trae 目标,输出 trae-cn 或 trae。
# curl|bash 会占用 stdin,因此交互始终直接读写控制终端。
select_target() {
  local target="${SUPERPOWERS_TARGET:-}" tty="${SUPERPOWERS_TTY:-/dev/tty}"
  local key rest selected=0 esc
  if [ -n "$target" ]; then
    if target_root "$target" >/dev/null; then
      printf '%s\n' "$target"
      return 0
    fi
    log ERROR "invalid SUPERPOWERS_TARGET: $target (expected trae-cn or trae)"
    return 2
  fi
  if ! ( : <"$tty" ) 2>/dev/null; then
    log ERROR "no interactive terminal; set SUPERPOWERS_TARGET=trae-cn or trae."
    return 2
  fi
  exec 3<>"$tty"
  if [ ! -t 3 ]; then
    exec 3>&-
    log ERROR "no interactive terminal; set SUPERPOWERS_TARGET=trae-cn or trae."
    return 2
  fi
  esc="$(printf '\033')"
  printf 'Select the Trae installation to manage:\n' >&3
  printf '  > Trae CN        (~/%s/skills)\n' "$(target_root trae-cn)" >&3
  printf '    Trae Intl      (~/%s/skills)\n' "$(target_root trae)" >&3
  printf 'Use Up/Down arrows, then press Enter.' >&3
  while IFS= read -r -s -n 1 key <&3; do
    if [ -z "$key" ]; then
      break
    fi
    if [ "$key" = "$esc" ]; then
      IFS= read -r -s -n 2 rest <&3 || rest=""
      case "$rest" in
        "[A") selected=0 ;;
        "[B") selected=1 ;;
      esac
      if [ "$selected" -eq 0 ]; then
        printf '\r\033[2KSelected: Trae CN' >&3
      else
        printf '\r\033[2KSelected: Trae Intl' >&3
      fi
    fi
  done
  printf '\n' >&3
  exec 3>&-
  if [ "$selected" -eq 0 ]; then
    printf 'trae-cn\n'
  else
    printf 'trae\n'
  fi
}

# target_skills_dir: 输出指定 Trae 目标的全局 skills 目录。
# 参数: $1=trae-cn|trae。
target_skills_dir() {
  local root
  root="$(target_root "$1")" || return 1
  printf '%s/%s/skills\n' "$HOME" "$root"
}

# target_rules_dir: 输出指定 Trae 目标的 User Rules 目录。
# 参数: $1=trae-cn|trae。
target_rules_dir() {
  local root
  root="$(target_root "$1")" || return 1
  printf '%s/%s/user_rules\n' "$HOME" "$root"
}

# agents_skills_dir: 输出外部共享 skills 目录路径;本工程只检测和复用,不删除。
agents_skills_dir() {
  printf '%s/%s/skills\n' "$HOME" "$(printf '\056agents')"
}

# agents_superpowers_state: 检查 .agents 中四个核心 Superpowers Skill。
# 返回 0=完整可复用,1=完全未安装,2=残缺安装。
agents_superpowers_state() {
  local dir count=0 name
  dir="$(agents_skills_dir)"
  for name in using-superpowers brainstorming test-driven-development systematic-debugging; do
    [ -f "$dir/$name/SKILL.md" ] && count=$((count + 1))
  done
  [ "$count" -eq 4 ] && return 0
  [ "$count" -eq 0 ] && return 1
  return 2
}

# is_agents_skills_dir: 判断候选路径的最近存在父目录是否落在外部 .agents 树内。
# 候选目录尚未创建时仍能识别 Trae 根目录软链接,防止间接删除外部安装。
is_agents_skills_dir() {
  local candidate="$1" probe agents_root candidate_real agents_real parent
  agents_root="$HOME/$(printf '\056agents')"
  [ -d "$agents_root" ] || return 1
  probe="$candidate"
  while [ ! -d "$probe" ]; do
    parent="$(dirname "$probe")"
    [ "$parent" != "$probe" ] || return 1
    probe="$parent"
  done
  candidate_real="$(cd "$probe" 2>/dev/null && pwd -P)" || return 1
  agents_real="$(cd "$agents_root" 2>/dev/null && pwd -P)" || return 1
  case "$candidate_real" in
    "$agents_real"|"$agents_real"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# is_safe_skill_name: manifest 条目必须是单个普通目录名,不得包含路径分隔符。
# 参数: $1=skill 名。返回 0 表示可安全拼接到 skills 根目录下。
is_safe_skill_name() {
  local name="$1"
  [ -n "$name" ] && [ "$name" != "." ] && [ "$name" != ".." ] || return 1
  case "$name" in
    */*|*\\*) return 1 ;;
    *) return 0 ;;
  esac
}

# unique_manifest_target: 恰有一个 Trae 目标带 manifest 时输出其目标名。
# 两边都有或都没有时返回 1,交由 select_target 决定。
unique_manifest_target() {
  local target dir found="" count=0
  for target in trae-cn trae; do
    dir="$(target_skills_dir "$target")"
    if [ -f "$dir/$MANIFEST" ]; then
      found="$target"
      count=$((count + 1))
    fi
  done
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$found"
}

# resolve_src: 得到 upstream skills 清单来源(用于确定"哪些 skill 属于本工程")。
# 测试可用 SUPERPOWERS_SKILLS_SRC 注入;否则 clone upstream 到临时目录。
resolve_src() {
  if [ -n "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    log INFO "Using injected skills source: $SUPERPOWERS_SKILLS_SRC/skills" >&2
    printf '%s\n' "$SUPERPOWERS_SKILLS_SRC/skills"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/superpowers.XXXXXX")" || return 1
  log INFO "Cloning upstream: $UPSTREAM_URL" >&2
  if ! git clone --depth 1 "$UPSTREAM_URL" "$tmp" >/dev/null 2>&1; then
    log ERROR "git clone failed: $UPSTREAM_URL"
    rm -rf "$tmp"
    return 1
  fi
  log INFO "Cloned upstream into: $tmp" >&2
  printf '%s\n' "$tmp/skills"
}

# remove_by_manifest: 按目标目录内 manifest 逐名删除本工程装入的 skill,并删 manifest。
# 参数: $1=目标 skills 目录。返回 0 表示已按 manifest 处理;返回 1 表示无 manifest(交由回退)。
remove_by_manifest() {
  local dst="$1" name count=0
  [ -f "$dst/$MANIFEST" ] || return 1
  log INFO "Uninstalling by manifest: $dst/$MANIFEST"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! is_safe_skill_name "$name"; then
      log WARN "ignoring unsafe skill name in manifest: $name"
      continue
    fi
    if [ -d "$dst/$name" ]; then
      log INFO "  - $name"
      rm -rf "${dst:?}/${name:?}"
      count=$((count + 1))
    fi
  done < "$dst/$MANIFEST"
  rm -f "$dst/$MANIFEST"
  log INFO "Removed $count skill(s) and manifest from: $dst"
  return 0
}

# remove_managed_rule: 删除目标 user_rules 目录内所有带 MARKER 的规则文件。
# 只碰带标记文件,保留用户自有规则(含 user_rules.md 与其他 rule-*.md)。
# 参数: $1=目标 user_rules 目录
remove_managed_rule() {
  local dir="$1" f count=0
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    if grep -qF "$MARKER" "$f"; then
      log INFO "  - $f"
      rm -f "$f"
      count=$((count + 1))
    fi
  done
  log INFO "Removed $count managed rule file(s) from: $dir"
}

# remove_all_managed_rules: 遍历各变体 user_rules 目录,删除本工程写入的带标记规则。
remove_all_managed_rules() {
  local target rdir
  for target in trae-cn trae; do
    rdir="$(target_rules_dir "$target")"
    if is_agents_skills_dir "$rdir"; then
      log INFO "Skipping managed-rule cleanup through .agents alias: $rdir"
    else
      remove_managed_rule "$rdir"
    fi
  done
}

main() {
  local agents_state agents_dir target d rdir
  agents_dir="$(agents_skills_dir)"
  agents_superpowers_state
  agents_state=$?
  if [ "$agents_state" -eq 0 ]; then
    log INFO "Keeping external Superpowers skills unchanged at: $agents_dir"
    for target in trae-cn trae; do
      d="$(target_skills_dir "$target")"
      if [ -d "$d" ]; then
        if is_agents_skills_dir "$d"; then
          log INFO "Skipping managed-copy cleanup through .agents alias: $d"
        elif ! remove_by_manifest "$d"; then
          log INFO "No manifest in $d; leaving its skills unchanged."
        fi
      fi
    done
    remove_all_managed_rules
    log INFO "Done. Removed this project's Trae copies and User Rule; external .agents skills were preserved."
    return 0
  fi
  if [ "$agents_state" -eq 2 ]; then
    log WARN "Incomplete Superpowers installation found at $agents_dir; leaving it unchanged."
  fi
  if target="$(unique_manifest_target)"; then
    log INFO "Located managed target from manifest: $target"
  else
    target="$(select_target)" || return $?
  fi
  d="$(target_skills_dir "$target")"
  rdir="$(target_rules_dir "$target")"
  log INFO "Selected target: $d"
  if is_agents_skills_dir "$rdir"; then
    log ERROR "refusing to uninstall User Rules through a Trae path inside external .agents: $rdir"
    return 5
  fi
  if is_agents_skills_dir "$d"; then
    log ERROR "refusing to uninstall through Trae path that resolves to external .agents/skills: $d"
    return 5
  fi

  # manifest 存在时直接精确卸载,无需获取上游清单。
  if remove_by_manifest "$d"; then
    remove_managed_rule "$rdir"
    log INFO "Done. Removed Superpowers skills and the User Rule this project wrote."
    return 0
  fi

  # 无 manifest 时,仅在所选目标内按上游清单反推删除。
  log INFO "No manifest in $d; falling back to the upstream skill list."
  local src
  if ! src="$(resolve_src)"; then
    log ERROR "failed to obtain superpowers skills list."
    return 4
  fi
  if [ ! -d "$src" ]; then
    log ERROR "skills source not found: $src"
    [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ] && rm -rf "$(dirname "$src")"
    return 4
  fi

  local entry name
  if [ -d "$d" ]; then
    log INFO "Uninstalling by upstream list in: $d"
    for entry in "$src"/*/; do
      [ -d "$entry" ] || continue
      name="$(basename "$entry")"
      if [ -d "$d/$name" ]; then
        log INFO "  - $name"
        rm -rf "${d:?}/${name:?}"
      fi
    done
  fi

  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    log INFO "Cleaning up temporary clone: $(dirname "$src")"
    rm -rf "$(dirname "$src")"
  fi

  remove_managed_rule "$rdir"
  log INFO "Done. Removed Superpowers skills and the User Rule this project wrote."
  return 0
}

main "$@"

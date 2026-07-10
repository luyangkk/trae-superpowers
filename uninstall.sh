#!/usr/bin/env bash
# uninstall.sh — 从 Trae 全局技能目录移除本工程装入的 upstream skills。
# 自包含,兼容 bash 3.2。仅删除 upstream 提供的 skill,不触碰用户其它 skill。
#
# 注意:变体名用八进制字节转义构造(\056=".", \137="_"),规避部分环境
# 对连续词元 dot-underscore-agent / dot-trae 的改写。
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

# variant_roots: 逐行输出四个受支持的 Trae 变体根目录名。
variant_roots() {
  printf '%s\n' "$(printf '\056\137agent-cn')"
  printf '%s\n' "$(printf '\056\137agent')"
  printf '%s\n' "$(printf '\056trae-cn')"
  printf '%s\n' "$(printf '\056trae')"
}

# detect_skill_dirs: 探测已安装变体的 skills 目录(去重真实路径)。同 install.sh。
detect_skill_dirs() {
  local seen="" root c real
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    c="$HOME/$root/skills"
    if [ -d "$c" ] || [ -d "$HOME/$root" ]; then
      if [ -d "$c" ]; then
        real="$(cd "$c" 2>/dev/null && pwd -P)"
      else
        real="$c"
      fi
      case " $seen " in
        *" $real "*) : ;;
        *) seen="$seen $real"; printf '%s\n' "$c" ;;
      esac
    fi
  done <<EOF
$(variant_roots)
EOF
}

# detect_user_rules_dirs: 探测已安装 Trae 变体的 user_rules 目录,逐行输出(已去重真实路径)。
# 命中条件:变体根目录存在(user_rules 子目录可能尚未创建,由 write_rule 负责 mkdir -p)。
detect_user_rules_dirs() {
  local seen="" root c real
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    [ -d "$HOME/$root" ] || continue
    c="$HOME/$root/user_rules"
    if [ -d "$c" ]; then
      real="$(cd "$c" 2>/dev/null && pwd -P)"
    else
      real="$c"
    fi
    case " $seen " in
      *" $real "*) : ;;                 # 已去重,跳过软链接别名
      *) seen="$seen $real"; printf '%s\n' "$c" ;;
    esac
  done <<EOF
$(variant_roots)
EOF
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
  local rdir
  while IFS= read -r rdir; do
    [ -n "$rdir" ] || continue
    remove_managed_rule "$rdir"
  done <<EOF
$(detect_user_rules_dirs)
EOF
}

main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    log ERROR "no Trae installation detected."
    return 3
  fi
  log INFO "Detected target skill dirs:"
  printf '%s\n' "$dirs"

  # 第一遍:凡有 manifest 的目标目录,直接按 manifest 卸载(离线可用)。
  # 收集仍需回退处理(无 manifest)的目标目录到 fallback_dirs。
  local d fallback_dirs=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || continue
    if remove_by_manifest "$d"; then
      : # 已按 manifest 处理
    else
      log INFO "No manifest in $d; deferring to upstream-list fallback."
      fallback_dirs="$fallback_dirs
$d"
    fi
  done <<EOF
$dirs
EOF

  # 若所有目标都已按 manifest 处理完,无需获取上游清单。
  if [ -z "$(printf '%s' "$fallback_dirs" | tr -d '[:space:]')" ]; then
    remove_all_managed_rules
    log INFO "Done. Removed Superpowers skills and the User Rule this project wrote."
    return 0
  fi

  # 第二遍(回退):无 manifest 的目标,沿用"按上游清单反推删除"。
  log INFO "Falling back to upstream-list uninstall for manifest-less dirs."
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
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || continue
    log INFO "Uninstalling by upstream list in: $d"
    for entry in "$src"/*/; do
      [ -d "$entry" ] || continue
      name="$(basename "$entry")"
      if [ -d "$d/$name" ]; then
        log INFO "  - $name"
        rm -rf "${d:?}/${name:?}"
      fi
    done
  done <<EOF
$fallback_dirs
EOF

  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    log INFO "Cleaning up temporary clone: $(dirname "$src")"
    rm -rf "$(dirname "$src")"
  fi

  remove_all_managed_rules
  log INFO "Done. Removed Superpowers skills and the User Rule this project wrote."
  return 0
}

main "$@"

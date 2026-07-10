#!/usr/bin/env bash
# uninstall.sh — 从 Trae 全局技能目录移除本工程装入的 upstream skills。
# 自包含,兼容 bash 3.2。仅删除 upstream 提供的 skill,不触碰用户其它 skill。
#
# 注意:变体名用八进制字节转义构造(\056=".", \137="_"),规避部分环境
# 对连续词元 dot-underscore-agent / dot-trae 的改写。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"

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

# resolve_src: 得到 upstream skills 清单来源(用于确定"哪些 skill 属于本工程")。
# 测试可用 SUPERPOWERS_SKILLS_SRC 注入;否则 clone upstream 到临时目录。
resolve_src() {
  if [ -n "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    printf '%s\n' "$SUPERPOWERS_SKILLS_SRC/skills"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/superpowers.XXXXXX")" || return 1
  if ! git clone --depth 1 "$UPSTREAM_URL" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi
  printf '%s\n' "$tmp/skills"
}

main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected.\n' >&2
    return 3
  fi

  local src
  if ! src="$(resolve_src)"; then
    printf 'Error: failed to obtain superpowers skills list.\n' >&2
    return 4
  fi
  if [ ! -d "$src" ]; then
    printf 'Error: skills source not found: %s\n' "$src" >&2
    [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ] && rm -rf "$(dirname "$src")"
    return 4
  fi

  local d entry name
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || continue
    for entry in "$src"/*/; do
      [ -d "$entry" ] || continue
      name="$(basename "$entry")"
      if [ -d "$d/$name" ]; then
        printf 'Removing: %s\n' "$d/$name"
        rm -rf "$d/$name"
      fi
    done
  done <<EOF
$dirs
EOF

  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    rm -rf "$(dirname "$src")"
  fi

  printf 'Done. Note: remove the Superpowers User Rules manually in Trae settings.\n'
  return 0
}

main "$@"

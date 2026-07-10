#!/usr/bin/env bash
# install.sh — 把 upstream superpowers 的 skills 装入 Trae 全局技能目录。
# 自包含:不 source 外部文件(需兼容 curl|bash)。兼容 bash 3.2。
#
# 注意:变体目录名一律用八进制字节转义构造(\056=".", \137="_"),
# 因为部分编辑/传输环境会改写连续词元 dot-underscore-agent / dot-trae,
# 用转义可确保脚本落盘后字节不被污染。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"

# variant_roots: 逐行输出四个受支持的 Trae 变体根目录名(仅名字,不含 HOME)。
# 顺序:CN agent、国际 agent、CN trae、国际 trae。
variant_roots() {
  printf '%s\n' "$(printf '\056\137agent-cn')"
  printf '%s\n' "$(printf '\056\137agent')"
  printf '%s\n' "$(printf '\056trae-cn')"
  printf '%s\n' "$(printf '\056trae')"
}

# detect_skill_dirs: 探测已安装 Trae 变体的 skills 目录,逐行输出(已去重真实路径)。
# 命中条件:候选 skills 目录存在,或其变体根目录存在。
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
        *" $real "*) : ;;              # 已去重,跳过软链接别名
        *) seen="$seen $real"; printf '%s\n' "$c" ;;
      esac
    fi
  done <<EOF
$(variant_roots)
EOF
}

# resolve_src: 返回 skills 源目录(内含各 skill 子目录)。
# 测试可用 SUPERPOWERS_SKILLS_SRC 注入本地源以离线运行;
# 否则 git clone upstream 到临时目录,由调用方负责清理。
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

# copy_skills: 把源目录下所有 skill 复制到目标 skills 目录。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
copy_skills() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp -R "$src"/* "$dst"/
}

main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected.\n' >&2
    return 3
  fi
  printf 'Detected target skill dirs:\n%s\n' "$dirs"

  local src
  if ! src="$(resolve_src)"; then
    printf 'Error: failed to obtain superpowers skills source.\n' >&2
    return 4
  fi
  if [ ! -d "$src" ]; then
    printf 'Error: skills source not found: %s\n' "$src" >&2
    [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ] && rm -rf "$(dirname "$src")"
    return 4
  fi

  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf 'Installing skills into: %s\n' "$d"
    copy_skills "$src" "$d"
  done <<EOF
$dirs
EOF

  # 若为临时 clone(非注入源),安装后清理
  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    rm -rf "$(dirname "$src")"
  fi

  printf 'Done. Next: configure User Rules in Trae settings, then restart.\n'
  return 0
}

main "$@"

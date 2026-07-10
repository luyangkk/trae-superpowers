#!/usr/bin/env bash
# update.sh — 把 Trae 全局技能目录里本工程装入的 skills 精确镜像到 upstream 最新状态。
# 精确镜像:覆盖同名内容 + 删除上游已移除的孤儿 skill(仅限 manifest 记录范围)。
# 自包含:不 source 外部文件(需兼容 curl|bash)。兼容 bash 3.2。
#
# 注意:变体目录名一律用八进制字节转义构造(\056=".", \137="_"),
# 规避部分环境对连续词元 dot-underscore-agent / dot-trae 的改写。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"
# manifest 文件名:记录本工程装入的 skill 名单。
MANIFEST=".superpowers-manifest"

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

# resolve_src: 返回上游 skills 源目录(内含各 skill 子目录)。
# 测试可用 SUPERPOWERS_SKILLS_SRC 注入本地源以离线运行;否则 clone upstream 到临时目录。
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

# mirror_skills: 对新源里每个 skill 做逐 skill 清替(先删后拷),实现目录级镜像。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
mirror_skills() {
  local src="$1" dst="$2" entry name
  mkdir -p "$dst"
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    rm -rf "$dst/$name"
    cp -R "$src/$name" "$dst/$name"
  done
}

# write_manifest: 把源目录下所有 skill 名逐行写入目标 manifest(覆盖)。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
write_manifest() {
  local src="$1" dst="$2" entry name
  : > "$dst/$MANIFEST"
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    printf '%s\n' "$name" >> "$dst/$MANIFEST"
  done
}

# remove_orphans: 删除孤儿 skill —— 旧 manifest 记录过、但新源已不再提供的 skill。
# 严格限定 manifest 范围,绝不触碰未记录的用户自有 skill。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
remove_orphans() {
  local src="$1" dst="$2" name
  [ -f "$dst/$MANIFEST" ] || return 0     # 无旧 manifest → 无孤儿可删(降级)
  while IFS= read -r name; do
    [ -n "$name" ] || continue            # 跳过空行
    if [ ! -d "$src/$name" ]; then        # 旧记录的 skill 已不在新源 → 孤儿
      printf 'Removing orphan skill: %s\n' "$dst/$name"
      rm -rf "$dst/$name"
    fi
  done < "$dst/$MANIFEST"
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
    printf 'Updating skills in: %s\n' "$d"
    remove_orphans "$src" "$d"
    mirror_skills "$src" "$d"
    write_manifest "$src" "$d"
  done <<EOF
$dirs
EOF

  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    rm -rf "$(dirname "$src")"
  fi

  printf 'Done. Skills updated to latest upstream.\n'
  return 0
}

main "$@"

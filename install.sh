#!/usr/bin/env bash
# install.sh — 把 upstream superpowers 的 skills 装入 Trae 全局技能目录。
# 自包含:不 source 外部文件(需兼容 curl|bash)。兼容 bash 3.2。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"

# detect_skill_dirs: 探测已安装 Trae 变体的 skills 目录,逐行输出(已去重真实路径)。
# CN 候选: ~/.trae-cn/skills, ~/.trae-cn/skills
# intl 候选: ~/.trae/skills, ~/.trae/skills
detect_skill_dirs() {
  local candidates="$HOME/.trae-cn/skills $HOME/.trae-cn/skills $HOME/.trae/skills $HOME/.trae/skills"
  local seen="" c real
  for c in $candidates; do
    # 命中条件:候选目录本身存在,或其父目录(变体根)存在
    if [ -d "$c" ] || [ -d "$(dirname "$c")" ]; then
      # 解析真实路径以去重软链接别名
      if [ -d "$c" ]; then
        real="$(cd "$c" 2>/dev/null && pwd -P)"
      else
        real="$c"
      fi
      case " $seen " in
        *" $real "*) : ;;              # 已见过,跳过
        *) seen="$seen $real"; printf '%s\n' "$c" ;;
      esac
    fi
  done
}

main() {
  local dirs
  dirs="$(detect_skill_dirs)"
  if [ -z "$dirs" ]; then
    printf 'Error: no Trae installation detected (looked for ._agent-cn/._agent/.trae-cn/.trae).\n' >&2
    return 3
  fi
  printf 'Detected target skill dirs:\n%s\n' "$dirs"
  return 0
}

main "$@"

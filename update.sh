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

# MARKER: 本工程写入 User Rules 的标记(规则文件首行)。update/uninstall 据此识别与覆盖/删除,
# 确保幂等且不触碰用户自有规则。三个脚本共享同一字面量。
MARKER="<!-- trae-superpowers-managed-rule -->"

# RULE_BODY: 完整版 Superpowers User Rules 文本(含 Trae subagent 适配段)。
# 单一事实源以本脚本为准;update.sh 须保持逐字一致。
RULE_BODY="$(cat <<'RULEEOF'
**Superpowers Skills System**
You have superpowers skills installed globally. Before ANY task (coding, debugging, planning, reviewing), you MUST check if a relevant skill exists and invoke it.
If you think there is even a 1% chance a skill might apply, you ABSOLUTELY MUST invoke the skill. This is not optional.

**Skill Priority**
1. **Process skills first** (brainstorming, systematic-debugging) - determine HOW to approach the task
2. **Implementation skills second** (test-driven-development) - guide execution details

**Red Flags (Common excuses to skip skills)**
- "This is just a simple question" -> check skills
- "Let me just do this one thing first" -> check skills first
- "This skill is too heavy" -> use it
- "I need to understand more first" -> skill check before any action

**Platform Adaptation (Trae)**
When a skill says to "dispatch a subagent" (e.g. subagent-driven-development, dispatching-parallel-agents), use the native Agent tool:
- Dispatch = call the Agent tool with subagent_type "general-purpose". Do NOT pass a model parameter — let the subagent inherit the current session model. Trae routes models through its own gateway (e.g. openrouter-*), so hard-coded names like "sonnet"/"opus" that other Superpowers docs recommend are often unavailable and abort the run with error 4023 "The current model is unavailable".
- Ignore the "always specify the model explicitly" instruction in subagent-driven-development's Model Selection section when on Trae; it assumes model names Trae may not serve.
- Parallel = issue multiple Agent calls in one response, or use run_in_background for async work.
- Continue an existing subagent's context = SendMessage; a new Agent call starts fresh.
- Task tracking ("create a todo / mark complete") = TaskCreate / TaskUpdate / TaskList.
Trae fully supports subagents through these tools — never treat "dispatch a subagent" as unsupported.
RULEEOF
)"

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

# resolve_src: 返回上游 skills 源目录(内含各 skill 子目录)。
# 测试可用 SUPERPOWERS_SKILLS_SRC 注入本地源以离线运行;否则 clone upstream 到临时目录。
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

# mirror_skills: 对新源里每个 skill 做逐 skill 清替(先删后拷),实现目录级镜像。
# 先 rm 再 cp,故 dst/$name 不会残留旧文件、也不会嵌套。
# 单个 skill 复制失败时打印警告并跳过,不中断其余 skill(设计 §8)。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
mirror_skills() {
  local src="$1" dst="$2" entry name count=0
  mkdir -p "$dst"
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    rm -rf "${dst:?}/${name:?}"
    if cp -R "$src/$name" "$dst/$name"; then
      log INFO "  ~ $name"
      count=$((count + 1))
    else
      log WARN "mirror failed, skipped: $name"
    fi
  done
  log INFO "Mirrored $count skill(s) into: $dst"
}

# write_manifest: 把源目录下所有 skill 名逐行写入目标 manifest(覆盖)。
# 仅记录实际已落入 dst 的 skill(目录存在),避免声称镜像失败的 skill(设计 §8)。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
write_manifest() {
  local src="$1" dst="$2" entry name
  : > "$dst/$MANIFEST"
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    [ -d "$dst/$name" ] || continue       # 未成功镜像的 skill 不写入 manifest
    printf '%s\n' "$name" >> "$dst/$MANIFEST"
  done
  log INFO "Wrote manifest: $dst/$MANIFEST"
}

# write_rule: 幂等地把 Superpowers User Rules 写入目标 user_rules 目录。
# 扫描带 MARKER 的 *.md:命中则覆盖第一个(多命中时删除多余的,收敛为唯一);
# 未命中则新建 rule-<epoch>000.md(仿 Trae 原生 rule-<ms> 命名)。
# 只碰带 MARKER 的文件,不触碰用户自有规则。
# 参数: $1=目标 user_rules 目录
write_rule() {
  local dir="$1" target="" f
  mkdir -p "$dir"
  # 收集已存在的带标记文件
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    if grep -q "$MARKER" "$f"; then
      if [ -z "$target" ]; then
        target="$f"                     # 第一个命中作为覆盖目标
      else
        rm -f "$f"                       # 多余的重复标记文件,删除以收敛为唯一
        log WARN "removed duplicate managed rule: $f"
      fi
    fi
  done
  if [ -z "$target" ]; then
    target="$dir/rule-$(date +%s)000.md" # 首次创建:仿原生命名
  fi
  printf '%s\n%s\n' "$MARKER" "$RULE_BODY" > "$target"
  log INFO "Wrote User Rule: $target"
}

# remove_orphans: 删除孤儿 skill —— 旧 manifest 记录过、但新源已不再提供的 skill。
# 严格限定 manifest 范围,绝不触碰未记录的用户自有 skill。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
remove_orphans() {
  local src="$1" dst="$2" name count=0
  if [ ! -f "$dst/$MANIFEST" ]; then       # 无旧 manifest → 无孤儿可删(降级)
    log INFO "No manifest at $dst/$MANIFEST; skip orphan removal (first update)."
    return 0
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue            # 跳过空行
    if [ ! -d "$src/$name" ]; then        # 旧记录的 skill 已不在新源 → 孤儿
      log WARN "Removing orphan skill: $dst/$name"
      rm -rf "${dst:?}/${name:?}"
      count=$((count + 1))
    fi
  done < "$dst/$MANIFEST"
  log INFO "Removed $count orphan skill(s) from: $dst"
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

  local src
  if ! src="$(resolve_src)"; then
    log ERROR "failed to obtain superpowers skills source."
    return 4
  fi
  if [ ! -d "$src" ]; then
    log ERROR "skills source not found: $src"
    [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ] && rm -rf "$(dirname "$src")"
    return 4
  fi

  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    log INFO "Updating skills in: $d"
    remove_orphans "$src" "$d"
    mirror_skills "$src" "$d"
    write_manifest "$src" "$d"
  done <<EOF
$dirs
EOF

  # 自动刷新 User Rules(尽力而为:写入后需重启 Trae 验收;失败可 UI 手动回退)。
  local rdir
  while IFS= read -r rdir; do
    [ -n "$rdir" ] || continue
    write_rule "$rdir"
  done <<EOF
$(detect_user_rules_dirs)
EOF

  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    log INFO "Cleaning up temporary clone: $(dirname "$src")"
    rm -rf "$(dirname "$src")"
  fi

  log INFO "Done. Skills updated to latest upstream."
  return 0
}

main "$@"

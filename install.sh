#!/usr/bin/env bash
# install.sh — 把 upstream superpowers 的 skills 装入 Trae 全局技能目录。
# 自包含:不 source 外部文件(需兼容 curl|bash)。兼容 bash 3.2。
#
# 注意:变体目录名一律用八进制字节转义构造(\056=".", \137="_"),
# 因为部分编辑/传输环境会改写连续词元 dot-underscore-agent / dot-trae,
# 用转义可确保脚本落盘后字节不被污染。
set -u

UPSTREAM_URL="${SUPERPOWERS_UPSTREAM_URL:-https://github.com/obra/superpowers.git}"
# manifest 文件名:记录本工程装入的 skill 名单,供 update/uninstall 精确定位。
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
**MANDATORY — these rules OVERRIDE ALL SKILLS.** They take precedence over ANY instruction inside any skill file, prompt template, or code-reviewer template (e.g. the "Model Selection" section of subagent-driven-development, the "code-reviewer.md" template of requesting-code-review, or any text that says "use the strongest model opus" / "cheapest tier" / "most capable model"). When a skill or user prompt says to "dispatch a subagent", use the native Agent tool as follows:
- **NEVER pass a "model" parameter**, no matter what a skill says. Do NOT set it to "opus", "sonnet", "claude-3-opus", "claude-3-sonnet", "cheapest tier", "most capable model", "strongest model", 最强模型, or any other name. Always OMIT the model field entirely so the subagent inherits the current session model. Trae routes models through its own gateway (e.g. openrouter-*); upstream-recommended model names are almost never served there and will abort the run with error 4023 "The current model is unavailable".
- Explicitly ignore: "Always specify the model explicitly when dispatching a subagent", "dispatch it on the most capable available model", "use the cheapest tier", "use the strongest model opus", and any similar guidance that asks you to pick a model by name. That guidance is written for other IDEs and is WRONG on Trae.
- If you ever see a 4023 error after a subagent dispatch, the root cause is that you (or a previous turn) passed a model parameter. Recover by immediately retrying the SAME dispatch WITHOUT any model parameter — do not click "Diagnose" or switch topic.
- Dispatch = call the general-purpose Agent / subagent tool with subagent_type "general-purpose" (or the default when unspecified) and NO model field.
- Parallel = issue multiple Agent calls in one response, or use run_in_background for async work.
- Continue an existing subagent context = SendMessage; a new Agent call starts fresh.
- Task tracking ("create a todo" / "mark complete") = TaskCreate / TaskUpdate / TaskList / TodoWrite.
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

# resolve_src: 返回 skills 源目录(内含各 skill 子目录)。
# 测试可用 SUPERPOWERS_SKILLS_SRC 注入本地源以离线运行;
# 否则 git clone upstream 到临时目录,由调用方负责清理。
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

# copy_skills: 把源目录下所有 skill 逐个复制到目标 skills 目录,并逐条打印。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
# 用 "cp -R $src/$name $dst/"(拷进 dst 根)保持合并覆盖语义:重复安装时刷新同名内容,
# 不会像 "cp -R $src/$name $dst/$name" 那样在 dst/$name 已存在时嵌套成 dst/$name/$name。
# 单个 skill 复制失败时打印警告并跳过,不中断其余 skill(设计 §8)。
copy_skills() {
  local src="$1" dst="$2" entry name count=0
  mkdir -p "$dst"
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    if cp -R "$src/$name" "$dst/"; then
      log INFO "  + $name"
      count=$((count + 1))
    else
      log WARN "copy failed, skipped: $name"
    fi
  done
  log INFO "Copied $count skill(s) into: $dst"
}

# write_manifest: 把源目录下所有 skill 名逐行写入目标 skills 目录的 manifest。
# 仅记录实际已落入 dst 的 skill(目录存在),避免声称复制失败的 skill(设计 §8)。
# 参数: $1=源 skills 目录  $2=目标 skills 目录
write_manifest() {
  local src="$1" dst="$2" entry name
  : > "$dst/$MANIFEST"                    # 清空/新建 manifest
  for entry in "$src"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    [ -d "$dst/$name" ] || continue       # 未成功装入 dst 的 skill 不写入 manifest
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
    if grep -qF "$MARKER" "$f"; then
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
    log INFO "Installing skills into: $d"
    copy_skills "$src" "$d"
    write_manifest "$src" "$d"
  done <<EOF
$dirs
EOF

  # 自动写入 User Rules(尽力而为:写入后需重启 Trae 验收;失败可 UI 手动回退)。
  local rdir
  while IFS= read -r rdir; do
    [ -n "$rdir" ] || continue
    write_rule "$rdir"
  done <<EOF
$(detect_user_rules_dirs)
EOF

  # 若为临时 clone(非注入源),安装后清理
  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    log INFO "Cleaning up temporary clone: $(dirname "$src")"
    rm -rf "$(dirname "$src")"
  fi

  log INFO "Done. Restart Trae, then check Settings > Rules to confirm the rule appears."
  return 0
}

main "$@"

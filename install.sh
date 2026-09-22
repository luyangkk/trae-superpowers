#!/usr/bin/env bash
# install.sh — 把 upstream superpowers 的 skills 装入 Trae 全局技能目录。
# 自包含:不 source 外部文件(需兼容 curl|bash)。兼容 bash 3.2。
#
# 注意:隐藏目录名一律用八进制字节转义构造(\056="."),
# 因为部分编辑/传输环境会改写连续词元 dot-trae,
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
  local target="${SUPERPOWERS_TARGET:-}" key rest selected=0 esc
  if [ -n "$target" ]; then
    if target_root "$target" >/dev/null; then
      printf '%s\n' "$target"
      return 0
    fi
    log ERROR "invalid SUPERPOWERS_TARGET: $target (expected trae-cn or trae)"
    return 2
  fi
  if ! ( : </dev/tty ) 2>/dev/null; then
    log ERROR "no interactive terminal; set SUPERPOWERS_TARGET=trae-cn or trae."
    return 2
  fi
  exec 3<>/dev/tty
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

# agents_skills_dir: 输出外部共享 skills 目录路径;本工程只检测和复用,不写入。
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

# is_agents_skills_dir: 判断候选目录是否与外部 .agents/skills 指向同一真实路径。
# 两个目录都存在时才比较,用于防止通过 Trae 软链接间接修改外部安装。
is_agents_skills_dir() {
  local candidate="$1" agents candidate_real agents_real
  agents="$(agents_skills_dir)"
  [ -d "$candidate" ] && [ -d "$agents" ] || return 1
  candidate_real="$(cd "$candidate" 2>/dev/null && pwd -P)" || return 1
  agents_real="$(cd "$agents" 2>/dev/null && pwd -P)" || return 1
  [ "$candidate_real" = "$agents_real" ]
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

# remove_managed_skills: 按 manifest 清理本项目装入的 Trae 副本,不猜测未记录目录的归属。
# 参数: $1=目标 skills 目录。无 manifest 时不做任何处理。
remove_managed_skills() {
  local dst="$1" name count=0
  [ -f "$dst/$MANIFEST" ] || return 0
  log INFO "Removing managed duplicate skills from: $dst"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -d "$dst/$name" ]; then
      log INFO "  - $name"
      rm -rf "${dst:?}/${name:?}"
      count=$((count + 1))
    fi
  done < "$dst/$MANIFEST"
  rm -f "$dst/$MANIFEST"
  log INFO "Removed $count managed duplicate skill(s) and manifest from: $dst"
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
  local target d rdir
  target="$(select_target)" || return $?
  d="$(target_skills_dir "$target")"
  rdir="$(target_rules_dir "$target")"
  log INFO "Selected target: $d"

  local agents_state agents_dir
  agents_dir="$(agents_skills_dir)"
  agents_superpowers_state
  agents_state=$?
  if [ "$agents_state" -eq 0 ]; then
    log INFO "Using existing Superpowers skills from: $agents_dir"
    log INFO "The external .agents installation will not be modified."
    if is_agents_skills_dir "$d"; then
      log INFO "Skipping managed-copy cleanup through .agents alias: $d"
    else
      remove_managed_skills "$d"
    fi
    write_rule "$rdir"
    log INFO "Done. Reusing external Superpowers skills; restart Trae and confirm the rule appears."
    return 0
  fi
  if [ "$agents_state" -eq 2 ]; then
    log WARN "Incomplete Superpowers installation found at $agents_dir; leaving it unchanged."
    log INFO "Installing a complete copy into Trae's skills directory."
  fi
  if is_agents_skills_dir "$d"; then
    log ERROR "refusing to install through Trae path that resolves to external .agents/skills: $d"
    return 5
  fi

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

  log INFO "Installing skills into: $d"
  copy_skills "$src" "$d"
  write_manifest "$src" "$d"

  # 自动写入 User Rules(尽力而为:写入后需重启 Trae 验收;失败可 UI 手动回退)。
  write_rule "$rdir"

  # 若为临时 clone(非注入源),安装后清理
  if [ -z "${SUPERPOWERS_SKILLS_SRC:-}" ]; then
    log INFO "Cleaning up temporary clone: $(dirname "$src")"
    rm -rf "$(dirname "$src")"
  fi

  log INFO "Done. Restart Trae, then check Settings > Rules to confirm the rule appears."
  return 0
}

main "$@"

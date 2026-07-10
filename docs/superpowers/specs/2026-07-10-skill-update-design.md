# Trae Superpowers 更新能力 — 设计文档

- 日期:2026-07-10
- 状态:已通过 brainstorming 评审,待用户确认后进入 writing-plans
- 关联:在 [2026-07-10-trae-superpowers-design.md](./2026-07-10-trae-superpowers-design.md) 基础上新增"更新 skill"能力

## 1. 目标

为 `trae-superpowers` 新增"更新已安装 skill"的能力,使用户能把本工程装入的 upstream
skills 同步到上游最新状态,并**精确镜像**上游:既覆盖同名 skill 的内容,也移除上游已
删除/改名的孤儿 skill 及 skill 目录内被上游删掉的文件——同时绝不触碰用户自有或其它
来源的 skill(如 `lark-*` / `bits-*` / `vercel-*`)。

## 2. 背景:为什么需要 manifest

Trae 的全局技能目录(如 `~/.trae-cn/skills/`)是**多来源共享**的,并非本工程专属。
本机实测该目录含 49 个 skill,其中大量来自 Trae 内置、飞书插件(`lark-*`)、字节内部
工具(`bits-*`)等,真正来自 upstream superpowers 的只是其中一小部分。

因此"精确镜像更新"若采用"全目录对齐",会误删 `lark-*` / `bits-*` 等**用户自有 skill**,
后果灾难性。必须有一份 **manifest 清单**记录"本工程装入了哪些 skill",孤儿删除只在
manifest 记录范围内进行。

这也顺带修复现有 [uninstall.sh](../../../uninstall.sh) 的一个盲区:它靠"当前上游清单"
反推删除,一旦上游删掉某 skill,该 skill 不在当前清单里,卸载就会漏删它。

## 3. 已确认的关键决策

| # | 决策点 | 结论 |
|---|--------|------|
| 1 | 更新一致性保证 | **精确镜像**:覆盖同名内容 + 删除上游已移除的孤儿 skill + 删除 skill 内被上游删的文件 |
| 2 | 来源区分机制 | 写 **manifest 文件**记录本工程装入的 skill;孤儿删除仅限 manifest 范围 |
| 3 | 更新入口 | 新增独立 `update.sh`,`curl \| bash` 一行流,与 install/uninstall 并列 |
| 4 | manifest 格式 | **纯文本清单**,每行一个 skill 名(A1);零依赖、兼容 bash 3.2 |
| 5 | manifest 位置 | **skills 根下** `.superpowers-manifest`;在所有 skill 子目录外层,`cp -R *` / `rm -rf <skill>` 都碰不到它,独立于任何单个 skill 的存亡 |
| 6 | 单 skill 镜像策略 | **逐 skill 清替**(B1):`rm -rf "$dst/<name>" && cp -R "$src/<name>" "$dst/<name>"`;不引入 rsync 依赖 |
| 7 | install 复制策略 | **保持 `cp -R` 覆盖**,不升级为清替;install 只多加"写 manifest"一步。职责:install=铺开,update=对齐 |

## 4. Manifest 文件规范

- 路径:每个命中的变体 skills 目录下一份,如 `~/.trae-cn/skills/.superpowers-manifest`
- 格式:纯文本,每行一个 skill 名(无元数据,YAGNI),示例:

```
brainstorming
systematic-debugging
using-superpowers
writing-plans
```

- 点开头:双保险——Trae 只按"含 `SKILL.md` 的子目录"识别 skill,manifest 是文件不是
  目录,天然不会被误识别;点开头额外隐藏。
- 写入时机:install 与 update 在完成复制后覆盖写入(名单 = 当次上游 skill 全集)。
- 容错:读取时跳过空行与首尾空白(`[ -n "$name" ] || continue`)。
- 用户篡改(如手填 `lark-im`)属自伤场景,**不做防御**(YAGNI);文档注明"请勿手动编辑"。

## 5. 三脚本职责与共享逻辑

三个脚本各自**自包含**(不 source 外部文件,需兼容 `curl | bash`),各内联一份共享函数:
`variant_roots` / `detect_skill_dirs` / `resolve_src`(与现有脚本一致,含 `pwd -P` 软链接去重)。

| 脚本 | 职责 |
|------|------|
| `install.sh` | 复制 skills(`cp -R` 覆盖)→ **新增:写 manifest** |
| `update.sh`(新增) | 读旧 manifest → 精确镜像同步 → 写新 manifest |
| `uninstall.sh` | **优先按 manifest** 逐名删除 + 删 manifest;manifest 缺失时**回退**到现有"按上游清单反推"逻辑 |

## 6. update.sh 核心数据流

对**每个命中的变体 skills 目录** `$dst` 执行:

```
1. 探测变体 skills 目录(复用 detect_skill_dirs)
2. 获取新上游 skills 源(复用 resolve_src:注入源或临时 clone)
3. 读旧 manifest → OLD 集合(本工程上次装的 skill 名单;文件不存在则 OLD=空集)
4. 扫描新源目录 → NEW 集合(上游当前 skill 名单)
5. 计算孤儿 = OLD 中存在、但 NEW 中已消失的 skill
     → 逐个 rm -rf "$dst/<orphan>"(只删 manifest 记过的,绝不碰用户 skill)
6. 对 NEW 中每个 skill 逐 skill 清替(B1):
     rm -rf "$dst/<name>" && cp -R "$src/<name>" "$dst/<name>"
     → skill 内被上游删的文件随之消失,实现目录级镜像
7. 写新 manifest = NEW 集合(覆盖旧 manifest)
8. 清理临时 clone(非注入源时)
```

关键点:

- 孤儿删除严格限定 `OLD ∩ (¬NEW)`;用户自有 skill 从不进 manifest → 永不被删。
- manifest 缺失(老用户首次 update):OLD=空集 → 不删任何孤儿,只做全量镜像 + 补写 manifest。安全降级。
- 删除前打印"将更新的 skill / 将删除的孤儿"清单(遵循项目约定)。

## 7. install.sh / uninstall.sh 联动改动

### install.sh

- 保持现有 `copy_skills`(`cp -R "$src"/* "$dst"/`)不变。
- 新增:复制完成后,扫描 `$src` 下所有 skill 名,逐行写入 `$dst/.superpowers-manifest`。

### uninstall.sh

```
1. 探测变体 skills 目录
2. 若 "$dst/.superpowers-manifest" 存在:
     读 manifest → 逐名删除 "$dst/<name>";删除 manifest 文件本身
     (此路径离线可用,无需 clone 上游)
3. 若 manifest 不存在(老用户/手动安装):
     回退现有逻辑(resolve_src 拿上游清单反推删除)
```

- manifest 存在的路径不再依赖 `resolve_src` / `git clone`(离线可卸载、省一次 clone)。
- 为兼容回退分支,`resolve_src` 仍保留。

## 8. 错误处理与边界

退出码沿用现约定:3 = 未检测到 Trae 变体;4 = 无法获取 skills 源。

| 情形 | 处理 | 退出码 |
|------|------|--------|
| 未检测到任何 Trae 变体 | 打印错误退出 | 3 |
| `resolve_src` 失败(clone 失败/注入源不存在) | 清理临时目录后退出 | 4 |
| 某变体 manifest 不存在 | OLD=空集,不删孤儿,全量镜像 + 补写 manifest | 继续 |
| manifest 含空行/首尾空白 | 读取时跳过,容错 | 继续 |
| 孤儿 `rm -rf` 目标不存在 | `rm -rf` 幂等,无副作用 | 继续 |
| 逐 skill 清替 `rm` 后 `cp` 失败 | 打印警告,继续其它变体,不整体中断 | 继续 |

贯穿三脚本的安全护栏:

1. **孤儿删除只在 manifest 范围内**(`OLD ∩ ¬NEW`)——最重要的护栏,用户自有 skill 永不入 manifest。
2. manifest 名单只可能是 upstream 曾提供的名字,不会误伤同名用户 skill(撞名为极端场景,与现有 uninstall 行为一致,接受此风险)。
3. 删除前打印清单(项目约定)。
4. 临时 clone 在正常与异常路径均清理(沿用现有脚本的显式 `rm -rf` 模式)。
5. 软链接去重:`detect_skill_dirs` 用 `pwd -P` 去重,互为别名的变体只同步一次、manifest 只写一次。

## 9. 测试策略

沿用现有框架([test_helpers.bash](../../../tests/test_helpers.bash):隔离 HOME + 假源 + 断言,兼容 bash 3.2,离线)。

**新增 helper**(加到 test_helpers.bash):

- `assert_file_exists` / `assert_file_absent`:断言 manifest 文件在/不在。
- `assert_file_contains`:断言 manifest 含某 skill 名(`grep -qx`)。

**新增 tests/test_update.sh**:

| 用例 | 场景 | 断言 |
|------|------|------|
| 无变体 | HOME 无任何变体 | 退出码 3 |
| 基本更新 | 旧源装 A,B → 新源 A,B,C | A/B/C 都在;manifest 含 A/B/C |
| 删孤儿 | 旧 manifest 有 A,B → 新源只有 A | B 被删;A 保留;manifest 只剩 A |
| 不误伤用户 skill | 目录含 my-own + manifest 只记 A;新源只有 A | my-own 保留;manifest 无 my-own |
| skill 内文件镜像(B1) | 旧 A 有 old.md;新 A 无 old.md 有 new.md | old.md 消失、new.md 存在 |
| manifest 缺失降级 | 无 manifest → update | 不删任何东西;全量镜像;补写 manifest |

**扩充 test_install.sh**:install 后断言 `.superpowers-manifest` 生成且含装入的 skill 名。

**扩充 test_uninstall.sh**:

- manifest 存在 → 按 manifest 删除 + manifest 被删;用户 skill 保留。
- manifest 不存在 → 回退旧逻辑仍能删(保留现有用例,验证向后兼容)。

**注册进 run_all.sh**:把 `test_update.sh` 加入循环。

## 10. 文档改动

### README.md / README.zh-CN.md(结构保持一致)

1. 新增 **Update / 更新** 章节:`curl -fsSL <raw>/update.sh | bash`;说明"精确镜像:
   更新内容 + 移除上游已删的 skill,不动你自己的 skill"。
2. **How it works / 工作原理**:补一句 manifest 机制(记录本工程装入的 skill,供更新/
   卸载精确定位,请勿手动编辑)。
3. Uninstall 章节:说明现在优先按 manifest 卸载,离线可用。

### CLAUDE.md

- 常用命令补 `bash tests/test_update.sh`。
- 架构与关键文件补 `update.sh` 及其核心逻辑、manifest 约定。

## 11. 非目标(YAGNI)

- manifest 不记版本号/时间戳等元数据(纯 skill 名清单即可)。
- 不做 manifest 篡改防御。
- 不引入 rsync / jq 等外部依赖(保持单一 bash 脚本、自包含、兼容 bash 3.2)。
- install 复制不升级为逐 skill 清替(精确镜像是 update 的职责)。
- 不自动检测"上游是否有更新"(用户主动跑 update 即可)。

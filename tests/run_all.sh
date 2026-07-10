#!/usr/bin/env bash
# 运行全部 shell 测试,任一失败则整体失败。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$HERE"/test_install.sh "$HERE"/test_update.sh "$HERE"/test_uninstall.sh; do
  printf '\n=== Running %s ===\n' "$(basename "$t")"
  bash "$t" || rc=1
done
exit "$rc"

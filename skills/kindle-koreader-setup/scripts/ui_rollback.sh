#!/bin/bash
# 把 ui_install.sh 覆盖前的备份还原回 Kindle：frontend / plugins / resources 精确还原（会删掉界面新增的文件），
# defaults.lua、reader.lua 原样拷回。书、设置、阅读进度都不在这些目录里，不受影响。
# 用法：ui_rollback.sh <Kindle 挂载路径> <备份目录，例如 ~/kindle-koreader-backups/ui-before-20261126-203000>
# okooo5km(十里)
set -euo pipefail

K="${1:?用法：ui_rollback.sh <Kindle 挂载路径> <备份目录>}"
B="${2:?缺少备份目录}"
export COPYFILE_DISABLE=1

[ -d "$K/koreader" ] || { echo "$K/koreader 不存在"; exit 1; }
[ -d "$B/koreader/frontend" ] || { echo "$B 不是 ui_install.sh 生成的备份（缺 koreader/frontend）"; exit 1; }

for part in frontend plugins resources; do
  [ -d "$B/koreader/$part" ] && rsync -a --delete "$B/koreader/$part/" "$K/koreader/$part/"
done
for f in defaults.lua reader.lua; do
  [ -f "$B/koreader/$f" ] && cp "$B/koreader/$f" "$K/koreader/$f"
done
command -v dot_clean >/dev/null && dot_clean -m "$K" || true
sync
diff -rq "$B/koreader/frontend" "$K/koreader/frontend" >/dev/null && echo "==> 已还原到 $B 的状态" || { echo "还原后仍有差异，请检查"; exit 1; }
echo "下一步：弹出并拔线，再启动 KOReader。"

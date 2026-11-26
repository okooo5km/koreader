#!/bin/bash
# 把本仓库的界面覆盖到 Kindle 上已装好的 KOReader v2026.07.1。
# 用法：ui_install.sh <Kindle 挂载路径> [--source <覆盖包.zip | 仓库目录>]
#   不给 --source：先找本仓库 GitHub Release 里的 Kindle 覆盖包，没有就浅克隆仓库现场组装。
#   环境变量 KOREADER_UI_REPO（默认 okooo5km/koreader）、KOREADER_UI_REF（克隆用的分支，默认 eink-ui）。
# 覆盖前把 koreader/ 里会被改到的部分备份到 ~/kindle-koreader-backups/ui-before-<时间>/，回退用 ui_rollback.sh。
# 不带 --delete：Kindle 版 KOReader 自带的插件（SSH 等）保留。
# okooo5km(十里)
set -euo pipefail

VER=v2026.07.1
REPO="${KOREADER_UI_REPO:-okooo5km/koreader}"
REF="${KOREADER_UI_REF:-eink-ui}"
K="${1:?用法：ui_install.sh <Kindle 挂载路径> [--source <zip|dir>]}"
SRC=""
[ "${2:-}" = "--source" ] && SRC="${3:?--source 后面要给 zip 或目录}"
export COPYFILE_DISABLE=1

[ -d "$K/koreader" ] || { echo "$K/koreader 不存在：先装 KOReader $VER（koreader_install.sh）"; exit 1; }
rev="$(cat "$K/koreader/git-rev" 2>/dev/null || true)"
case "$rev" in
  "$VER"*) ;;
  *) echo "Kindle 上的 KOReader 版本是「${rev:-未知}」，本界面只适配 $VER。先用 koreader_install.sh --force 装 $VER。"; exit 1 ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kindle-ui.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OV="$WORK/overlay/koreader"

assemble_from_repo() {  # $1 = 仓库目录：按仓库自己的排除清单组装（不带微信读书集成）
  local R="$1"
  [ -f "$R/reader.lua" ] && [ -d "$R/frontend" ] || { echo "$R 不是本仓库的检出"; exit 1; }
  local ex="$WORK/excludes.txt"
  if [ -f "$R/ireader/check_share.py" ]; then
    python3 -I - "$R/ireader/check_share.py" > "$ex" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for node in tree.body:
    if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") in ("EXCLUDED", "EXCLUDED_DIRS"):
        for v in ast.literal_eval(node.value):
            print(v)
PY
  else
    : > "$ex"
  fi
  mkdir -p "$OV"
  for part in frontend plugins resources; do
    rsync -a --exclude '.git' "$R/$part/" "$OV/$part/"
  done
  cp "$R/defaults.lua" "$R/reader.lua" "$OV/"
  while IFS= read -r rel; do
    [ -n "$rel" ] && rm -rf "${OV:?}/$rel"
  done < "$ex"
}

if [ -n "$SRC" ] && [ -f "$SRC" ]; then
  echo "==> 用覆盖包 $SRC"
  unzip -q "$SRC" -d "$WORK/overlay"
elif [ -n "$SRC" ] && [ -d "$SRC" ]; then
  echo "==> 用仓库目录 $SRC 组装"
  assemble_from_repo "$SRC"
else
  asset_url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for a in d.get('assets', []):
    n=a.get('name','')
    if n.startswith('koreader-kindle-overlay-$VER') and n.endswith('.zip'):
        print(a['browser_download_url']); break
" || true)"
  if [ -n "$asset_url" ]; then
    echo "==> 下载 Release 覆盖包 $asset_url"
    curl -fL --retry 3 -o "$WORK/overlay.zip" "$asset_url"
    unzip -q "$WORK/overlay.zip" -d "$WORK/overlay"
  else
    echo "==> 没有可用的 Release 覆盖包，浅克隆 $REPO@$REF 组装"
    git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$WORK/repo" || {
      echo "克隆失败：$REPO 上没有分支 $REF，或网络不通。可以用 --source 指定下载好的覆盖包或仓库目录。"; exit 1; }
    assemble_from_repo "$WORK/repo"
  fi
fi
[ -f "$OV/reader.lua" ] && [ -d "$OV/frontend" ] || { echo "覆盖内容不完整（缺 koreader/reader.lua 或 frontend/）"; exit 1; }
if find "$OV" -name 'wereader*' -o -name 'gohomeflag*' | grep -q .; then
  echo "覆盖内容里有微信读书集成文件，这不是给分享用的版本，停止"; exit 1
fi

B="$HOME/kindle-koreader-backups/ui-before-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$B/koreader"
echo "==> 备份到 $B"
for part in frontend plugins resources; do
  [ -d "$K/koreader/$part" ] && rsync -a "$K/koreader/$part/" "$B/koreader/$part/"
done
for f in defaults.lua reader.lua; do
  [ -f "$K/koreader/$f" ] && cp "$K/koreader/$f" "$B/koreader/$f"
done

echo "==> 覆盖到 $K/koreader"
for part in frontend plugins resources; do
  rsync -a "$OV/$part/" "$K/koreader/$part/"
done
cp "$OV/defaults.lua" "$OV/reader.lua" "$K/koreader/"
command -v dot_clean >/dev/null && dot_clean -m "$K" || true
find "$K/koreader" -name '._*' -delete 2>/dev/null || true
sync

# 逐个比对：Kindle 上多出来的文件（原有插件等）不算差异
diffs=""
for part in frontend plugins resources; do
  diffs="$diffs$(diff -rq "$OV/$part" "$K/koreader/$part" 2>&1 | grep -v "^Only in $K" || true)"
done
cmp -s "$OV/reader.lua" "$K/koreader/reader.lua" || diffs="$diffs reader.lua 不一致"
if [ -n "$diffs" ]; then
  echo "警告：Kindle 上的文件和覆盖内容不一致，可能拷贝没完成："
  echo "$diffs" | head -20
  exit 1
fi
echo "==> 完成，文件已逐个比对一致"
echo "回退：bash $(cd "$(dirname "$0")" && pwd)/ui_rollback.sh \"$K\" \"$B\""
echo "下一步：弹出并拔线，再从启动入口打开 KOReader。"

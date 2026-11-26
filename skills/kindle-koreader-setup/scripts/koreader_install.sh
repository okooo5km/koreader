#!/bin/bash
# 下载并安装官方 KOReader v2026.07.1 的 Kindle 包到 U 盘模式挂载的 Kindle。
# 用法：koreader_install.sh <Kindle 挂载路径> <kindlehf|kindlepw2|kindle|kindle-legacy> [--force]
#   已装了 KOReader 时默认停下；--force 会先把旧的 koreader/ 备份到电脑再覆盖（settings、历史等一并备份）。
# 下载缓存：~/.cache/kindle-koreader-setup/
# okooo5km(十里)
set -euo pipefail

VER=v2026.07.1
K="${1:?用法：koreader_install.sh <Kindle 挂载路径> <包名> [--force]}"
PKG="${2:?缺少包名：kindlehf / kindlepw2 / kindle / kindle-legacy}"
FORCE="${3:-}"
export COPYFILE_DISABLE=1

case "$PKG" in kindlehf|kindlepw2|kindle|kindle-legacy) ;; *) echo "包名不对：$PKG"; exit 64 ;; esac
[ -d "$K/documents" ] && [ -d "$K/system" ] || { echo "$K 看起来不是 Kindle 的 USB 根目录"; exit 1; }

NAME="koreader-$PKG-$VER.zip"
URL="https://github.com/koreader/koreader/releases/download/$VER/$NAME"
CACHE="$HOME/.cache/kindle-koreader-setup"
mkdir -p "$CACHE"

# 官方 release 的资产大小，用来核对下载完整
api="https://api.github.com/repos/koreader/koreader/releases/tags/$VER"
want_size="$(curl -fsSL "$api" | python3 -c "import json,sys;d=json.load(sys.stdin);print(next(a['size'] for a in d['assets'] if a['name']=='$NAME'))")"
[ -n "$want_size" ] || { echo "在官方 release 里找不到 $NAME"; exit 1; }

zip="$CACHE/$NAME"
if [ ! -f "$zip" ] || [ "$(wc -c < "$zip" | tr -d ' ')" != "$want_size" ]; then
  echo "==> 下载 $URL"
  curl -fL --retry 3 -o "$zip.part" "$URL"
  mv "$zip.part" "$zip"
fi
got="$(wc -c < "$zip" | tr -d ' ')"
[ "$got" = "$want_size" ] || { echo "下载不完整：$got / $want_size 字节"; rm -f "$zip"; exit 1; }
unzip -tq "$zip" >/dev/null || { echo "zip 校验失败"; rm -f "$zip"; exit 1; }
echo "==> 包已就绪（$got 字节）"

if [ -d "$K/koreader" ]; then
  if [ "$FORCE" != "--force" ]; then
    echo "Kindle 上已有 koreader/（版本 $(cat "$K/koreader/git-rev" 2>/dev/null || echo 未知)）。要覆盖请加 --force，会先备份。"
    exit 2
  fi
  B="$HOME/kindle-koreader-backups/koreader-before-install-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$B"
  echo "==> 备份旧的 koreader/ 到 $B"
  rsync -a --exclude 'cache/' "$K/koreader/" "$B/koreader/"
fi

echo "==> 解压到 $K"
unzip -oq "$zip" -d "$K"
rm -rf "${K:?}/__MACOSX"
command -v dot_clean >/dev/null && dot_clean -m "$K" || true
find "$K" -maxdepth 3 -name '._*' -delete 2>/dev/null || true
sync

rev="$(cat "$K/koreader/git-rev" 2>/dev/null || true)"
echo "==> 完成：koreader/git-rev = ${rev:-未知}"
echo "下一步：弹出 Kindle，按越狱类型对应的方式启动 KOReader（见 references/after-jailbreak.md），能进文件浏览器后正常退出。"

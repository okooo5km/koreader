#!/bin/bash
# 找到以 U 盘模式挂载的 Kindle，报告：挂载路径、剩余空间、越狱痕迹、已装的 KOReader 版本。
# 找不到时提示：可能没插好、没解锁，或者是 MTP 机型（不会出现挂载路径）。
# 用法：kindle_find.sh            自动找
#       kindle_find.sh <挂载路径>  只检查这个路径
# 支持 macOS 和 Linux。Windows 请在资源管理器里看盘符，手动检查同样的目录。
# okooo5km(十里)
set -u

candidates=()
if [ $# -ge 1 ]; then
  candidates=("$1")
else
  for d in /Volumes/* /media/"${USER:-}"/* /run/media/"${USER:-}"/* /media/*; do
    [ -d "$d" ] && candidates+=("$d")
  done
fi

found=0
for d in "${candidates[@]}"; do
  # Kindle 的 USB 根目录固定有 documents/ 和 system/
  [ -d "$d/documents" ] && [ -d "$d/system" ] || continue
  found=1
  echo "== Kindle：$d"
  df -h "$d" 2>/dev/null | awk 'NR==2 {print "   容量 " $2 "，已用 " $3 "，剩余 " $4}'

  marks=()
  [ -d "$d/extensions" ] && marks+=("extensions/（KUAL 扩展目录）")
  [ -d "$d/mrpackages" ] && marks+=("mrpackages/（MRPI）")
  ls "$d"/documents/KUAL* >/dev/null 2>&1 && marks+=("documents/KUAL*（KUAL）")
  ls "$d"/documents/*.sh >/dev/null 2>&1 && marks+=("documents/*.sh（scriptlet）")
  [ -d "$d/fill_disk" ] && marks+=("fill_disk/（防更新填充文件）")
  if ls "$d"/update*.bin >/dev/null 2>&1 || [ -e "$d/update.bin.tmp.partial" ]; then
    marks+=("根目录有 update*.bin 或 update.bin.tmp.partial（越狱前要删；旧式越狱用作防更新的同名文件夹除外）")
  fi
  if [ ${#marks[@]} -gt 0 ]; then
    echo "   发现："; for m in "${marks[@]}"; do echo "     - $m"; done
  else
    echo "   没发现越狱相关文件（可能还没越狱，或新式越狱的文件不在 USB 可见区域）"
  fi

  if [ -d "$d/koreader" ]; then
    rev="$(cat "$d/koreader/git-rev" 2>/dev/null || true)"
    echo "   KOReader：已安装，版本 ${rev:-未知（没有 git-rev 文件）}"
    case "$rev" in
      v2026.07.1*) echo "   版本符合本界面要求（v2026.07.1）" ;;
      "") ;;
      *) echo "   注意：本界面只适配 v2026.07.1，现在的版本是 $rev" ;;
    esac
    [ -f "$d/koreader/crash.log" ] && echo "   crash.log：$(wc -l < "$d/koreader/crash.log" | tr -d ' ') 行，最后一行：$(tail -n 1 "$d/koreader/crash.log" | cut -c1-120)"
  else
    echo "   KOReader：未安装"
  fi
done

if [ $found -eq 0 ]; then
  echo "没找到以 U 盘模式挂载的 Kindle。"
  echo "  - 确认数据线能传数据、Kindle 已解锁，并且屏幕显示「USB 驱动器模式」之类的提示。"
  echo "  - KOReader 运行时 Kindle 进不了 U 盘模式，先在 KOReader 里退出。"
  echo "  - 2024 年以后的机型和 Scribe 多半走 MTP，不会出现挂载路径：macOS 用 OpenMTP 或 Amazon 的 USB File Manager，Linux 用 gvfs-mtp，Windows 直接在资源管理器里操作。"
  exit 1
fi

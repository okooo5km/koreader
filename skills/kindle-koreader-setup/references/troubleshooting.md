# 常见问题与恢复

## 电脑看不到 Kindle

- 先在 KOReader 里退出，再插线（KOReader 运行时进不了 U 盘模式）。
- 换一根能传数据的线；Kindle 要解锁。
- 2024 年以后的机型和 Scribe 多半走 **MTP**，不会出现 U 盘：
  - macOS：OpenMTP（开源）或 Amazon「Send to Kindle」应用里的 USB File Manager。同一时间只能有一个程序占用 MTP 设备，先关掉别的。
  - Linux：gvfs-mtp（文件管理器里会出现设备）。
  - Windows：资源管理器里直接操作。
  - MTP 机型没法跑本 skill 的 rsync 脚本：用上面的工具手动拷，拷完逐个核对文件大小。
- 反复插拔 USB 之后，Kindle 上的启动器可能打不开，重启 Kindle 即可。

## macOS 的 `._` 文件

macOS 往 FAT 卷拷文件会生成 `._文件名` 的资源叉文件，Kindle 上会变成一堆无效文件，偶尔干扰程序。

- 拷贝前 `export COPYFILE_DISABLE=1`，用 `rsync` 而不是 Finder 拖拽。
- 拷完执行 `dot_clean -m <挂载路径>`。
- 这是经验做法，wiki 没有专门写。

## 越狱失败

| 现象 | 处理 |
|---|---|
| 越狱前固件被自动升级了 | 重新跑 `jb_lookup.py` 查新固件有没有方法；没有就等，保持飞行模式和满存储 |
| SpiderCat 末行 `abort:no-firm` | 机型或固件不支持，换方法 |
| Véra / SpiderCat 中途卡住 | 是否断了 Wi-Fi；按页面说明重来 |
| Shadow 提示 "did not get a clean address leak" | 直接重试 |
| WinterBreak 商店里 "Unexpected error" | 按方法页的 LocalStorage Replacement 清 `.active_content_sandbox` 缓存 |
| SpringBreak 后开机特别慢 | 漏了清理步骤，再运行一次程序清理 |

## KOReader 打不开

1. 看 `koreader/crash.log` 的最后几行。
2. 没有新的 `launching...` 行：KOReader 根本没被拉起，不是代码问题。拔线，重启 Kindle，再从启动入口打开。
3. 有报错：
   - 包装错了。固件 ≥ 5.16.3 要 `kindlehf`，更低的触屏机型要 `kindlepw2`。删掉整个 `koreader/` 后用 `koreader_install.sh` 重装对的包。
   - 越狱其实没生效（crash.log 里有 framebuffer 之类的错误）：重新确认越狱状态。
   - 覆盖界面后才出问题：先用 `ui_rollback.sh` 回到原版 KOReader，确认原版能跑，再排查。
4. 中文显示成方块：缺中文字体，往 `koreader/fonts/` 放一个中文字体（比如霞鹜文楷）。

## Kindle 本身出问题

- **启动循环 / 卡死**：固件 ≥ 5.16.3 且装了 Jobman 恢复模式的，可以在启动后 10 秒内点屏幕进恢复模式，或在 USB 根目录建一个空文件 `JOBMAN_RECOVERY`。https://kindlemodding.org/jailbreaking/faq/kindle-recovery.html
- **恢复出厂后卡在 Update Failed**：从 wiki 的固件下载表找到机型对应的官方 `.bin`，放到 USB 根目录，弹出后重启让它安装。之后设备回到未越狱状态。https://kindlemodding.org/jailbreaking/faq/recovering-from-a-reset.html
- **重置之前**：屏蔽了 OTA 的越狱机，要先用 Jobman 的「Enable OTA Updates」（或旧式的 renameotabin Restore）恢复更新，否则重置后装不上官方更新。

## 卸载越狱、回到原厂

1. 恢复 OTA（同上）。
2. 安装一个与当前版本相同或更高的官方固件。
3. 恢复出厂设置。

https://kindlemodding.org/jailbreaking/faq/unjailbreaking.html

只想去掉本界面、保留 KOReader：`scripts/ui_rollback.sh <挂载路径> <备份目录>`。

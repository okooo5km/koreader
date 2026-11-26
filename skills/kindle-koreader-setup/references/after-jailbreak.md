# 越狱之后：收尾、防更新、启动 KOReader

先判断越狱属于哪一类，两类的做法完全不同。

## 新式越狱（wiki 称 hdnext）

适用：Véra、Shadow、SpiderCat、SpringBreak、Sanctuary、AdBreak、Nosebleed，以及 2026-06 以后的 WinterBreak。

1. 重启 Kindle，临时打开 Wi-Fi。
2. 首页搜索栏输入 `;kpm update` 回车，再 `;kpm install jobman`（越狱管理器：管更新屏蔽、恢复模式、SSH 等）。Jobman 不支持固件 5.16.3 以下的设备。
3. **KUAL 在新式越狱下已经不能用，不要装。** 第三方程序以「书」的形式出现在首页，点一下运行。
4. 更新屏蔽由越狱自动打开，Jobman 里有「Enable OTA Updates」开关。确认屏蔽生效后，可以删掉越狱前填充存储用的文件（wiki 写的是 `fill_disk` 目录）。
5. **KOReader 不要用 `;kpm install koreader`**：KPM 仓库里的版本不受控，本界面要求 v2026.07.1。用 `scripts/koreader_install.sh` 手动装，再按 KOReader 官方 wiki 的「手动拷贝 + scriptlet」方式，把 KOReader 启动脚本（`.sh`）放进 `documents/`，它会作为一本书出现在首页。启动脚本的下载地址和文件名以 https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices 当下写的为准。

参考：https://kindlemodding.org/jailbreaking/whats-next/ 、https://kindlemodding.org/jailbreaking/whats-next/jailbreaking-manager/

## 旧式越狱（Legacy / hotfix 体系）

适用：WinterBreak2、2026-06 以前的 WinterBreak、LanguageBreak 等 Legacy 方法。

1. **Hotfix**：让越狱在官方更新后还能保留。装 `Update_hotfix_universal.bin`（「设置 → 更新您的 Kindle」），书库里会出现「Run Hotfix」。**每次系统更新后都要再运行一次 Run Hotfix。** WinterBreak、SpringBreak、Sanctuary 已自带，可跳过。之前用 renameotabin 屏蔽过更新的，要先 Restore 再装 Hotfix。
   https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/setting-up-a-hotfix/
2. **KUAL + MRPI**：KUAL 用 PEKI 版（`KUAL.sh`、`KUAL.jar` 放进 `documents/`），MRPI 的 `extensions/`、`mrpackages/` 拷到根目录。预留约 220 MB 空间，不够会装不上。
   https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/installing-kual-mrpi/
3. **关闭 OTA**：固件 5.11 以下在根目录建一个名为 `update.bin.tmp.partial` 的**文件夹**；5.11 及以上用 KUAL 里的 renameotabin 扩展点 Rename。
   https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/disable-ota.html
4. **启动 KOReader**：
   - 固件 < 5.16.3：KUAL → KOReader → Start KOReader（用 `kindlepw2` 包）。
   - 固件 ≥ 5.16.3：用 KUALA（`kindlehf` 包）。
   - 「Start KOReader (no framework)」会先释放内存，退出更慢，一般不用。

实例：Kindle Voyage 5.13.6 → WinterBreak2 → Hotfix → KUAL(PEKI) + MRPI(khf) → KOReader `kindlepw2`，实测可用（2026-11-16）。

## 不管哪一类

- 平时保持飞行模式，只在要下载东西时打开 Wi-Fi。
- KOReader 运行时 Kindle 进不了 U 盘模式；在 KOReader 里点退出再插线。
- KOReader 退出时会把内存里的设置写回文件。改它的配置文件之前一定先退出，否则改了也会被覆盖。
- 本界面的 KOReader 里去掉了「在线更新」菜单，避免一键升级把界面覆盖掉。要升级 KOReader，等本仓库发布对应版本的界面后再一起升。

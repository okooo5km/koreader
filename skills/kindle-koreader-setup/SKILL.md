---
name: kindle-koreader-setup
description: 在用户的 Kindle 上装好 KOReader 和本仓库的中文界面，按需从零开始：识别机型与固件、按 Kindle Modding Wiki 的实时数据选越狱方法并指导越狱、防自动更新、安装 KOReader v2026.07.1、覆盖界面、回退。适用于 KOReader 支持的所有可越狱 Kindle（Paperwhite、Oasis、Voyage、入门款、Scribe、Colorsoft 等）。用户说「帮我在这个 Kindle 上连接并安装 KOReader」「给我的 Kindle 装 KOReader」「把这套界面装到 Kindle 上」「帮我越狱 Kindle」「Kindle 从零配置」时使用。不用于安卓电纸书、Kobo，也不用于盗版或去 DRM。
---

# Kindle 从零配置：越狱 → KOReader → 界面

这份 skill 让你（AI）陪用户把一台 Kindle 从原厂状态配到「KOReader v2026.07.1 + 本仓库的界面」。大部分步骤要用户在 Kindle 上亲手点，你负责：判断方法、准备文件、在电脑上执行拷贝和校验、每一步告诉用户该看到什么。

本仓库：https://github.com/okooo5km/koreader （KOReader 的修改版，AGPL-3.0）。界面只改了 Lua，必须配 **KOReader v2026.07.1** 的官方二进制，版本不对会直接崩。

## 先看设备处在哪一步（每次都从这里开始）

用户通常只会说一句「帮我在这个 Kindle 上连接并安装 KOReader」。先别讲流程，直接：

1. 让用户用数据线把 Kindle 接到电脑、解锁屏幕；KOReader 正在运行的话先在里面退出。
2. 运行 `bash scripts/kindle_find.sh`，按结果分流：
   - **已装 KOReader 且版本是 v2026.07.1**：直接到阶段 6 覆盖界面。
   - **已装 KOReader 但版本不对**：到阶段 5 用 `--force` 重装 v2026.07.1（书、设置、阅读进度都在 `koreader/` 的设置文件里，脚本会先整体备份，重装不会动它们），再到阶段 6。
   - **有越狱痕迹但没装 KOReader**：从阶段 5 开始。
   - **什么都没有（原厂状态）**：从阶段 1 开始走完整流程。
   - **找不到挂载路径**：多半是 MTP 机型（2024 年以后的多数机型和 Scribe），按 `references/troubleshooting.md` 的 MTP 一节处理，脚本里的 rsync 步骤改成用 MTP 工具手动拷。
3. 用一两句话告诉用户你看到的状态和接下来要做什么，然后开始。

越狱状态从 USB 侧不一定看得出来（新式越狱的文件不在 U 盘可见区域）。拿不准时问用户一句：Kindle 首页有没有 KOReader、Jobman、KUAL 之类的「书」或启动器。

## 铁律

1. **越狱方法以 Kindle Modding Wiki 的实时数据为准。** 越狱漏洞几个月就换一批，`references/jailbreak-methods.md` 只是 2026-11-26 的快照。先跑 `scripts/jb_lookup.py`（它读 wiki 的 `models.json` / `jailbreaks.json`），再打开它给出的方法页，按页面当下写的步骤来。页面和快照冲突时听页面的。
2. **防自动更新放在第一位。** 用户的 Kindle 一旦自动升到没有越狱的固件，就只能等，且不能降级。没确认防更新措施到位前，别让用户连 Wi-Fi、别打开商店。
3. **只从官方来源下载**：越狱文件只来自 wiki 方法页里写的链接；KOReader 只来自 `github.com/koreader/koreader/releases`；界面只来自本仓库。不要从论坛网盘、第三方镜像下东西。
4. **越狱程序由用户自己运行。** 需要 `sudo` 运行的越狱程序（例如 Shadow），把命令和来源给用户看，得到明确同意后再跑；能让用户在自己的终端里跑就让他跑。
5. **动 Kindle 上的文件之前先备份**，至少备份 `documents/` 和已有的 `koreader/`。用 `scripts/kindle_find.sh` 拿到挂载路径后再操作，不要猜路径。
6. **不帮忙去 DRM、不帮忙获取盗版书。** 越狱只是为了装 KOReader 读自己的文件。
7. 开始前把风险讲清楚一次：越狱会脱离官方支持，可能影响保修；Amazon 可能拉黑设备；误升级会丢越狱。用户确认后再继续。

## 流程总览

| 阶段 | 做什么 | 谁动手 |
|---|---|---|
| 0 | 讲风险、确认电脑环境（macOS / Linux 有脚本；Windows 按文档手动） | 你 |
| 1 | 识别机型、固件、是否带广告、能否注册亚马逊账号 | 用户读数，你记录 |
| 2 | 防自动更新（飞行模式 + 填满存储） | 用户 + 你 |
| 3 | 查越狱方法，按方法页越狱 | 用户主导，你准备文件 |
| 4 | 越狱后的收尾（新式：KPM/Jobman；旧式：Hotfix + KUAL + MRPI） | 用户 + 你 |
| 5 | 安装 KOReader v2026.07.1（选对包） | 你拷文件，用户启动 |
| 6 | 覆盖本仓库界面 | 你 |
| 7 | 可选：中文字体、书库 | 你 |
| 8 | 验证，交代日常注意事项和回退方法 | 你 |

## 阶段 1：识别设备

让用户在 Kindle 上打开「⋮ → 设置 → 设备选项 → 设备信息」（英文界面是 Settings → Device options → Device info），读出：

- 序列号前 8 位（不要让用户把完整序列号发出来，前 8 位就够判断机型）。
- 固件版本，例如 `5.13.6`、`5.18.1.0.1`；Shadow 越狱还要括号里那串 10 位编号。
- 锁屏有没有广告（AdBreak 只适用于带广告版）。
- 这台 Kindle 现在还能不能注册亚马逊账号。**中国区账号的商店和推送服务已停，按「不能注册」处理**，这会排除需要注册的方法（WinterBreak、SpringBreak、AdBreak）。

然后运行：

```bash
python3 scripts/jb_lookup.py --serial G0XXXXXX --firmware 5.18.1 --registered no --ads no
```

输出机型、可用的越狱方法（第一个是 wiki 推荐的）、每个方法的说明页链接，以及该装哪个 KOReader 包。没有可用方法时，告诉用户：保持飞行模式、填满存储、等新越狱发布，不要升级。

## 阶段 2：防自动更新

按 wiki 的 Prevent Automatic Updates 页（https://kindlemodding.org/jailbreaking/prevent-auto-update/）做，要点：

1. 先开飞行模式，越狱完成前一直开着。只有方法页明确要求联网的那一步才关。
2. 把 USB 根目录里的 `update*.bin`、`update.bin.tmp.partial` 删掉。
3. 把存储填满，只留 50~90 MB，让后台没地方下载更新包。USB 存储模式的机型可以用 wiki 给的 Filler 脚本；MTP 机型（多数 2024 年以后的机型和 Scribe）脚本不能用，要手动拷填充文件。
4. Shadow 越狱全程 Kindle 不联网，可以跳过填充，但飞行模式照开。

越狱完成后，新式越狱会自动屏蔽更新，填充文件可以删掉（wiki 写的是删 `fill_disk` 目录）。

## 阶段 3：越狱

1. 运行 `scripts/kindle_find.sh`，确认 Kindle 是以 U 盘挂载（输出里有挂载路径）还是 MTP（没有挂载路径，要用 OpenMTP 或 Amazon 的 USB File Manager 之类的工具拷文件）。
2. 打开 `jb_lookup.py` 给出的方法页，**完整读一遍**再动手，把步骤用中文复述给用户，特别标出：哪一步要联网、哪一步要等、成功时屏幕上会出现什么。
3. 需要往 Kindle 拷文件的，你来拷（macOS 用 `COPYFILE_DISABLE=1`，拷完 `dot_clean -m <挂载路径>`；需要拷隐藏目录的方法，比如 WinterBreak 的 `.active_content_sandbox`，拷完列目录确认它在）。
4. 失败时先对照方法页的 troubleshooting，再看 `references/troubleshooting.md`。同一方法别无限重试，两次失败就换方法页里列出的备选方法。

各方法的固件范围、是否要注册、已知坑，见 `references/jailbreak-methods.md`。

## 阶段 4：越狱后

先判断走哪条路，看 `references/after-jailbreak.md`：

- **新式越狱**（Véra、Shadow、SpiderCat、SpringBreak、Sanctuary、AdBreak、Nosebleed 以及较新的 WinterBreak）：用首页搜索栏的 `;kpm` 命令装 Jobman（越狱管理器）。**KUAL 在新式越狱下已经不能用**，别装。
- **旧式越狱**（WinterBreak2、早期 WinterBreak、LanguageBreak 等 Legacy 方法）：装 Hotfix，再装 KUAL 和 MRPI，按 Legacy 页面关掉 OTA。

## 阶段 5：安装 KOReader v2026.07.1

**不要用 `;kpm install koreader`**：KPM 仓库里的版本不受控，和本界面要求的 v2026.07.1 不一定一致。手动装：

```bash
bash scripts/koreader_install.sh <Kindle 挂载路径> <包名>
```

包名由 `jb_lookup.py` 给出：固件 ≥ 5.16.3 用 `kindlehf`；更低固件的触屏机型用 `kindlepw2`；K4、Kindle Touch、第一代 Paperwhite 用 `kindle`；带键盘的老机型用 `kindle-legacy`。脚本会下载官方 zip、核对大小、解压到 Kindle 根目录。之后的启动方式取决于越狱类型（scriptlet / KUAL / KUALA / KPM 书），见 `references/after-jailbreak.md`。

让用户启动一次 KOReader，确认能进文件浏览器，然后**正常退出**（KOReader 运行时不能进 U 盘模式，退出时还会用内存里的设置覆盖文件）。

## 阶段 6：覆盖界面

```bash
bash scripts/ui_install.sh <Kindle 挂载路径>
```

脚本会：确认 Kindle 上的 KOReader 是 v2026.07.1；备份现有的 `koreader/frontend`、`plugins`、`resources`、`defaults.lua`、`reader.lua` 到电脑的 `~/kindle-koreader-backups/<时间>/`；从本仓库取界面文件（优先用仓库 Release 里的 Kindle 覆盖包，没有就浅克隆仓库现场组装）；不带 `--delete` 地覆盖进去，保留 Kindle 原有插件；最后清理 macOS 的 `._` 文件并逐个比对。

覆盖包里带开源微信读书插件 weread.koplugin（书架右上角第一个标签「微信读书」），**不带任何账号信息**。用户要用的话，在 Kindle 上点「微信读书」标签，按登录页提示扫码登录（先在手机微信读书「我 › 设置 › 微信读书 Skill」里获取 API Key；手机确认页要勾选「自动退出登录」，否则 Kindle 报 HTTP 401）；扫码需要临时开 Wi-Fi。不要替用户扫码，也不要从别的设备拷 `settings/weread.lua` 过来。

覆盖完让用户**拔线**，再从启动入口打开 KOReader。推完文件后 KOReader 打不开、而 `koreader/crash.log` 里没有新的 `launching...` 行，说明它根本没被拉起：拔线后重启 Kindle 再试，不是界面坏了。

界面包含什么、在哪些机型上验证过，见 `references/ui-overview.md`。

## 阶段 7：可选

- 中文字体：霞鹜文楷（OFL 协议，可自由分发）从 https://github.com/lxgw/LxgwWenKai/releases 下载 ttf，放进 `koreader/fonts/`。**不要**往 Kindle 里放来源不明或没有分发授权的商业字体。
- 词典：StarDict 格式放进 `koreader/data/dict/<词典名>/`。
- 书库：KOReader 自带 OPDS，地址写 `http://` 还是 `https://` 按服务端实际配置，局域网自建的服务多半是 `http://`。

## 阶段 8：验证与交接

逐项确认：KOReader 能从启动入口打开；书架、阅读工具栏（点屏幕中央）、长按选词都正常；书架右上角第一个标签是「微信读书」，点开能看到登录页（用户登录后能看到书架）；Jobman 或 Legacy 方式下更新确实被屏蔽。然后告诉用户：

- 平时尽量保持飞行模式，只在需要时开 Wi-Fi。
- 改 KOReader 设置文件、拷书之前先退出 KOReader。
- macOS 往 Kindle 拷文件后跑一次 `dot_clean -m`。
- 回退界面：`bash scripts/ui_rollback.sh <挂载路径> <备份目录>`；彻底回到原厂见 `references/troubleshooting.md` 的「卸载越狱」。

## 文件

- `scripts/kindle_find.sh`：找 Kindle 挂载路径，报告剩余空间、越狱痕迹、已装的 KOReader 版本。
- `scripts/jb_lookup.py`：按序列号前缀、固件、能否注册、有无广告，查 wiki 实时数据，给出越狱方法和 KOReader 包名。
- `scripts/koreader_install.sh`：下载并安装指定变体的 KOReader v2026.07.1。
- `scripts/ui_install.sh`、`scripts/ui_rollback.sh`：覆盖 / 回退本仓库界面。
- `references/jailbreak-methods.md`：越狱方法快照（2026-11-26）。
- `references/after-jailbreak.md`：越狱后收尾、防更新、KOReader 启动方式。
- `references/troubleshooting.md`：常见问题、恢复、卸载越狱、MTP。
- `references/ui-overview.md`：界面改了什么、验证过的设备、已知限制。

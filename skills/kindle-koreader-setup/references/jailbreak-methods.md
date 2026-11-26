# 越狱方法快照（2026-11-26）

> 这是快照，不是依据。越狱方法几个月就变一次，**以 `scripts/jb_lookup.py` 读到的 wiki 实时数据和方法页当下的内容为准**。数据源：https://kindlemodding.org/jailbreaks.json 、https://kindlemodding.org/models.json ，向导页 https://kindlemodding.org/jailbreak-wizard.html 。

## 机型代号

wiki 用代号指机型，`jb_lookup.py` 会从序列号前缀算出来：

| 代号 | 机型 |
|---|---|
| PW / PW2 / PW3 | Paperwhite 第 1 / 2 / 3 代（2012 / 2013 / 2015） |
| KV | Voyage |
| KT2 / KT3 | 入门款第 7 / 8 代 |
| KOA / KOA2 / KOA3 | Oasis 第 1 / 2 / 3 代 |
| PW4 / KT4 | 第 10 代 Paperwhite / 入门款 |
| PW5 / KT5 | 第 11 代 Paperwhite / 2022 入门款 |
| KS / KS2 / KS3 | Scribe 2022 / 2024 / 第 3 代 |
| KT6 / PW6 | 2024 入门款 / 2024 Paperwhite |
| CS / KSC | Colorsoft / Scribe Colorsoft |
| KT7 / PW7 | 2026 入门款 / 2026 Paperwhite |

## 方法一览

区间含两端。「要注册」= 设备必须能登录亚马逊账号；中国区账号按不能注册处理。

| 方法 | 机型 | 固件区间 | 要注册 | 要广告版 | Kindle 要联网 |
|---|---|---|---|---|---|
| Véra | PW5、KT5、KT6、PW6、CS、KS、KS2 | 5.17.1 ~ 5.20.2.0.1 | 否 | 否 | 是 |
| Shadow | KS、KS2、CS、PW6、KT6 | 5.19.4 ~ 5.19.6 | 否 | 否 | 否（电脑端程序，走 MTP） |
| SpiderCat | PW4、KT4、KOA3、PW5、KT5、KT6、PW6、CS、KS、KS2 | 5.16.3 ~ 5.19.5 | 否 | 否 | 是 |
| SpringBreak | PW5、KT5（5.18.1 ~ 5.19.2.0.1）；PW4、KT4（5.18.1 ~ 5.18.1.1.1） | 见左 | 是 | 否 | 是 |
| AdBreak | KOA3、PW5、KT5、KS、KT6、PW6（5.18.1 ~ 5.18.5.0.1）；PW4、KT4（仅 5.18.1） | 见左 | 是 | 是 | 是 |
| Nosebleed | KT5、PW5、KOA3（5.16.4 ~ 5.18.6）；PW6、KT6（5.16.4 ~ 5.17.1.0.4） | 见左 | 否 | 否 | 是 |
| Sanctuary | PW4、KT4、KOA3、PW5、KT5、KS、KT6、PW6、KS2、CS | 5.16.4 ~ 5.18.3（不含 5.16.5） | 否 | 否 | 是 |
| WinterBreak | PW 到 CS 的大多数机型 | 5.6.1.1 ~ 5.18.0.2 | 是 | 否 | 是 |
| WinterBreak2 | PW、PW2、KV、KT2、PW3、KOA、KT3、KOA2、PW4、KT4、KOA3、PW5、KT5、KS | 5.6.1.1 ~ 5.16.3（另含 5.16.5） | 否 | 否 | 是 |
| Legacy（NiLuJe K2/DX/K3、K4、K5 等） | 键盘机、K4、Kindle Touch | 老固件 | — | — | — |

截至快照时**没有任何方法**的机型：KS3、KSC、KT7、PW7。这些机型只能等，期间保持飞行模式、填满存储。

## 各方法要点

每个方法开始前都要：飞行模式、填满存储（Shadow 除外）、删掉根目录的 `update*.bin` 和 `update.bin.tmp.partial`。

- **Véra**（https://kindlemodding.org/jailbreaking/Vera/ ，2026-08-10 发布）：在 Kindle 自带浏览器打开 `kindlemodding.org/vera`，选机型固件，下载「Font Calibration」书和对应机型的 Véra 书；按页面要求设好字体、字号、行距存成主题，再打开 Véra 书，等界面重启。全程保持 Wi-Fi。页面正文和元数据写的上限不一致（正文 5.19.6，元数据 5.20.2.0.1），固件不在下拉框里时页面说「试最接近的」，不保证成功。
- **Shadow**（https://kindlemodding.org/jailbreaking/Shadow/ ，2026-10-26）：电脑端程序，要固件号后括号里的 10 位编号。运行前：macOS `killall ptpcamerad`，Linux `killall kiod6 kiod5 gvfsd-mtp`，Windows 关掉资源管理器后重插。需要管理员 / root 权限（它会替换 USB 驱动），按提示拔插。偶尔报 "did not get a clean address leak"，重试即可。
- **SpiderCat**（https://kindlemodding.org/jailbreaking/SpiderCat/ ，2026-09-01）：把 SpiderCat 书放进 `documents/`（或在 Kindle 浏览器打开 `kindlemodding.org/spidercat` 下载），从书库打开，保持 Wi-Fi，等文字滚动到 "Restarting Kindle"。末行出现 `abort:no-firm` 说明机型或固件不兼容。可能要 10~20 分钟。**不支持 5.19.6**。
- **SpringBreak**（https://kindlemodding.org/jailbreaking/SpringBreak/ ）：电脑端程序，往 Kindle 写大量嵌套文件夹，再在商店里关飞行模式触发。**完成后必须再运行一次程序清理**，否则开机会超过 15 分钟。
- **AdBreak**（https://kindlemodding.org/jailbreaking/AdBreak/ ）：只适用带广告版。联网等广告下载 → 飞行模式 → 改 `system/.assets` 里的文件 → 点锁屏广告触发。不会去掉广告。
- **Nosebleed**（https://kindlemodding.org/jailbreaking/Nosebleed/ ）：两个文件放根目录，Kindle 浏览器打开 `kindlemodding.org/nosb` 点按钮。弹出 Application error 是正常的。
- **Sanctuary**（https://kindlemodding.org/jailbreaking/Sanctuary/ ）：要访问第三方站点 `http://sanctuary.skyvincent.com/scroll`（必须 http），端口扫描最多 20 分钟。依赖第三方站点，站点挂了就用不了。
- **WinterBreak**（https://kindlemodding.org/jailbreaking/WinterBreak/ ）：要已注册账号。macOS / Linux 拷文件时**必须把隐藏目录 `.active_content_sandbox` 一起拷过去**（Finder 里 ⌘⇧. 显示隐藏文件）。测试期间变砖过一台 PW4。
- **WinterBreak2**（https://kindlemodding.org/jailbreaking/WinterBreak2/ ）：`wb2.zip` 解压到根目录，连 Wi-Fi，用 Kindle 实验性浏览器打开页面写的地址点 Jailbreak，不需要登录亚马逊。已在 Kindle Voyage 5.13.6（中国区账号）上实测成功（2026-11-16）。

## 不要做的事

- 不要为了越狱去升级或降级固件，除非方法页明确要求升到某个「最新可越狱版本」。没有越狱就不能降级，5.18 以后部分机型连同分支降级都不行。
- 不要同时折腾两种方法。一种失败两次，再按方法页给的备选换下一种。
- 不要用论坛或网盘里的「一键越狱包」。

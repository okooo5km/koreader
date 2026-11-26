#!/usr/bin/env python3
"""按 Kindle Modding Wiki 的实时数据查越狱方法，并给出该装的 KOReader 包。

判定逻辑照搬 wiki 向导页（https://kindlemodding.org/jailbreak-wizard.html 的 jailbreakFinder.js）：
序列号前缀 → 机型代号 → 在 jailbreaks.json 里按机型、是否需要注册、是否需要广告版、固件区间筛选。

用法：
  python3 jb_lookup.py --serial G0XXXXXX --firmware 5.18.1 --registered no --ads no
  python3 jb_lookup.py --model KV --firmware 5.13.6 --registered no --ads no

只用标准库。网络取不到时直接报错退出，不用旧数据硬猜。
okooo5km(十里)
"""
import argparse
import json
import sys
import urllib.request

BASE = "https://kindlemodding.org/"
UA = "Mozilla/5.0 (kindle-koreader-setup skill)"

# KOReader v2026.07.1 的 Kindle 包（KOReader 官方 wiki「Installation on Kindle devices」）
KEYBOARD_MODELS = {"K2", "DX", "K3"}           # 带键盘的老机型
KINDLE_PKG_MODELS = {"K4", "KT", "PW"}          # K4、Kindle Touch、第一代 Paperwhite
HF_FROM = "5.16.3"                              # 硬浮点固件起点


def fetch(name):
    req = urllib.request.Request(BASE + name, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def cmp_ver(a, b):
    x = [int(p) for p in a.split(".")]
    y = [int(p) for p in b.split(".")]
    for i in range(max(len(x), len(y))):
        p = x[i] if i < len(x) else 0
        q = y[i] if i < len(y) else 0
        if p != q:
            return 1 if p > q else -1
    return 0


def serial_info(serial):
    s = serial.upper().replace(" ", "")
    if len(s) in (2, 3):
        return (0 if len(s) == 2 else 1), s
    if s.startswith("G"):
        if len(s) < 6:
            sys.exit("序列号太短：以 G 开头的序列号至少给 6 位（建议 8 位）")
        return 1, s[3:6]
    if s[:1] in "0123456789ABCDEF" and s:
        if len(s) < 4:
            sys.exit("序列号太短：至少给 4 位（建议 8 位）")
        return 0, s[2:4]
    sys.exit("序列号格式不对")


def find_model(models, serial=None, nickname=None):
    if nickname:
        for m in models:
            if m["generation_nickname"].upper() == nickname.upper():
                return m
        sys.exit(f"wiki 的机型表里没有代号 {nickname}")
    version, code = serial_info(serial)
    for m in models:
        if m["serial_version"] < version:
            continue
        if code in m["device_codes"]:
            return m
    sys.exit(f"wiki 的机型表里查不到设备码 {code}（序列号前缀可能输错了）")


def koreader_package(model, firmware):
    nick = model["generation_nickname"]
    if nick in KEYBOARD_MODELS:
        return "kindle-legacy"
    if nick in KINDLE_PKG_MODELS:
        return "kindle"
    return "kindlehf" if cmp_ver(firmware, HF_FROM) >= 0 else "kindlepw2"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--serial", help="序列号前 8 位")
    g.add_argument("--model", help="已知机型代号，例如 KV、PW5、KS2")
    ap.add_argument("--firmware", required=True, help="固件版本，例如 5.18.1.0.1")
    ap.add_argument("--registered", choices=["yes", "no"], required=True,
                    help="现在能否注册亚马逊账号（中国区账号按 no）")
    ap.add_argument("--ads", choices=["yes", "no", "unsure"], required=True, help="锁屏是否有广告")
    a = ap.parse_args()

    fw = a.firmware.strip()
    if not all(p.isdigit() for p in fw.split(".")) or int(fw.split(".")[0]) > 5:
        sys.exit("固件版本格式不对，应形如 5.18.1 或 5.18.1.0.1")

    try:
        models = fetch("models.json")
        jbs = fetch("jailbreaks.json")
    except Exception as e:  # noqa: BLE001
        sys.exit(f"取不到 wiki 数据（{e}）。请直接打开 {BASE}jailbreak-wizard.html 手动查。")

    model = find_model(models, a.serial, a.model)
    nick = model["generation_nickname"]
    registered = a.registered == "yes"
    ads = a.ads == "yes"

    matches = []
    for jb in jbs:
        if nick not in jb["models"]:
            continue
        if jb.get("registration") and not registered:
            continue
        if jb.get("ads") and not ads:
            continue
        ok = False
        for rule in jb["firmwares"]:
            if "all" not in rule["models"] and nick not in rule["models"]:
                continue
            out = rule.get("outliers", {})
            if fw in out.get("denied", []):
                continue
            if fw in out.get("accepted", []) or (cmp_ver(fw, rule["min"]) >= 0 and cmp_ver(fw, rule["max"]) <= 0):
                ok = True
                break
        if ok:
            matches.append(jb)

    print(f"机型：{model['amazon_name']}（代号 {nick}，最后官方固件 {model.get('last_firmware')}）")
    print(f"固件：{fw}    能否注册：{'能' if registered else '不能'}    广告版：{a.ads}")
    print()
    if matches:
        print("可用越狱方法（第一个是 wiki 推荐的）：")
        for i, jb in enumerate(matches, 1):
            need = []
            if jb.get("registration"):
                need.append("需要已注册账号")
            if jb.get("ads"):
                need.append("需要带广告版")
            extra = f"（{'、'.join(need)}）" if need else ""
            print(f"  {i}. {jb['name']}{extra}  {BASE.rstrip('/')}{jb['url']}")
        print()
        print("下一步：完整读一遍第 1 个方法的页面，按页面当下写的步骤做。")
    else:
        print("目前没有适用于这个机型和固件的越狱方法。")
        print("保持飞行模式、填满存储防止自动更新，等新越狱发布；不要升级固件。")
    print()
    pkg = koreader_package(model, fw)
    print(f"KOReader 包：{pkg}   →  koreader-{pkg}-v2026.07.1.zip")
    if model.get("platform", "").lower().startswith("n/a") or nick in ("K1", "KM"):
        print("注意：这个机型不在 KOReader 的支持范围内。")


if __name__ == "__main__":
    main()

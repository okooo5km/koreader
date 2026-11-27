--[[--
设备目标：iReader 与 Kindle 共用同一套界面代码，设备差异集中在这里决定，别在各处各自猜。

    iReader（Android）：微信读书用闭源 wereader 插件，首页「发现 / 书架 / 我」，系统输入法、读书桌面联动
    Kindle：微信读书用开源 weread.koplugin（书架来源标签进入），系统自动亮度开关、系统屏保图

共用：wereadkit 及全部换皮控件、亮度模块 wereadlight、中文按词选取、词典与字体。

okooo5km(十里)
]]

local Device = require("device")

local T = {}

function T.name()
    if Device:isKindle() then return "kindle" end
    if Device:isAndroid() then return "ireader" end
    return "other"
end

function T.isIReader() return T.name() == "ireader" end
function T.isKindle() return T.name() == "kindle" end

-- 插件目录是否存在且未被停用（FileManager 布局时插件还没加载，只能看目录）
local plugin_cache = {}
function T.hasPlugin(name)
    if plugin_cache[name] ~= nil then return plugin_cache[name] end
    local lfs = require("libs/libkoreader-lfs")
    local DataStorage = require("datastorage")
    local disabled = G_reader_settings:readSetting("plugins_disabled") or {}
    local found = false
    if not disabled[name] then
        for _, dir in ipairs{ DataStorage:getDataDir() .. "/plugins", "plugins" } do
            if lfs.attributes(dir .. "/" .. name .. ".koplugin", "mode") == "directory" then
                found = true
                break
            end
        end
    end
    plugin_cache[name] = found
    return found
end

-- 微信读书由哪个插件提供："wereader"（闭源，仅 iReader 完整版）| "weread"（开源 weread.koplugin）| nil
-- 开源插件随分享版 / Kindle 覆盖包一起分发（plugins/weread.koplugin）；iReader 完整版不打包它（build_apk.sh 排除）
function T.wereadProvider()
    local F = require("ireader/features")
    if T.isIReader() and F.weread() then return "wereader" end
    if F.wereadSkin() and T.hasPlugin("weread") then return "weread" end
    return nil
end

-- 首页底部「发现 / 书架 / 我」：只有 iReader 装了闭源插件时才有内容
function T.homeTabs()
    return require("ireader/features").weread() and T.isIReader() and T.hasPlugin("wereader")
end

-- PNG 宽高（文件头 IHDR），读不出返回 nil
local function pngSize(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(24)
    f:close()
    if not head or #head < 24 or head:sub(2, 4) ~= "PNG" then return nil end
    local function u32(i)
        local a, b, c, d = head:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return u32(17), u32(21)
end

-- Kindle：KOReader 接管休眠画面后看不到系统壁纸。把系统自带屏保图里和屏幕同尺寸的复制到
-- screensaver_dir（默认 /mnt/us/screensavers），供「随机图片」休眠画面使用。目录里已有图就不动。
function T.copyKindleScreensavers()
    local lfs = require("libs/libkoreader-lfs")
    local logger = require("logger")
    local dst = G_reader_settings:readSetting("screensaver_dir") or "/mnt/us/screensavers"
    if lfs.attributes(dst, "mode") == "directory" then
        for name in lfs.dir(dst) do
            if name:lower():match("%.png$") or name:lower():match("%.jpe?g$") then return end
        end
    else
        lfs.mkdir(dst)
    end
    local src = "/usr/share/blanket/screensaver"
    if lfs.attributes(src, "mode") ~= "directory" then
        logger.warn("target: no system screensaver dir", src)
        return
    end
    local Screen = Device.screen
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local w0, h0 = math.min(sw, sh), math.max(sw, sh)
    local function copy(path, name)
        local inf = io.open(path, "rb")
        local data = inf and inf:read("*a")
        if inf then inf:close() end
        local out = data and io.open(dst .. "/" .. name, "wb")
        if not out then return false end
        out:write(data)
        out:close()
        return true
    end
    local pngs, copied = {}, 0
    for name in lfs.dir(src) do
        local path = src .. "/" .. name
        if name:lower():match("%.png$") and lfs.attributes(path, "mode") == "file" then
            table.insert(pngs, { path = path, name = name })
            local w, h = pngSize(path)
            if w and math.min(w, h) == w0 and math.max(w, h) == h0 and copy(path, name) then
                copied = copied + 1
            end
        end
    end
    -- 没有和屏幕同尺寸的图：全部拷过去，交给休眠画面缩放
    if copied == 0 then
        for _, p in ipairs(pngs) do
            if copy(p.path, p.name) then copied = copied + 1 end
        end
    end
    local seen = #pngs
    logger.info("target: copied system screensavers", copied, "of", seen, "size", w0, h0)
end

function T.onStartup()
    if T.isKindle() and G_reader_settings:readSetting("screensaver_type") == "random_image" then
        pcall(T.copyKindleScreensavers)
    end
end

return T

--[[--
iReader: 前光开关 / 档位 / Kindle 系统自动亮度的统一入口（阅读页亮度面板和亮度弹窗共用）。

Kindle Voyage 这类带光感的机型，系统 powerd 的「自动亮度」（lipc com.lab126.powerd flAuto）
在 KOReader 运行时照样工作：KOReader 往 sysfs 写 0 关灯后，powerd 按环境光会把灯重新调亮。
所以这里关灯时顺带关掉系统自动亮度，并在面板上给出「自动亮度」开关；
读状态前先按硬件实际亮度同步，避免面板显示「关」而灯其实被系统点亮了。

okooo5km(十里)
]]

local Device = require("device")
local logger = require("logger")

local Light = {
    STEPS = 10,
}

local function powerd() return Device:getPowerDevice() end

-- hasLightSensor 只在 Kindle 设备类上有定义，安卓等平台直接调用会报 nil
local function hasLightSensor()
    return Device:isKindle() and type(Device.hasLightSensor) == "function" and Device:hasLightSensor()
end

local function lipc()
    local p = powerd()
    return Device:isKindle() and p and p.lipc_handle or nil
end

-- Kindle 带光感、lipc 可用时才有系统自动亮度
function Light.autoSupported()
    return Device:hasFrontlight() and hasLightSensor() and lipc() ~= nil
end

function Light.autoOn()
    local h = lipc()
    if not h or not hasLightSensor() then return false end
    local ok, v = pcall(h.get_int_property, h, "com.lab126.powerd", "flAuto")
    return ok and v == 1
end

function Light.setAuto(on)
    local h = lipc()
    if not h then return end
    local ok, err = pcall(h.set_int_property, h, "com.lab126.powerd", "flAuto", on and 1 or 0)
    if not ok then logger.warn("wereadlight: set flAuto failed", err) end
    Light.sync()
end

-- 按硬件实际亮度刷新 KOReader 的缓存（Kindle 系统可能在背后改过）
function Light.sync()
    local p = powerd()
    if not (Device:isKindle() and Device:hasFrontlight()) then return end
    local ok, hw = pcall(p.frontlightIntensityHW, p)
    if not ok or type(hw) ~= "number" then return end
    if hw > p.fl_min then
        p.fl_intensity = hw
        p.is_fl_on = true
    else
        p.is_fl_on = false
    end
end

function Light.isOn()
    Light.sync()
    return powerd():isFrontlightOn()
end

function Light.setOn(on)
    local p = powerd()
    if not Device:isKindle() then
        -- 安卓：原版 turnOn/OffFrontlight 会调 android.hasStandaloneWarmth()，
        -- iReader 的启动器没有这个 JNI 方法，直接原生崩溃。改用 setIntensity，自己记住关灯前的亮度。
        if on then
            if p:isFrontlightOn() then return end
            local last = G_reader_settings:readSetting("ireader_fl_last_on")
            if type(last) ~= "number" or last <= p.fl_min then
                last = p.fl_min + math.ceil((p.fl_max - p.fl_min) / Light.STEPS)
            end
            p:setIntensity(last)
        else
            if not p:isFrontlightOn() then return end
            G_reader_settings:saveSetting("ireader_fl_last_on", p:frontlightIntensity())
            p:setIntensity(p.fl_min)
        end
        return
    end
    if on then
        p:turnOnFrontlight()
    else
        -- 不先关系统自动亮度，灯过一会儿会被 powerd 重新点亮
        if Light.autoOn() then Light.setAuto(false) end
        p:turnOffFrontlight()
    end
end

-- 0..STEPS 档
function Light.level()
    Light.sync()
    local p = powerd()
    local cur = p:frontlightIntensity()
    return math.floor((cur - p.fl_min) * Light.STEPS / math.max(1, p.fl_max - p.fl_min) + 0.5)
end

function Light.setLevel(l)
    local p = powerd()
    l = math.max(0, math.min(Light.STEPS, l))
    if l == 0 then
        Light.setOn(false)
        return
    end
    if not Device:isKindle() then
        G_reader_settings:saveSetting("ireader_fl_last_on", p.fl_min + math.floor(l * (p.fl_max - p.fl_min) / Light.STEPS + 0.5))
    end
    p:setIntensity(p.fl_min + math.floor(l * (p.fl_max - p.fl_min) / Light.STEPS + 0.5))
end

-- 色温（暖光）：只在 Kindle 上启用（Oasis 2/3、PW5 Signature、Colorsoft 等带暖光的机型）。
-- 安卓的 hasNaturalLight 会走 JNI，部分启动器缺方法会原生崩溃；安卓用户可在原版菜单「设置 → 前光」里调。
function Light.warmthSupported()
    return Device:isKindle() and Device:hasFrontlight() and Device:hasNaturalLight() and true or false
end

-- 0..STEPS 档（KOReader 内部色温是 0..100）
function Light.warmthLevel()
    local p = powerd()
    return math.floor((p:frontlightWarmth() or 0) * Light.STEPS / 100 + 0.5)
end

function Light.setWarmthLevel(l)
    l = math.max(0, math.min(Light.STEPS, l))
    powerd():setWarmth(math.floor(l * 100 / Light.STEPS + 0.5))
end

return Light

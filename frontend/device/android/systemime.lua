--[[--
iReader: 系统输入法桥（Lua 侧，隐形输入框版）。

启动器（launcher-ime 补丁）在 MainActivity 上加了：
    showTextInput(String title, String text, int multiline)  开始输入
    getTextInputState() -> 0 空闲 / 1 输入中 / 2 完成或回车 / 3 返回键收起
    getTextInputResult() -> 当前文字
    closeTextInput()                                         结束输入
Java 侧是全透明窗口里的隐形 EditText，只为调起系统键盘；
这里轮询把文字实时同步给 KOReader 自己的输入框显示。
没打补丁的旧启动器上 available() 返回 false，调用方回退到 KOReader 自带键盘。

okooo5km(十里)
]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local SystemIME = {}

local available_cache
local session = 0   -- 每次 show 自增，旧会话的轮询自动作废
local active = false
local current -- { last = 文字, on_change = fn }，close 前补一次同步

local function withJNI(fn)
    local android = require("android")
    return android.jni:context(android.app.activity.vm, function(jni)
        return fn(jni, android.app.activity.clazz)
    end)
end

function SystemIME.available()
    if available_cache ~= nil then return available_cache end
    if not Device:isAndroid() then
        available_cache = false
        return false
    end
    local ok, res = pcall(withJNI, function(jni, obj)
        local env = jni.env
        local clazz = env[0].GetObjectClass(env, obj)
        local mid = env[0].GetMethodID(env, clazz, "closeTextInput", "()V")
        env[0].DeleteLocalRef(env, clazz)
        if mid == nil then
            -- 旧启动器：GetMethodID 会挂一个 NoSuchMethodError，必须清掉
            env[0].ExceptionClear(env)
            return false
        end
        return true
    end)
    available_cache = ok and res or false
    logger.info("SystemIME available:", available_cache)
    return available_cache
end

function SystemIME.enabled()
    return G_reader_settings:nilOrTrue("ireader_system_ime") and SystemIME.available()
end

local function getState()
    return withJNI(function(jni, obj) return jni:callIntMethod(obj, "getTextInputState", "()I") end)
end

local function getText()
    return withJNI(function(jni, obj)
        return jni:to_string(jni:callObjectMethod(obj, "getTextInputResult", "()Ljava/lang/String;"))
    end)
end

--- 开始输入。flags：1 多行 / 2 数字 / 4 密码（可相加，传 boolean 视为是否多行）。
--- on_change(text) 每次文字变化时调用；on_finish(text, by_enter) 在按完成/回车或返回键收起时调用。
function SystemIME.show(text, flags, on_change, on_finish)
    if type(flags) == "boolean" then flags = flags and 1 or 0 end
    flags = flags or 0
    -- 从一个框切到另一个框：上个框最后 0.2 秒内打的字还没同步，先补给它
    if active then pcall(SystemIME.sync) end
    session = session + 1
    local my = session
    active = true
    withJNI(function(jni, obj)
        local env = jni.env
        local t = env[0].NewStringUTF(env, "")
        local s = env[0].NewStringUTF(env, text or "")
        jni:callVoidMethod(obj, "showTextInput", "(Ljava/lang/String;Ljava/lang/String;I)V",
            t, s, require("ffi").new("int32_t", flags))
        env[0].DeleteLocalRef(env, t)
        env[0].DeleteLocalRef(env, s)
    end)
    current = { last = text or "", on_change = on_change }
    local cs = current
    local function poll()
        if my ~= session then return end
        local state = getState()
        local cur = getText()
        if cur ~= cs.last then
            cs.last = cur
            if on_change then on_change(cur) end
        end
        if state == 2 or state == 3 then
            active = false
            if on_finish then on_finish(cur, state == 2) end
            return
        end
        if state == 0 then active = false return end -- 被 close 掉了
        UIManager:scheduleIn(0.2, poll)
    end
    UIManager:scheduleIn(0.2, poll)
end

--- 结束输入（对话框关闭、点了 KOReader 的按钮等）。
function SystemIME.close()
    if not active then return end
    active = false
    session = session + 1
    -- 最后 0.2 秒内打的字可能还没同步，关之前补一次
    local cs = current
    local ok, cur = pcall(getText)
    if ok and cs and cur ~= cs.last then
        cs.last = cur
        if cs.on_change then cs.on_change(cur) end
    end
    pcall(withJNI, function(jni, obj) jni:callVoidMethod(obj, "closeTextInput", "()V") end)
end

--- 立即把系统键盘里的文字同步过来（不结束输入）。
function SystemIME.sync()
    if not active then return end
    local cs = current
    local ok, cur = pcall(getText)
    if ok and cs and cur ~= cs.last then
        cs.last = cur
        if cs.on_change then cs.on_change(cur) end
    end
end

function SystemIME.isActive()
    return active
end

return SystemIME

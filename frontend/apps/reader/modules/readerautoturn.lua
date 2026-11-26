--[[--
iReader: 本机书的自动翻页（ui.wrautoturn）。

微信读书云端书的自动翻页用 wereader 插件自己的（owner.auto_read），这里只给本机书：

- 开关状态只在内存里（不落盘，关书即停），间隔存 G_reader_settings "ireader_autoturn_interval"（秒，默认 30，5–300）；
- 每到间隔：栈顶窗口就是这个 ReaderUI 且未 suspend → GotoViewRel +1；否则 1 秒后重试（菜单 / 浮层开着时不翻）；
- 用户手动翻页后重新计时；
- 到书末（EndOfBook，或翻了一下页码没变）/ Suspend / CloseDocument 自动停，Resume 不自动恢复；
- 开 / 关时弹一句 Notification。

okooo5km(十里)
]]

local Event = require("ui/event")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local ReaderAutoTurn = WidgetContainer:extend{
    name = "wrautoturn",
}

local MIN_INTERVAL, MAX_INTERVAL, DEFAULT_INTERVAL = 5, 300, 30

function ReaderAutoTurn:init()
    self.running = false
    self.task = nil
    self.suspended = false
end

function ReaderAutoTurn:isRunning()
    return self.running
end

function ReaderAutoTurn:interval()
    local v = tonumber(G_reader_settings:readSetting("ireader_autoturn_interval", DEFAULT_INTERVAL)) or DEFAULT_INTERVAL
    if v ~= v then v = DEFAULT_INTERVAL end
    return math.max(MIN_INTERVAL, math.min(MAX_INTERVAL, math.floor(v)))
end

-- 成功返回 true；不是 5–300 的整数秒返回 false
function ReaderAutoTurn:setInterval(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds or seconds % 1 ~= 0
        or seconds < MIN_INTERVAL or seconds > MAX_INTERVAL then
        return false
    end
    G_reader_settings:saveSetting("ireader_autoturn_interval", seconds)
    if self.running then self:schedule(self:interval()) end
    return true
end

function ReaderAutoTurn:unschedule()
    if self.task then
        UIManager:unschedule(self.task)
        self.task = nil
    end
end

function ReaderAutoTurn:schedule(delay)
    self:unschedule()
    local task
    task = function()
        if self.task ~= task then return end
        self.task = nil
        self:tick()
    end
    self.task = task
    UIManager:scheduleIn(delay, task)
end

function ReaderAutoTurn:tick()
    if not self.running then return end
    local ui = self.ui
    if not ui.document or self.suspended then return self:stop("quiet") end
    if UIManager:getTopmostVisibleWidget() ~= ui then
        return self:schedule(1) -- 菜单 / 浮层 / 弹窗开着：等一会儿再翻
    end
    local before = ui:getCurrentPage()
    self.turning = true
    local ok, err = pcall(function() ui:handleEvent(Event:new("GotoViewRel", 1)) end)
    self.turning = false
    if not self.running then return end -- 翻页过程中触发了 EndOfBook → 已经 stop
    if not ok then
        logger.warn("wrautoturn turn failed", err)
        return self:stop()
    end
    if ui:getCurrentPage() == before then
        -- 页码没变：到书末了
        return self:stop("end")
    end
    self:schedule(self:interval())
end

function ReaderAutoTurn:start()
    if self.running then return end
    if not self.ui.document then return end
    self.running = true
    self.suspended = false
    self:schedule(self:interval())
    Notification:notify(string.format("已开启自动翻页 · %d 秒", self:interval()), Notification.SOURCE_ALWAYS_SHOW)
end

-- mode: nil 手动关 / "end" 到书末 / "quiet" 静默（休眠等）
function ReaderAutoTurn:stop(mode)
    local was = self.running
    self.running = false
    self.turning = false
    self:unschedule()
    if was and mode ~= "quiet" then
        Notification:notify(mode == "end" and "已到书末，自动翻页已关闭" or "已关闭自动翻页", Notification.SOURCE_ALWAYS_SHOW)
    end
end

function ReaderAutoTurn:toggle()
    if self.running then self:stop() else self:start() end
    return self.running
end

-- 用户手动翻页：重新计时（自己发的 GotoViewRel 不算）
function ReaderAutoTurn:onPageUpdate()
    if self.running and not self.turning then
        self:schedule(self:interval())
    end
end

function ReaderAutoTurn:onEndOfBook()
    if self.running then self:stop("end") end
    return false
end

function ReaderAutoTurn:onSuspend()
    self.suspended = true
    if self.running then self:stop("quiet") end
end

function ReaderAutoTurn:onResume()
    -- 不自动恢复
    self.suspended = false
end

function ReaderAutoTurn:onCloseDocument()
    self.running = false
    self.turning = false
    self:unschedule()
end

return ReaderAutoTurn

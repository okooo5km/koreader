--[[--
iReader: 亮度底部面板（替代 Android 原生 Holo 前光对话框）。

    灯光 (○)   夜间 (○)                    完成
    [-]  ■■■■□□□□□□  [+]

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Kit = require("ui/wereadkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local px, face = Kit.px, Kit.face
local Light = require("ui/wereadlight")
local STEPS = Light.STEPS

local LightDialog = InputContainer:extend{}

function LightDialog:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh } } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:build()
end

function LightDialog:level()
    return Light.level()
end

function LightDialog:setLevel(l)
    Light.setLevel(l)
    UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    self:refresh()
end

-- 一行开关：灯光 /（Kindle）自动 / 夜间
function LightDialog:switches()
    local g = HorizontalGroup:new{ align = "center" }
    local function add(label, checked, callback)
        if #g > 0 then table.insert(g, HorizontalSpan:new{ width = px(72) }) end
        table.insert(g, Kit.switchItem(label, checked, callback))
    end
    local function changed()
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
        self:refresh()
    end
    local is_on = Light.isOn()
    add("灯光", is_on, function() Light.setOn(not is_on); changed() end)
    if Light.autoSupported() then
        local auto = Light.autoOn()
        add("自动", auto, function() Light.setAuto(not auto); changed() end)
    end
    add("夜间", G_reader_settings:isTrue("night_mode"), function()
        UIManager:broadcastEvent(Event:new("ToggleNightMode"))
        self:refresh()
    end)
    return g
end

function LightDialog:build()
    local pad = px(44)
    local inner = self.sw - 2 * pad
    local level = self:level()
    local rows = VerticalGroup:new{ align = "left" }

    table.insert(rows, HorizontalGroup:new{
        align = "center",
        -- 开关整组在屏幕上水平居中：左边留出和右侧「完成」等宽的空位
        HorizontalSpan:new{ width = pad + px(160) },
        require("ui/widget/container/centercontainer"):new{
            dimen = Geom:new{ w = inner - 2 * px(160), h = px(100) },
            self:switches(),
        },
        Kit.Tappable:new{
            width = px(160), height = px(100), align = "right",
            content = TextWidget:new{ text = "完成", face = face(32) },
            callback = function() self:onClose() end,
        },
    })

    local btn_w, gap = px(100), px(8)
    local seg_area = inner - 2 * btn_w - 2 * px(16)
    local seg_w = math.floor((seg_area - gap * (STEPS - 1)) / STEPS)
    -- 十档条：亮度两侧 − / +，色温（带暖光的 Kindle）两侧「冷 / 暖」
    local function seg_row(cur, set, left, right)
        local segs = HorizontalGroup:new{ align = "center" }
        for i = 1, STEPS do
            table.insert(segs, Kit.Tappable:new{
                width = seg_w, height = px(100),
                content = FrameContainer:new{
                    width = seg_w, height = px(44), padding = 0, margin = 0,
                    bordersize = px(2), color = i <= cur and Blitbuffer.COLOR_BLACK or Kit.GRAY,
                    background = i <= cur and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                    VerticalSpan:new{ width = 0 },
                },
                callback = function() set(i == cur and i - 1 or i) end,
            })
            if i < STEPS then table.insert(segs, HorizontalSpan:new{ width = gap }) end
        end
        return HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            Kit.Tappable:new{ width = btn_w, height = px(100), content = left, callback = function() set(cur - 1) end },
            HorizontalSpan:new{ width = px(16) },
            segs,
            HorizontalSpan:new{ width = px(16) },
            Kit.Tappable:new{ width = btn_w, height = px(100), content = right, callback = function() set(cur + 1) end },
        }
    end
    table.insert(rows, seg_row(level, function(l) self:setLevel(l) end, Kit.icon("wr.minus", 44), Kit.icon("wr.plus", 44)))
    if Light.warmthSupported() then
        table.insert(rows, seg_row(Light.warmthLevel(), function(l)
            Light.setWarmthLevel(l)
            UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
            self:refresh()
        end, TextWidget:new{ text = "冷", face = face(30), fgcolor = Kit.GRAY },
            TextWidget:new{ text = "暖", face = face(30), fgcolor = Kit.GRAY }))
    end

    table.insert(rows, VerticalSpan:new{ width = px(24) })

    self.panel = VerticalGroup:new{ align = "left", Kit.line(self.sw, px(2)), rows }
    self[1] = self.panel
    self.panel_h = self.panel:getSize().h
    self.dimen = Geom:new{ x = 0, y = self.sh - self.panel_h, w = self.sw, h = self.panel_h }
end

function LightDialog:paintTo(bb, x, y)
    bb:paintRect(0, self.sh - self.panel_h, self.sw, self.panel_h, Blitbuffer.COLOR_WHITE)
    self.panel:paintTo(bb, 0, self.sh - self.panel_h)
end

function LightDialog:refresh()
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

function LightDialog:onShow()
    UIManager:setDirty(self, "ui", self.dimen)
end

function LightDialog:onCloseWidget()
    local d = self.dimen
    UIManager:setDirty(nil, "ui", d)
end

function LightDialog:onTapOutside(_, ges)
    if not ges.pos:intersectWith(self.dimen) then self:onClose() end
    return true
end

function LightDialog:onClose()
    UIManager:close(self)
    return true
end

return LightDialog

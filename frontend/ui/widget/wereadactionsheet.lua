--[[--
iReader: 底部操作单（微信读书式）。

    ActionSheet:new{
        header = widget,                    -- 可选：顶部信息区（如封面+书名）
        actions = {
            { icon = "wr.cat.book", text = "继续阅读", callback = fn },
            { icon = "wr.trash", text = "删除", callback = fn, separator = true },
            ...
        },
    }

点空白处关闭；点某一项先关闭面板再执行回调。

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Kit = require("ui/wereadkit")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local px, face = Kit.px, Kit.face

local ActionSheet = InputContainer:extend{
    header = nil,
    actions = nil,
}

function ActionSheet:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh } } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    local vg = VerticalGroup:new{ align = "left", Kit.line(self.sw, px(2)) }
    if self.header then
        table.insert(vg, self.header)
        table.insert(vg, LineWidget:new{
            background = Blitbuffer.COLOR_GRAY_D,
            dimen = Geom:new{ w = self.sw, h = px(8) },
        })
    end
    for i, a in ipairs(self.actions or {}) do
        if a.separator and i > 1 then
            table.insert(vg, LineWidget:new{
                background = Blitbuffer.COLOR_GRAY_D,
                dimen = Geom:new{ w = self.sw, h = px(8) },
            })
        elseif i > 1 then
            table.insert(vg, HorizontalGroup:new{
                HorizontalSpan:new{ width = px(120) },
                LineWidget:new{
                    background = Blitbuffer.COLOR_GRAY_D,
                    dimen = Geom:new{ w = self.sw - px(160), h = 1 },
                },
            })
        end
        local enabled = a.enabled ~= false
        local row = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = px(44) },
            Kit.icon(a.icon or "wr.cat.folder", 46),
            HorizontalSpan:new{ width = px(30) },
            TextWidget:new{
                text = a.text, face = face(32),
                fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_9,
                max_width = self.sw - px(320),
            },
        }
        if a.value then
            table.insert(row, HorizontalSpan:new{ width = px(16) })
            table.insert(row, TextWidget:new{ text = a.value, face = face(26), fgcolor = Kit.GRAY })
        end
        table.insert(vg, Kit.Tappable:new{
            width = self.sw, height = px(100), align = "left",
            content = row,
            callback = function()
                if not enabled then return end
                UIManager:close(self)
                if a.callback then UIManager:nextTick(a.callback) end
            end,
        })
    end
    table.insert(vg, VerticalSpan:new{ width = px(16) })
    self.panel = vg
    self[1] = vg
    self.panel_h = vg:getSize().h
    self.dimen = Geom:new{ x = 0, y = self.sh - self.panel_h, w = self.sw, h = self.panel_h }
end

function ActionSheet:paintTo(bb, x, y)
    bb:paintRect(0, self.sh - self.panel_h, self.sw, self.panel_h, Blitbuffer.COLOR_WHITE)
    self.panel:paintTo(bb, 0, self.sh - self.panel_h)
end

function ActionSheet:onShow()
    UIManager:setDirty(self, "ui", self.dimen)
end

function ActionSheet:onCloseWidget()
    UIManager:setDirty(nil, "ui", self.dimen)
end

function ActionSheet:onTapOutside(_, ges)
    if not ges.pos:intersectWith(self.dimen) then self:onClose() end
    return true
end

function ActionSheet:onClose()
    UIManager:close(self)
    return true
end

return ActionSheet

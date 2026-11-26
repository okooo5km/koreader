--[[--
Widget that shows a checkmark (`✓`), an empty box (`□`)
or nothing of the same size.

Example:

    local CheckMark = require("ui/widget/CheckMark")
    local parent_widget = FrameContainer:new{}
    table.insert(parent_widget, CheckMark:new{
        checkable = false, -- shows nothing when false, defaults to true
        checked = function() end, -- whether the box has a checkmark in it
    })
    UIManager:show(parent_widget)

]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local CheckMark = WidgetContainer:extend{
    checkable = true,
    checked = false,
    enabled = true,
    face = Font:getFace("smallinfofont"),
    width = 0,
    height = 0,
    baseline = 0,
}

-- iReader: 圆角方框；勾选=黑底白勾，未勾=细描边；不可用=灰
function CheckMark:init()
    local Kit = require("ui/wereadkit")
    local probe = TextWidget:new{ text = "▢ ", face = self.face }
    self.baseline = probe:getBaseline()
    local th = probe:getSize().h
    self._box = math.min(Kit.px(40), th)
    self._gap = Kit.px(14)
    self._tick = TextWidget:new{ text = "✓", face = Kit.face(28, true), fgcolor = Blitbuffer.COLOR_WHITE }
    self[1] = TextWidget:new{ text = "", face = self.face }
    self.dimen = require("ui/geometry"):new{ x = 0, y = 0, w = self._box + self._gap, h = th }
end

function CheckMark:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    if not self.checkable then return end
    local Kit = require("ui/wereadkit")
    local b = self._box
    local by = y + math.floor((self.dimen.h - b) / 2)
    local color = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_9
    if self.checked then
        bb:paintRoundedRect(x, by, b, b, color, Kit.px(8))
        local ts = self._tick:getSize()
        self._tick:paintTo(bb, x + math.floor((b - ts.w) / 2), by + math.floor((b - ts.h) / 2))
    else
        bb:paintBorder(x, by, b, b, Kit.px(2), color, Kit.px(8))
    end
end

return CheckMark

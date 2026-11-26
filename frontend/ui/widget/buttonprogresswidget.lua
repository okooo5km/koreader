local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

local ButtonProgressWidget = FocusManager:extend{
    width = Screen:scaleBySize(216),
    height = Size.item.height_default,
    padding = Size.padding.small,
    font_face = "cfont",
    font_size = 16,
    enabled = true,
    num_buttons = 2,
    position = 1,
    default_position = nil,
    thin_grey_style = false, -- default to black
    fine_tune = false, -- no -/+ buttons on the extremities by default
    more_options = false, -- no "⋮" button
}

function ButtonProgressWidget:init()
    self.current_button_index = self.position

    self.buttonprogress_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        radius = Size.radius.window,
        bordersize = 0,
        padding = self.padding,
        dim = not self.enabled,
    }


    self.buttonprogress_content = HorizontalGroup:new{}
    self.horizontal_span_width = 0
    if self.fine_tune or self.more_options then
        self.horizontal_span = HorizontalSpan:new{
            width = Size.margin.fine_tune
        }
        self.horizontal_span_width = self.horizontal_span.width
    end
    self:update()
    if self.fine_tune then
        self.current_button_index = self.current_button_index + 1
    end
    self.buttonprogress_frame[1] = self.buttonprogress_content
    self[1] = self.buttonprogress_frame
    self.dimen = Geom:new(self.buttonprogress_frame:getSize())
end

-- iReader: [−] ▮▮▮▮▯▯▯ [+] [更多]
-- 进度段为细描边圆角块，已到达的段填黑；默认档在段下方画一个小点
function ButtonProgressWidget:update()
    local Kit = require("ui/wereadkit")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local TextWidget = require("ui/widget/textwidget")
    self.layout = {{}}
    self.buttonprogress_content:clear()

    local h = math.min(self.height, Kit.px(76))
    local side_w = Kit.px(84)
    local more_w = Kit.px(100)
    local gap = Kit.px(14)
    local seg_gap = Kit.px(6)
    local avail = self.width
    if self.fine_tune then avail = avail - 2 * (side_w + gap) end
    if self.more_options then avail = avail - (more_w + gap) end
    local n = self.num_buttons
    local seg_w = math.floor((avail - seg_gap * (n - 1)) / n)
    local enabled_color = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_9

    local function boxed(w, content, filled)
        return FrameContainer:new{
            width = w, height = h, padding = 0, margin = 0,
            bordersize = Kit.px(2), radius = Kit.px(12), color = enabled_color,
            background = filled and enabled_color or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = w - 2 * Kit.px(2), h = h - 2 * Kit.px(2) }, content },
        }
    end
    local function add(w, content, filled, arg)
        local t = Kit.Tappable:new{
            width = w, height = h,
            content = boxed(w, content, filled),
            callback = function()
                if not self.enabled then return end
                self.callback(arg)
                if type(arg) == "number" then self.position = arg end
                self:update()
            end,
            hold_callback = function()
                if self.enabled and self.hold_callback then self.hold_callback(arg) end
            end,
        }
        table.insert(self.buttonprogress_content, t)
        table.insert(self.layout[1], t)
    end

    if self.fine_tune then
        add(side_w, Kit.icon("wr.minus", 36), false, "-")
        table.insert(self.buttonprogress_content, HorizontalSpan:new{ width = gap })
    end
    for i = 1, n do
        local filled = self.position and i <= self.position
        local mark = VerticalSpan:new{ width = 0 }
        if i == self.default_position then
            local d = Kit.px(10)
            local Widget = require("ui/widget/widget")
            mark = Widget:new{ dimen = Geom:new{ w = d, h = d } }
            function mark:getSize() return self.dimen end
            function mark:paintTo(bb, x, y)
                bb:paintCircle(x + d / 2, y + d / 2, d / 2,
                    filled and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
            end
        end
        add(seg_w, mark, filled, i)
        if i < n then table.insert(self.buttonprogress_content, HorizontalSpan:new{ width = seg_gap }) end
    end
    if self.fine_tune then
        table.insert(self.buttonprogress_content, HorizontalSpan:new{ width = gap })
        add(side_w, Kit.icon("wr.plus", 36), false, "+")
    end
    if self.more_options then
        table.insert(self.buttonprogress_content, HorizontalSpan:new{ width = gap })
        add(more_w, TextWidget:new{ text = "更多", face = Kit.face(26), fgcolor = enabled_color }, false, "⋮")
    end

    UIManager:setDirty(self.show_parent, function()
        return "ui", self.dimen
    end)
end

function ButtonProgressWidget:setPosition(position, default_position)
    self.position = position
    self.default_position = default_position
    self:update()
end

function ButtonProgressWidget:onTapSelect(arg, gev)
    if gev == nil then
        self:circlePosition()
    end
end

function ButtonProgressWidget:circlePosition()
    if self.position then
        self.position = self.position+1
        if self.position > self.num_buttons then
            self.position = 1
        end
        self.callback(self.position)
        self:update()
    end
end

return ButtonProgressWidget

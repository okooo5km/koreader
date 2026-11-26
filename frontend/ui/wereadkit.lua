--[[--
iReader 微信读书风格 UI 小工具：尺寸换算、字体、可点块、胶囊按钮、图标、书名清洗。

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local Screen = Device.screen

local Kit = {}

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY = Blitbuffer.COLOR_GRAY_5
Kit.BLACK, Kit.WHITE, Kit.GRAY = BLACK, WHITE, GRAY

-- 所有尺寸按 1080 宽的竖屏写，再按屏幕短边等比缩放：竖屏时短边就是宽，结果和以前一样；
-- 横屏（Oasis 等会自动旋转的机型）按短边算，控件不会跟着长边放大到溢出屏幕
local function px(v)
    return math.floor(v * math.min(Screen:getWidth(), Screen:getHeight()) / 1080 + 0.5)
end
-- Font:getFace 内部会再 scaleBySize，这里反算成像素字号
local function face(size_px, bold)
    local s = px(size_px) * 1000 / Screen:scaleBySize(1000)
    return Font:getFace(bold and "smallinfofontbold" or "cfont", s)
end

local function line(w, h, color)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = h or px(2) }, background = color or BLACK }
end

--------------------------------------------------------------------------
-- 通用可点块：内容居中，点按回调；按下不做反色（墨水屏减少闪烁）
--------------------------------------------------------------------------
local Tappable = InputContainer:extend{
    width = nil, height = nil,
    callback = nil, hold_callback = nil,
    align = "center",
}

function Tappable:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    local content = self.content
    local box = Geom:new{ w = self.width, h = self.height }
    if self.align == "left" then
        self[1] = LeftContainer:new{ dimen = box, content }
    elseif self.align == "right" then
        self[1] = RightContainer:new{ dimen = box, content }
    else
        self[1] = CenterContainer:new{ dimen = box, content }
    end
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Hold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
end

function Tappable:onTap()
    if self.callback then self.callback() end
    return true
end

function Tappable:onHold()
    if self.hold_callback then self.hold_callback() elseif self.callback then self.callback() end
    return true
end

-- 文字胶囊按钮：选中=黑底白字，未选中=细描边
local function chip(text, w, h, selected, callback, size)
    local tw = TextWidget:new{
        text = text, face = face(size or 34),
        fgcolor = selected and WHITE or BLACK,
        max_width = w - px(16),
    }
    local frame = FrameContainer:new{
        width = w, height = h,
        bordersize = px(2), radius = px(10), padding = 0, margin = 0,
        color = BLACK,
        background = selected and BLACK or WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = w - px(4), h = h - px(4) }, tw },
    }
    return Tappable:new{ width = w, height = h, content = frame, callback = callback }
end


-- 去掉书名里的营销括注，如「事实（读客熊猫君出品……）」
local function clean_title(t)
    if not t then return "" end
    local s = t:find("（", 1, true) or t:find("(", 1, true)
    if s and s > 1 then
        local _, n = t:sub(s):gsub("[^\128-\191]", "")
        if n >= 12 then return (t:sub(1, s - 1):gsub("%s+$", "")) end
    end
    return t
end

local function icon(name, size)
    return IconWidget:new{ icon = name, width = px(size), height = px(size) }
end


-- /storage/emulated/0 与 /storage/emulated/legacy（4.4 的两个挂载点）视为同一路径
function Kit.normPath(p)
    if not p then return "" end
    p = p:gsub("^/storage/emulated/legacy", "/storage/emulated/0"):gsub("^/sdcard", "/storage/emulated/0")
    p = p:gsub("/+$", "")
    return p
end
function Kit.samePath(a, b)
    return Kit.normPath(a) == Kit.normPath(b)
end

Kit.px, Kit.face, Kit.line, Kit.chip, Kit.icon, Kit.clean_title = px, face, line, chip, icon, clean_title
Kit.Tappable = Tappable

-- 拨动开关（墨水屏版：开=黑底白钮靠右，关=白底描边黑钮靠左）
local Widget = require("ui/widget/widget")
local Toggle = Widget:extend{ checked = false, enabled = true }
function Toggle:getSize() return Geom:new{ w = px(76), h = px(42) } end
function Toggle:paintTo(bb, x, y)
    local w, h = px(76), px(42)
    local r = math.floor(h / 2)
    local fg = self.enabled and BLACK or Blitbuffer.COLOR_GRAY_9
    if self.checked then
        bb:paintRoundedRect(x, y, w, h, fg, r)
        bb:paintCircle(x + w - r, y + r, r - px(5), WHITE)
    else
        bb:paintRoundedRect(x, y, w, h, WHITE, r)
        bb:paintBorder(x, y, w, h, px(3), fg, r)
        bb:paintCircle(x + r, y + r, r - px(8), fg)
    end
end
function Kit.toggle(checked, enabled)
    return Toggle:new{ checked = checked and true or false, enabled = enabled ~= false }
end

-- 「标签 + 开关」一组（亮度面板的 灯光 / 自动 / 夜间）：灰色标签在左，开关在右，整组可点
function Kit.switchItem(label, checked, callback)
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local group = HorizontalGroup:new{
        align = "center",
        TextWidget:new{ text = label, face = Kit.face(30), fgcolor = Kit.GRAY },
        HorizontalSpan:new{ width = Kit.px(20) },
        Kit.toggle(checked),
    }
    return Kit.Tappable:new{
        width = group:getSize().w, height = Kit.px(100), align = "left",
        content = group, callback = callback,
    }
end

-- 「↩ 返回原进度」胶囊：贴右下角、页脚上方（两种书共用；微信读书的 wrnative 和本机书的 wrreturn 都画它）
-- 右边距取 px(44)，与阅读浮层的 pad 一致；尺寸 220×56，字号 24，白底 px(2) 黑描边圆角
Kit.RETURN_CHIP_TEXT = "↩ 返回原进度"
function Kit.returnChipRect(ui)
    local w, h = px(220), px(56)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local view = ui and ui.view
    local footer = view and view.footer
    local fh = (footer and view.footer_visible) and footer:getHeight() or 0
    return Geom:new{ x = sw - px(44) - w, y = sh - fh - h - px(20), w = w, h = h }
end

local return_chip_cache
function Kit.paintReturnChip(bb, rect)
    local c = return_chip_cache
    if not c or c.w ~= rect.w or c.h ~= rect.h then
        local FrameContainer = require("ui/widget/container/framecontainer")
        c = {
            w = rect.w, h = rect.h,
            widget = FrameContainer:new{
                width = rect.w, height = rect.h,
                bordersize = px(2), radius = px(18), padding = 0, margin = 0,
                color = BLACK, background = WHITE,
                CenterContainer:new{
                    dimen = Geom:new{ w = rect.w - px(4), h = rect.h - px(4) },
                    TextWidget:new{ text = Kit.RETURN_CHIP_TEXT, face = face(24), max_width = rect.w - px(24) },
                },
            },
        }
        return_chip_cache = c
    end
    c.widget:paintTo(bb, rect.x, rect.y)
end

-- 导航行：「‹ 返回 | 标题」，固定高度
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local NavRow = InputContainer:extend{ width = nil, height = nil }
function NavRow:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or px(96)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self:set("", nil)
end
function NavRow:set(title, back_callback)
    local row = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = px(24) } }
    if back_callback then
        table.insert(row, Tappable:new{
            width = px(150), height = self.height, align = "left",
            content = HorizontalGroup:new{
                align = "center",
                icon("wr.back", 40),
                TextWidget:new{ text = "返回", face = face(30) },
            },
            callback = back_callback,
        })
        table.insert(row, line(px(2), px(36)))
        table.insert(row, HorizontalSpan:new{ width = px(24) })
    else
        table.insert(row, HorizontalSpan:new{ width = px(16) })
    end
    table.insert(row, TextWidget:new{
        text = title or "", face = face(32, true), max_width = self.width - px(260),
    })
    self[1] = VerticalGroup:new{
        align = "left",
        LeftContainer:new{ dimen = Geom:new{ w = self.width, h = self.height - px(2) }, row },
        line(self.width, px(2)),
    }
end
Kit.NavRow = NavRow

return Kit

--[[--
iReader: 书架 / 书库共用页头。

    书架                     本机   书库   全部    ⋯
    共 10 本
    [可选 extra_widget，如继续阅读卡 / 书库导航行]

继承 TitleBar（Menu / FileManager 依赖它的 getHeight、setSubTitle、dimen 等接口），
但不用它的左右图标按钮：右侧换成文字标签页 + 「⋯」。

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Kit = require("ui/wereadkit")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local px, face = Kit.px, Kit.face

local WeReadTitleBar = TitleBar:extend{
    tabs = nil,           -- { { text=, selected=, callback= }, ... }
    more_icon = "wr.more",
    more_callback = nil,
    more_hold_callback = nil,
}

function WeReadTitleBar:init()
    self.fullscreen = true
    self.align = "left"
    self.title_face = self.title_face or face(54, true)
    self.title_top_padding = self.title_top_padding or px(26)
    self.title_h_padding = px(40)
    self.subtitle_face = self.subtitle_face or face(26)
    self.subtitle_fullwidth = true
    self.bottom_v_padding = self.bottom_v_padding or px(14)
    self.left_icon = nil
    self.right_icon = nil
    self.close_callback = nil
    TitleBar.init(self)

    -- 右侧：标签页 + ⋯，与大标题同一行垂直居中
    local row_h = self.title_top_padding + self.title_widget:getSize().h + px(6)
    local group = HorizontalGroup:new{ align = "center" }
    for _, tab in ipairs(self.tabs or {}) do
        local tw = TextWidget:new{
            text = tab.text,
            face = face(32, tab.selected),
            fgcolor = tab.selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_5,
            max_width = px(260),
        }
        local w = tw:getSize().w
        table.insert(group, Kit.Tappable:new{
            width = w + px(36), height = row_h,
            content = VerticalGroup:new{
                align = "center",
                VerticalSpan:new{ width = px(10) },
                tw,
                VerticalSpan:new{ width = px(8) },
                tab.selected and Kit.line(math.min(w, px(48)), px(5)) or VerticalSpan:new{ width = px(5) },
            },
            callback = tab.callback,
        })
    end
    self.more_button = Kit.Tappable:new{
        width = px(96), height = row_h,
        content = Kit.icon(self.more_icon, 48),
        callback = function() if self.more_callback then self.more_callback() end end,
        hold_callback = function()
            if self.more_hold_callback then self.more_hold_callback()
            elseif self.more_callback then self.more_callback() end
        end,
    }
    table.insert(group, HorizontalSpan:new{ width = px(8) })
    table.insert(group, self.more_button)
    self.right_group = RightContainer:new{
        dimen = Geom:new{ w = self.width - px(16), h = row_h },
        group,
    }
    self.right_group.overlap_offset = { 0, 0 }
    table.insert(self, self.right_group)
    -- 有些代码拿 left_button.image.dimen 当弹窗锚点
    self.left_button = { image = { dimen = self.more_button.dimen } }
end

-- 选择模式等场景会切换右侧图标
function WeReadTitleBar:setRightIcon(icon)
    self.more_icon = (icon == "plus") and "wr.more" or icon
    self.more_button.content = Kit.icon(self.more_icon, 48)
    self.more_button:init()
    self.left_button.image.dimen = self.more_button.dimen
end

function WeReadTitleBar:setLeftIcon() end

-- 大标题固定为「书架」，目录名由导航行显示
function WeReadTitleBar:setTitle() end

return WeReadTitleBar

--[[--
iReader: 本机书的「↩ 返回原进度」胶囊（ui.wrreturn）。

复用 KOReader 自带的位置栈（ui.link.location_stack）：目录 / 搜索 / 链接 / 跳转页 / 书签 / 进度面板滑条
跳走前都会 addCurrentLocationToStack。这里只管“要不要提示返回”：

- 位置栈非空，且最近一次入栈之后连续翻页不到 3 次（语义同 wereader 插件的 notePageTurn / turn_count：
  跳过去看一眼就回来；翻了几页说明在这边读下去了，胶囊消失，但位置栈不清）；
- 当前位置和栈顶不在同一页（打开书时的入栈、手动“加入历史”不会凭空冒出胶囊）；
- 点胶囊 → ui.link:onGoBackLink()，随后胶囊消失，直到下一次入栈。

微信读书云端书（ui.wrnative 生效）不走这里，仍用插件自己的返回原进度（readerwereader.lua）。

okooo5km(十里)
]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local ReaderReturnChip = WidgetContainer:extend{
    name = "wrreturn",
}

local MAX_TURNS = 3 -- 连续翻满这么多页就不再提示（同插件）

local function kit() return require("ui/wereadkit") end

function ReaderReturnChip:init()
    self.turns = 0
    self.dismissed = false
    self.last_page = nil

    self.chip_widget = {
        owner = self,
        paintTo = function(w, bb) return w.owner:paintChip(bb) end,
    }
    self.ui.view:registerViewModule("wrreturn_chip", self.chip_widget)

    -- 包一层入栈：记下“刚跳转过”，重新计翻页数
    self.ui:registerPostInitCallback(function()
        local link = self.ui.link
        if not link or link._wrreturn_wrapped then return end
        link._wrreturn_wrapped = true
        local orig = link.addCurrentLocationToStack
        link.addCurrentLocationToStack = function(l, ...)
            local ret = orig(l, ...)
            self.turns = 0
            self.dismissed = false
            return ret
        end
    end)

    if Device:isTouchDevice() then
        self.ui:registerTouchZones({
            {
                id = "wrreturn_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                overrides = {
                    -- 同 wrnative_tap：压过原生翻页 / 菜单 / 角落 / 页脚；链接（tap_link）排在前面
                    "readerhighlight_tap", "readerfooter_tap",
                    "readerconfigmenu_ext_tap", "readerconfigmenu_tap",
                    "readermenu_ext_tap", "readermenu_tap",
                    "tap_top_left_corner", "tap_top_right_corner",
                    "tap_left_bottom_corner", "tap_right_bottom_corner",
                    "tap_forward", "tap_backward",
                },
                handler = function(ges) return self:onZoneTap(ges) end,
            },
        })
    end
end

-- 微信读书云端书用插件自己的胶囊
function ReaderReturnChip:isWeReadNative()
    local wrn = self.ui.wrnative
    return wrn and wrn.active and wrn:active() or false
end

-- 当前位置和栈顶是不是同一页
function ReaderReturnChip:atStackTop(top)
    local ui = self.ui
    if ui.rolling then
        if not top.xpointer then return true end
        local page = ui.document:getPageFromXPointer(top.xpointer)
        return page == ui:getCurrentPage()
    elseif ui.paging then
        return top[1] and top[1].page == ui:getCurrentPage()
    end
    return true
end

function ReaderReturnChip:visible()
    if self.dismissed or self.turns >= MAX_TURNS then return false end
    if self:isWeReadNative() then return false end
    local link = self.ui.link
    local stack = link and link.location_stack
    if not stack or #stack == 0 then return false end
    local ok, same = pcall(self.atStackTop, self, stack[#stack])
    if not ok then return false end
    return not same
end

function ReaderReturnChip:chipRect()
    if not self:visible() then return end
    return kit().returnChipRect(self.ui)
end

function ReaderReturnChip:paintChip(bb)
    local ok, err = pcall(function()
        local rect = self:chipRect()
        if rect then kit().paintReturnChip(bb, rect) end
    end)
    if not ok and not self.paint_warned then
        self.paint_warned = true
        logger.warn("wrreturn paint failed", err)
    end
end

-- 翻页计数：只有 ±1 页算“连续翻页”；一次跳多页（目录 / 链接 / 返回 / 滑条）算新的跳转，计数归零
function ReaderReturnChip:onPageUpdate(pageno)
    local previous = self.last_page
    self.last_page = pageno
    if not previous or previous == pageno then return end
    if math.abs(pageno - previous) == 1 then
        self.turns = self.turns + 1
    else
        self.turns = 0
    end
end

function ReaderReturnChip:onZoneTap(ges)
    local ok, handled = pcall(function()
        local rect = self:chipRect()
        local p = ges.pos
        if not (rect and p) then return false end
        if p.x < rect.x or p.x >= rect.x + rect.w or p.y < rect.y or p.y >= rect.y + rect.h then
            return false
        end
        self.dismissed = true
        self.ui.link:onGoBackLink() -- 失败（栈空）也无妨：胶囊照样收掉
        UIManager:setDirty(self.ui, "ui", rect)
        return true
    end)
    if not ok then
        logger.warn("wrreturn tap failed", handled)
        return false
    end
    return handled and true or false
end

return ReaderReturnChip

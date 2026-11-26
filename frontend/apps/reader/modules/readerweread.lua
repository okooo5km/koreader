--[[--
微信读书式阅读页控制层（iReader R6801 专用）。

点按屏幕中央呼出：顶栏（返回书架 / 书名 / 搜索 / 书签）+ 底部工具栏
（目录 / 进度 / 亮度 / 字体 / 更多）。进度、亮度、字体在工具栏上方展开面板，
「更多」进入 KOReader 原版完整菜单，保证功能不丢。

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Notification = require("ui/widget/notification")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local Kit = require("ui/wereadkit")
local BLACK, WHITE, GRAY = Kit.BLACK, Kit.WHITE, Kit.GRAY
local px, face, line, chip, icon, clean_title = Kit.px, Kit.face, Kit.line, Kit.chip, Kit.icon, Kit.clean_title
local Tappable = Kit.Tappable
local LIGHT = Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_GRAY_9

-- n 个等宽块 + 间距刚好铺满 total（余数从前往后每块多 1px），保证各行左右边线严格对齐
local function fit(n, gap, total)
    local space = total - gap * (n - 1)
    local base = math.floor(space / n)
    local rem = space - base * n
    local ws = {}
    for i = 1, n do ws[i] = base + (i <= rem and 1 or 0) end
    return ws
end

-- 秒 → 「2 小时 14 分」/「35 分钟」/「不足 1 分钟」
local function fmt_duration(sec)
    local m = math.floor((tonumber(sec) or 0) / 60)
    if m < 1 then return "不足 1 分钟" end
    if m < 60 then return m .. " 分钟" end
    local h, r = math.floor(m / 60), m % 60
    if r == 0 then return h .. " 小时" end
    return string.format("%d 小时 %d 分", h, r)
end

-- 细轨道 + 圆形滑块（微信读书进度条样式）
local Widget = require("ui/widget/widget")
local Slider = Widget:extend{ width = nil, height = nil, percentage = 0 }
function Slider:getSize() return Geom:new{ w = self.width, h = self.height } end
function Slider:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local r = px(20)
    local x0, x1 = x + r, x + self.width - r
    local cy = y + math.floor(self.height / 2)
    local kx = x0 + math.floor((x1 - x0) * math.max(0, math.min(1, self.percentage)))
    bb:paintRect(x0, cy - px(2), x1 - x0, px(4), Blitbuffer.COLOR_GRAY_9)
    bb:paintRect(x0, cy - px(4), kx - x0, px(8), BLACK)
    bb:paintCircle(kx, cy, r, WHITE)
    bb:paintCircle(kx, cy, r, BLACK, px(4))
end
function Slider:getPercentageFromPosition(pos)
    local r = px(20)
    local p = (pos.x - self.dimen.x - r) / (self.width - 2 * r)
    return math.max(0, math.min(1, p))
end

--------------------------------------------------------------------------
-- 浮层本体
--------------------------------------------------------------------------
local WeReadBar = InputContainer:extend{
    ui = nil,
    owner = nil,
    panel = nil, -- nil | "progress" | "light" | "font"
    covers_fullscreen = false,
}

function WeReadBar:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.pad = px(44)
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } },
        SwipeOutside = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:build()
end

function WeReadBar:build()
    self.top = self:buildTop()
    self.bottom = self:buildBottom()
    self[1] = self.top
    self[2] = self.bottom
    self.top_h = self.top:getSize().h
    self.bottom_h = self.bottom:getSize().h
    self.top_dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.top_h }
    self.bottom_dimen = Geom:new{ x = 0, y = self.sh - self.bottom_h, w = self.sw, h = self.bottom_h }
end

function WeReadBar:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.sw, self.top_h, WHITE)
    self.top:paintTo(bb, 0, 0)
    bb:paintRect(0, self.sh - self.bottom_h, self.sw, self.bottom_h, WHITE)
    self.bottom:paintTo(bb, 0, self.sh - self.bottom_h)
end

-- 刷新：只刷两条栏的区域
function WeReadBar:refreshRegion(old_bottom)
    local region = self.top_dimen:combine(self.bottom_dimen)
    if old_bottom then region = region:combine(old_bottom) end
    return region
end

function WeReadBar:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.top_dimen
    end)
    UIManager:setDirty(self, function()
        return "ui", self.bottom_dimen
    end)
    return true
end

function WeReadBar:onCloseWidget()
    self.closed = true
    local top, bottom = self.top_dimen, self.bottom_dimen
    UIManager:setDirty(nil, function() return "ui", top end)
    UIManager:setDirty(nil, function() return "ui", bottom end)
    if self.owner then self.owner.bar = nil end
end

function WeReadBar:rebuild()
    local old_bottom = self.bottom_dimen
    local old_top = self.top_dimen
    self:build()
    if old_bottom.h > self.bottom_h then
        -- 面板收起：底下的正文要重画
        UIManager:setDirty(self.ui, function() return "ui", old_bottom end)
    end
    UIManager:setDirty(self, function() return "ui", old_bottom:combine(self.bottom_dimen) end)
    UIManager:setDirty(self, function() return "ui", old_top end)
end

function WeReadBar:onTapOutside(_, ges)
    if ges.pos:intersectWith(self.top_dimen) or ges.pos:intersectWith(self.bottom_dimen) then
        return true
    end
    if self.panel then
        -- 有面板时第一下点空白先收起面板，更接近微信读书
        self.panel = nil
        self:rebuild()
        return true
    end
    self:onClose()
    return true
end

function WeReadBar:onSwipeOutside(_, ges)
    if ges.pos:intersectWith(self.bottom_dimen) or ges.pos:intersectWith(self.top_dimen) then
        return true
    end
    self:onClose()
    return true
end

function WeReadBar:onClose()
    UIManager:close(self)
    return true
end

-- 关闭浮层后再执行（避免叠在全屏弹窗下面）
function WeReadBar:closeThen(fn)
    UIManager:close(self)
    UIManager:nextTick(fn)
end

---------------------------------- 顶栏 ----------------------------------
function WeReadBar:buildTop()
    local h = px(120)
    local btn = px(110)
    local ui = self.ui
    local back = Tappable:new{
        width = btn + self.pad / 2, height = h, align = "left",
        content = HorizontalGroup:new{ HorizontalSpan:new{ width = px(24) }, icon("wr.back", 52) },
        callback = function()
            self:closeThen(function() ui:onHome() end)
        end,
    }
    local wrn = self:wereadNative()
    local bookmarked = ui.view.dogear_visible
    local bm
    if wrn then
        -- 微信读书云端书：书签存插件里（笔记与书签页可见），长按进「笔记与书签」
        bookmarked = wrn:shim():isBookmarked()
        bm = Tappable:new{
            width = btn, height = h,
            content = icon(bookmarked and "wr.bookmark.on" or "wr.bookmark", 48),
            callback = function()
                wrn:toggleBookmark()
                self:rebuild()
            end,
            hold_callback = function()
                self:closeThen(function()
                    local owner = wrn:owner()
                    owner.notes_from_toc = nil
                    owner:showNotes()
                end)
            end,
        }
    else
        bm = Tappable:new{
            width = btn, height = h,
            content = icon(bookmarked and "wr.bookmark.on" or "wr.bookmark", 48),
            callback = function()
                ui:handleEvent(Event:new("ToggleBookmark"))
                self:rebuild()
            end,
            hold_callback = function()
                self:closeThen(function() ui:handleEvent(Event:new("ShowBookmark")) end)
            end,
        }
    end
    local search = Tappable:new{
        width = btn, height = h,
        content = icon("wr.search", 48),
        callback = function()
            self:closeThen(function() ui:handleEvent(Event:new("ShowFulltextSearchInput")) end)
        end,
    }
    -- 微信读书云端书：书名取书架上的书名（章节 EPUB 自带的标题是章名），多一个「微信读书」操作单入口
    local more_btn
    if wrn then
        more_btn = Tappable:new{
            width = btn, height = h,
            content = icon("wr.list", 46),
            callback = function()
                self:closeThen(function()
                    local ok, err = pcall(function()
                        require("apps/filemanager/wereaderreader").showMore(wrn:owner(), { native = true })
                    end)
                    if not ok then require("logger").warn("wrnative showMore failed", err) end
                end)
            end,
        }
    end
    local title_w = self.sw - back.width - bm.width - search.width - (more_btn and more_btn.width or 0) - px(24)
    local props = ui.doc_props or {}
    local title_text = props.display_title or props.title
    if wrn then
        local ok, name = pcall(function() return wrn:shim().remote.book.title end)
        if ok and name and name ~= "" then title_text = name end
    end
    local title = TextWidget:new{
        text = clean_title(title_text),
        face = face(36), max_width = title_w,
    }
    local row = HorizontalGroup:new{
        align = "center",
        back,
        LeftContainer:new{ dimen = Geom:new{ w = title_w, h = h }, title },
        more_btn or HorizontalSpan:new{ width = 0 },
        search, bm,
        HorizontalSpan:new{ width = px(24) },
    }
    return VerticalGroup:new{ row, line(self.sw) }
end

---------------------------------- 底栏 ----------------------------------
function WeReadBar:buildBottom()
    local vg = VerticalGroup:new{ align = "left", line(self.sw) }
    if self.panel == "progress" then
        local wrn = self:wereadNative()
        table.insert(vg, wrn and self:buildWeReadProgressPanel(wrn) or self:buildProgressPanel())
        table.insert(vg, line(self.sw, px(1)))
    elseif self.panel == "light" then
        table.insert(vg, self:buildLightPanel())
        table.insert(vg, line(self.sw, px(1)))
    elseif self.panel == "font" then
        table.insert(vg, self:buildFontPanel())
        table.insert(vg, line(self.sw, px(1)))
    end
    table.insert(vg, self:buildTabs())
    return vg
end

function WeReadBar:buildTabs()
    local ui = self.ui
    local tabs = {
        { "wr.toc", "目录", function()
            local wrn = self:wereadNative()
            if wrn then
                -- 全书章节目录（插件页）；选章会走插件开书流程 → 换文档
                self:closeThen(function()
                    local ok, err = pcall(function() wrn:owner():showToc() end)
                    if not ok then require("logger").warn("wrnative showToc failed", err) end
                end)
                return
            end
            self:closeThen(function() ui:handleEvent(Event:new("ShowToc")) end)
        end },
        { "wr.progress", "进度", "progress" },
        { "wr.light", "亮度", "light" },
        { "wr.font", "字体", "font" },
        { "wr.more", "更多", function()
            self:closeThen(function() ui.menu:onShowMenu() end)
        end },
    }
    local h = px(170)
    local w = math.floor(self.sw / #tabs)
    local hg = HorizontalGroup:new{}
    for _, t in ipairs(tabs) do
        local selected = type(t[3]) == "string" and self.panel == t[3]
        local content = VerticalGroup:new{
            align = "center",
            icon(t[1], 56),
            VerticalSpan:new{ width = px(10) },
            TextWidget:new{ text = t[2], face = face(30, selected) },
            VerticalSpan:new{ width = px(8) },
            selected and line(px(56), px(5)) or VerticalSpan:new{ width = px(5) },
        }
        table.insert(hg, Tappable:new{
            width = w, height = h, content = content,
            callback = function()
                if type(t[3]) == "function" then
                    t[3]()
                else
                    self.panel = (self.panel ~= t[3]) and t[3] or nil
                    self:rebuild()
                end
            end,
        })
    end
    return hg
end

-- 行：左侧小标题 + 右侧内容
function WeReadBar:row(label, widget, h)
    local label_w = px(130)
    h = h or px(120)
    return HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = self.pad },
        LeftContainer:new{
            dimen = Geom:new{ w = label_w, h = h },
            TextWidget:new{ text = label, face = face(30), fgcolor = GRAY },
        },
        widget,
    }
end

function WeReadBar:innerWidth()
    return self.sw - 2 * self.pad - px(130)
end

---------------------------------- 阅读统计 + 自动翻页（进度面板底行） ----------------------------------
-- 自动翻页的统一入口：微信读书云端书用插件的（owner.auto_read），本机书用 ui.wrautoturn；都拿不到返回 nil
function WeReadBar:autoTurnState()
    local wrn = self:wereadNative()
    if wrn then
        local owner = wrn:owner()
        local ok, st = pcall(function()
            return {
                on = owner.auto_read and true or false,
                interval = owner:autoReadInterval(),
                toggle = function() owner:toggleAutoRead() end,
                set = function(n) return owner:setAutoReadInterval(n) end,
            }
        end)
        return ok and st or nil
    end
    local at = self.ui.wrautoturn
    if not at then return nil end
    return {
        on = at:isRunning(),
        interval = at:interval(),
        toggle = function() at:toggle() end,
        set = function(n) return at:setInterval(n) end,
    }
end

function WeReadBar:editAutoInterval(st)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = "自动翻页间隔（5–300 秒）",
        input = tostring(st.interval), input_type = "number",
        buttons = { {
            { text = "取消", callback = function() UIManager:close(dialog) end },
            { text = "确定", callback = function()
                local ok, saved = pcall(st.set, tonumber(dialog:getInputText()))
                if ok and saved then
                    UIManager:close(dialog)
                    Notification:notify("翻页间隔已保存", Notification.SOURCE_ALWAYS_SHOW)
                    if not self.closed then self:rebuild() end
                else
                    Notification:notify("请输入 5–300 之间的整数秒数", Notification.SOURCE_ALWAYS_SHOW)
                end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- 本机书：statistics 插件的内存统计（不碰数据库）：本书已读时长 + 按平均每页用时估的剩余时间
function WeReadBar:localStatsText()
    local ok, text = pcall(function()
        local st = self.ui.statistics
        if not (st and st.isEnabled and st:isEnabled()) then return nil end
        local read = (tonumber(st.book_read_time) or 0) + (tonumber(st.mem_read_time) or 0)
        local out = "已读 " .. fmt_duration(read)
        local pages = (tonumber(st.book_read_pages) or 0) + (tonumber(st.mem_read_pages) or 0)
        local avg = tonumber(st.avg_time)
        local total, cur = self.ui.document:getPageCount(), self.ui:getCurrentPage()
        if avg and avg == avg and avg > 0 and pages >= 5 and total > cur then
            out = out .. " · 预计还需 " .. fmt_duration(avg * (total - cur))
        end
        return out
    end)
    return ok and text or nil
end

-- 微信读书：插件缓存的阅读时长 + 笔记数；联网后异步刷新（回来时面板还开着就重画）
function WeReadBar:weReadStatsText(wrn)
    local ok, text = pcall(function()
        local owner, shim = wrn:owner(), wrn:shim()
        local data, count = owner:readingStats(shim)
        local seconds = tonumber(data.readingTime)
        if seconds then seconds = seconds + (tonumber(data.recordReadingTime) or 0) end
        local parts = {}
        if seconds then parts[#parts + 1] = "阅读 " .. math.floor(seconds / 60) .. " 分钟" end
        parts[#parts + 1] = (tonumber(count) or 0) .. " 条笔记"
        if not self.stats_requested then
            self.stats_requested = true
            pcall(function()
                owner:loadReadingStats(shim, owner.surface, function()
                    if not self.closed and self.panel == "progress" then self:rebuild() end
                end)
            end)
        end
        return table.concat(parts, " · ")
    end)
    return ok and text or nil
end

-- 进度面板底行：浅灰细线 + 左「统计」右「自动翻页」chip（点按开关，长按改间隔）
-- 左边线 = pad（与章节名 / 滑条上一章对齐），右边线 = sw - pad（与下一章 / 百分比对齐）
function WeReadBar:buildStatsRow(stats_text)
    local st = self:autoTurnState()
    if not stats_text and not st then return VerticalSpan:new{ width = px(20) } end
    local inner = self.sw - 2 * self.pad
    local row_h = px(76)
    local chip_w = px(290)
    local row = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = self.pad } }
    local left_w = inner - (st and chip_w or 0)
    table.insert(row, LeftContainer:new{
        dimen = Geom:new{ w = left_w, h = row_h },
        stats_text and TextWidget:new{ text = stats_text, face = face(28), fgcolor = GRAY, max_width = left_w - px(16) }
            or HorizontalSpan:new{ width = 0 },
    })
    if st then
        local label = st.on and string.format("自动翻页 %d 秒", st.interval) or "自动翻页 关"
        local auto = chip(label, chip_w, px(64), st.on, function()
            local was_on = st.on
            local ok, err = pcall(st.toggle)
            if not ok then
                require("logger").warn("autoturn toggle failed", err)
                return
            end
            if was_on then
                self:rebuild()
            else
                -- 工具栏开着时翻页 tick 会一直等：开启后收掉工具栏
                UIManager:close(self)
            end
        end, 28)
        auto.hold_callback = function() self:editAutoInterval(st) end
        table.insert(row, auto)
    end
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = px(12) },
        HorizontalGroup:new{ HorizontalSpan:new{ width = self.pad }, line(inner, px(2), LIGHT) },
        VerticalSpan:new{ width = px(6) },
        row,
        VerticalSpan:new{ width = px(10) },
    }
end

---------------------------------- 微信读书云端书 ----------------------------------
-- 影子挂在这个 ReaderUI 上（微信读书云端书用原生阅读页）时返回桥接模块，否则 nil；本机书走原来的逻辑一字不改
function WeReadBar:wereadNative()
    local m = self.ui.wrnative
    if m and m:active() then return m end
end

-- 进度面板（全书口径）：页码 = 按字数估算的全书页码；点进度条 → 插件的全书跳转（可能跨章 → 换文档）
function WeReadBar:buildWeReadProgressPanel(wrn)
    local shim, owner = wrn:shim(), wrn:owner()
    local P = require("wereader/pagination")
    local ok, page, total, estimated = pcall(P.position, shim)
    if not ok then page, total, estimated = 1, 1, false end
    local chapter = clean_title(shim:chapter())

    local inner = self.sw - 2 * self.pad
    local side_w = px(170)
    local bar_w = inner - 2 * side_w
    self.progress_bar = Slider:new{
        width = bar_w, height = px(110),
        percentage = (page - 1) / math.max(1, total - 1),
    }
    local bar_tap = Tappable:new{
        width = bar_w, height = px(110), content = self.progress_bar,
    }
    bar_tap.onTap = function(_, _, ges)
        local pct = self.progress_bar:getPercentageFromPosition(ges.pos)
        if pct then
            -- jumpBookProgress(value) 的 value 是 0~100 的百分比（P.target 里按总页数折算）
            self:closeThen(function()
                local okj, err = pcall(function() owner:jumpBookProgress(pct * 100) end)
                if not okj then require("logger").warn("wrnative jumpBookProgress failed", err) end
            end)
        end
        return true
    end
    local function chapter_step(delta)
        self:closeThen(function()
            local okc, err = pcall(function() owner:changeChapter(delta) end)
            if not okc then require("logger").warn("wrnative changeChapter failed", err) end
        end)
    end
    local prev_ch = Tappable:new{
        width = side_w, height = px(110), align = "left",
        content = TextWidget:new{ text = "上一章", face = face(32) },
        callback = function() chapter_step(-1) end,
    }
    local next_ch = Tappable:new{
        width = side_w, height = px(110), align = "right",
        content = TextWidget:new{ text = "下一章", face = face(32) },
        callback = function() chapter_step(1) end,
    }
    local pct_text = string.format("%s%d / %d   %.1f%%", estimated and "约 " or "", page, total, page * 100 / total)
    local info = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = inner - px(340), h = px(70) },
            TextWidget:new{ text = chapter, face = face(34, true), max_width = inner - px(360) },
        },
        RightContainer:new{
            dimen = Geom:new{ w = px(340), h = px(70) },
            TextWidget:new{ text = pct_text, face = face(28), fgcolor = GRAY },
        },
    }
    -- 「输入页码」「回到第 N 页」跨章没有对应的原生实现，这类书不提供
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = px(26) },
        HorizontalGroup:new{ HorizontalSpan:new{ width = self.pad }, info },
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = self.pad }, prev_ch, bar_tap, next_ch,
        },
        self:buildStatsRow(self:weReadStatsText(wrn)),
    }
end

---------------------------------- 进度面板 ----------------------------------
function WeReadBar:buildProgressPanel()
    local ui = self.ui
    local page = ui:getCurrentPage()
    local total = ui.document:getPageCount()
    local chapter = ui.toc:getTocTitleByPage(page)
    if chapter == "" then chapter = clean_title(ui.doc_props and ui.doc_props.display_title) end

    local inner = self.sw - 2 * self.pad
    local side_w = px(170)
    local bar_w = inner - 2 * side_w
    self.progress_bar = Slider:new{
        width = bar_w, height = px(110),
        percentage = (page - 1) / math.max(1, total - 1),
    }
    local function goto_page(p)
        if not p then return end
        p = math.max(1, math.min(total, p))
        if not self.orig_page then
            self.orig_page = page
            ui.link:addCurrentLocationToStack()
        end
        ui:handleEvent(Event:new("GotoPage", p))
        self:rebuild()
    end
    local bar_tap = Tappable:new{
        width = bar_w, height = px(110), content = self.progress_bar,
    }
    bar_tap.onTap = function(_, _, ges)
        local pct = self.progress_bar:getPercentageFromPosition(ges.pos)
        if pct then goto_page(1 + math.floor(pct * (total - 1) + 0.5)) end
        return true
    end
    local prev_ch = Tappable:new{
        width = side_w, height = px(110), align = "left",
        content = TextWidget:new{ text = "上一章", face = face(32) },
        callback = function() goto_page(ui.toc:getPreviousChapter(page) or 1) end,
    }
    local next_ch = Tappable:new{
        width = side_w, height = px(110), align = "right",
        content = TextWidget:new{ text = "下一章", face = face(32) },
        callback = function() goto_page(ui.toc:getNextChapter(page) or total) end,
    }
    local pct_text = string.format("%d / %d   %.1f%%", page, total, page * 100 / total)
    local info = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = inner - px(300), h = px(70) },
            TextWidget:new{ text = chapter, face = face(34, true), max_width = inner - px(320) },
        },
        RightContainer:new{
            dimen = Geom:new{ w = px(300), h = px(70) },
            TextWidget:new{ text = pct_text, face = face(28), fgcolor = GRAY },
        },
    }
    local rows = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = px(26) },
        HorizontalGroup:new{ HorizontalSpan:new{ width = self.pad }, info },
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = self.pad }, prev_ch, bar_tap, next_ch,
        },
    }
    -- 底行：回到原页（跳转过才出现）+ 输入页码
    local actions = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = self.pad } }
    if self.orig_page and self.orig_page ~= page then
        local orig = self.orig_page
        table.insert(actions, chip(string.format("回到第 %d 页", orig), px(300), px(76), false, function()
            self.orig_page = nil
            ui:handleEvent(Event:new("GotoPage", orig))
            self:rebuild()
        end, 28))
        table.insert(actions, HorizontalSpan:new{ width = px(20) })
    end
    table.insert(actions, chip("输入页码", px(220), px(76), false, function()
        self:closeThen(function() ui.gotopage:onShowGotoDialog() end)
    end, 28))
    table.insert(rows, actions)
    table.insert(rows, self:buildStatsRow(self:localStatsText()))
    return rows
end

---------------------------------- 亮度面板 ----------------------------------
function WeReadBar:buildLightPanel()
    local ui = self.ui
    local Light = require("ui/wereadlight")
    local inner = self.sw - 2 * self.pad
    local rows = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = px(20) } }
    -- 一行开关：灯光 /（Kindle）自动 / 夜间。夜间就是原来的「背景 白天|夜间」，一个开关就够
    local night = G_reader_settings:isTrue("night_mode")
    local switches = HorizontalGroup:new{ align = "center" }
    local function add_switch(label, checked, callback)
        if #switches > 0 then table.insert(switches, HorizontalSpan:new{ width = px(96) }) end
        table.insert(switches, Kit.switchItem(label, checked, callback))
    end
    if Device:hasFrontlight() then
        local is_on = Light.isOn()
        add_switch("灯光", is_on, function() Light.setOn(not is_on); self:rebuild() end)
        if Light.autoSupported() then
            local auto = Light.autoOn()
            add_switch("自动", auto, function() Light.setAuto(not auto); self:rebuild() end)
        end
    end
    add_switch("夜间", night, function()
        ui:handleEvent(Event:new("ToggleNightMode"))
        self:rebuild()
    end)
    -- 开关整组水平居中
    table.insert(rows, require("ui/widget/container/centercontainer"):new{
        dimen = Geom:new{ w = self.sw, h = px(100) },
        switches,
    })
    if Device:hasFrontlight() then
        -- 十档条：亮度两侧是 − / +，色温两侧是「冷 / 暖」
        local steps = Light.STEPS
        local btn_w = px(110)
        local gap = px(8)
        local seg_area = inner - 2 * btn_w - 2 * px(20)
        local seg_w = math.floor((seg_area - gap * (steps - 1)) / steps)
        local FrameContainer = require("ui/widget/container/framecontainer")
        local function seg_row(level, set, left, right)
            local segs = HorizontalGroup:new{ align = "center" }
            for i = 1, steps do
                local on = i <= level
                table.insert(segs, Tappable:new{
                    width = seg_w, height = px(110),
                    content = FrameContainer:new{
                        width = seg_w, height = px(44), padding = 0, margin = 0,
                        bordersize = px(2), color = on and BLACK or GRAY,
                        background = on and BLACK or WHITE,
                        VerticalSpan:new{ width = 0 },
                    },
                    callback = function() set(i == level and i - 1 or i) end,
                })
                if i < steps then table.insert(segs, HorizontalSpan:new{ width = gap }) end
            end
            return HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = self.pad },
                Tappable:new{ width = btn_w, height = px(110), content = left,
                    callback = function() set(level - 1) end },
                HorizontalSpan:new{ width = px(20) },
                segs,
                HorizontalSpan:new{ width = px(20) },
                Tappable:new{ width = btn_w, height = px(110), content = right,
                    callback = function() set(level + 1) end },
            }
        end
        table.insert(rows, seg_row(Light.level(), function(l) Light.setLevel(l); self:rebuild() end,
            icon("wr.minus", 44), icon("wr.plus", 44)))
        if Light.warmthSupported() then
            table.insert(rows, seg_row(Light.warmthLevel(), function(l) Light.setWarmthLevel(l); self:rebuild() end,
                TextWidget:new{ text = "冷", face = face(30), fgcolor = GRAY },
                TextWidget:new{ text = "暖", face = face(30), fgcolor = GRAY }))
        end
    end
    table.insert(rows, VerticalSpan:new{ width = px(16) })
    return rows
end

---------------------------------- 字体面板 ----------------------------------
local FONT_CHOICES = {
    { "LXGW WenKai", "文楷" },
    { "Source Han Serif CN", "思源宋体" },
    { "Source Han Sans CN", "思源黑体" },
    { "TsangerJinKai03-6763", "仓耳今楷" },
}
local FONT_NAMES = {
    ["LXGW WenKai"] = "霞鹜文楷", ["Source Han Serif CN"] = "思源宋体",
    ["Source Han Sans CN"] = "思源黑体", ["TsangerJinKai03-6763"] = "仓耳今楷",
    ["TsangerYunHei"] = "仓耳云黑", ["FZYouSongJS"] = "方正悠宋",
    ["FZFangSong-Z02S"] = "方正仿宋", ["HYQiHei"] = "汉仪旗黑",
    ["FZYouH"] = "方正悠黑", ["FZZJ-ZSXKJW"] = "方正字迹",
    ["HanziPen SC"] = "翩翩体", ["ETrump KaiTi"] = "楷体",
    ["ETrump ShuSongEr"] = "书宋", ["ETrump XLS"] = "小隶书",
    ["ETrump YouYuan"] = "幼圆", ["ETrump ZhongHei"] = "中黑",
    ["Noto Sans CJK SC"] = "Noto 黑体",
}
local LINE_SPACES = { { 100, "紧凑" }, { 115, "标准" }, { 130, "宽松" } }
local MARGINS = { { 10, "窄" }, { 25, "标准" }, { 45, "宽" } }
-- 首行缩进 / 段间距：全局设置，nil = 跟随原书（默认，不改变任何书现在的样子）
local INDENT_CHOICES = { { "book", "原书" }, { "on", "开" }, { "off", "关" } }
local SPACING_CHOICES = { { "book", "原书" }, { 0, "无" }, { 0.5, "小" }, { 1.0, "大" } } -- 段后 em

local function closest(list, v)
    local best, bd = 1, math.huge
    for i, it in ipairs(list) do
        local d = math.abs(it[1] - v)
        if d < bd then best, bd = i, d end
    end
    return best
end

function WeReadBar:buildFontPanel()
    local ui = self.ui
    local inner = self:innerWidth()
    local rows = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = px(14) } }
    local conf = ui.document.configurable

    -- 字号
    local size = conf.font_size or 22
    local bw = px(200)
    local size_row = HorizontalGroup:new{
        align = "center",
        chip("A-", bw, px(80), false, function()
            ui:handleEvent(Event:new("ChangeSize", -1)); self:rebuild()
        end, 32),
        CenterContainer:new{
            dimen = Geom:new{ w = inner - 2 * bw, h = px(80) },
            TextWidget:new{ text = tostring(size), face = face(40, true) },
        },
        chip("A+", bw, px(80), false, function()
            ui:handleEvent(Event:new("ChangeSize", 1)); self:rebuild()
        end, 32),
    }
    table.insert(rows, self:row("字号", size_row))

    -- 字体：4 个常用 + 更多
    local cur_font = ui.font.font_face or conf.font_face or ""
    local n = #FONT_CHOICES + 1
    local gap = px(14)
    local cws = fit(n, gap, inner)
    local font_row = HorizontalGroup:new{ align = "center" }
    local in_list = false
    for i, f in ipairs(FONT_CHOICES) do
        if f[1] == cur_font then in_list = true end
        table.insert(font_row, chip(f[2], cws[i], px(80), f[1] == cur_font, function()
            ui:handleEvent(Event:new("SetFont", f[1])); self:rebuild()
        end, 28))
        table.insert(font_row, HorizontalSpan:new{ width = gap })
    end
    table.insert(font_row, chip(in_list and "更多 ›" or (FONT_NAMES[cur_font] or "更多 ›"),
        cws[n], px(80), not in_list, function() self:showFontList() end, 28))
    table.insert(rows, self:row("字体", font_row))

    -- 行距 / 边距：三档
    -- 一行等宽 chip（3 / 4 个），sel = 选中项下标；宽度用 fit 铺满 inner，与字号 / 字体行左右边线一致
    local function choices(list, sel, on_pick)
        local g = px(24)
        local ws = fit(#list, g, inner)
        local hg = HorizontalGroup:new{ align = "center" }
        for i, it in ipairs(list) do
            table.insert(hg, chip(it[2], ws[i], px(80), i == sel, function() on_pick(it[1]) end, 30))
            if i < #list then table.insert(hg, HorizontalSpan:new{ width = g }) end
        end
        return hg
    end
    local function three(list, cur_v, on_pick)
        return choices(list, closest(list, cur_v), on_pick)
    end
    table.insert(rows, self:row("行距", three(LINE_SPACES, conf.line_spacing or 115, function(v)
        ui:handleEvent(Event:new("SetLineSpace", v)); self:rebuild()
    end)))
    local h_margin = (conf.h_page_margins and conf.h_page_margins[1]) or 15
    table.insert(rows, self:row("边距", three(MARGINS, h_margin, function(v)
        -- ReaderTypeset 不回写 configurable，选中态和退出保存都靠这里写（与 ConfigDialog 一致）
        conf.h_page_margins = { v, v }
        ui:handleEvent(Event:new("SetPageHorizMargins", { v, v }))
        self:rebuild()
    end)))

    if ui.styletweak then
        -- 首行缩进：原书 / 开 / 关（写全局设置 → 重新交样式表给 crengine → 重排）
        local function apply_format()
            ui.styletweak:applyIReaderFormat()
            self:rebuild()
        end
        local indent = G_reader_settings:readSetting("ireader_first_line_indent")
        table.insert(rows, self:row("缩进", choices(INDENT_CHOICES,
            indent == nil and 1 or (indent and 2 or 3), function(v)
                if v == "book" then
                    G_reader_settings:delSetting("ireader_first_line_indent")
                else
                    G_reader_settings:saveSetting("ireader_first_line_indent", v == "on")
                end
                apply_format()
            end)))

        -- 段间距：原书 / 无 / 小 / 大（段后 0 / 0.5 / 1em）
        local spacing = tonumber(G_reader_settings:readSetting("ireader_para_spacing"))
        local spacing_sel = 1
        if spacing ~= nil then
            local best = math.huge
            for i = 2, #SPACING_CHOICES do
                local d = math.abs(SPACING_CHOICES[i][1] - spacing)
                if d < best then spacing_sel, best = i, d end
            end
        end
        table.insert(rows, self:row("段距", choices(SPACING_CHOICES, spacing_sel, function(v)
            if v == "book" then
                G_reader_settings:delSetting("ireader_para_spacing")
            else
                G_reader_settings:saveSetting("ireader_para_spacing", v)
            end
            apply_format()
        end)))
    end

    -- 更多排版
    table.insert(rows, HorizontalGroup:new{
        HorizontalSpan:new{ width = self.pad },
        Tappable:new{
            width = self.sw - 2 * self.pad, height = px(90), align = "left",
            content = TextWidget:new{ text = "更多排版设置 ›", face = face(30), fgcolor = GRAY },
            callback = function()
                self:closeThen(function() ui.config:onShowConfigMenu() end)
            end,
        },
    })
    return rows
end

function WeReadBar:showFontList()
    local ui = self.ui
    local cre = require("document/credocument"):engineInit()
    local faces = cre.getFontFaces()
    local cur = ui.font.font_face
    local items = {}
    -- 中文字体（有中文名的）排前面
    local cn, other = {}, {}
    for _, f in ipairs(faces) do
        if FONT_NAMES[f] then table.insert(cn, f) else table.insert(other, f) end
    end
    for _, list in ipairs({ cn, other }) do
        for _, f in ipairs(list) do
            table.insert(items, {
                text = (FONT_NAMES[f] and (FONT_NAMES[f] .. "  ·  " .. f) or f),
                bold = f == cur,
                callback = function()
                    ui:handleEvent(Event:new("SetFont", f))
                end,
            })
        end
    end
    local Menu = require("ui/widget/menu")
    local menu
    menu = Menu:new{
        title = "选择字体",
        item_table = items,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            item.callback()
        end,
    }
    self:closeThen(function() UIManager:show(menu) end)
end

--------------------------------------------------------------------------
-- 阅读器模块：持有浮层
--------------------------------------------------------------------------
local ReaderWeRead = WidgetContainer:extend{
    name = "wereadbar",
}

function ReaderWeRead:show(panel)
    if self.bar then
        UIManager:close(self.bar)
        self.bar = nil
        return true
    end
    self.ui.keyselection:stopHighlightIndicator(true)
    self.bar = WeReadBar:new{ ui = self.ui, owner = self, panel = panel }
    UIManager:show(self.bar)
    return true
end

function ReaderWeRead:onCloseWidget()
    if self.bar then UIManager:close(self.bar) end
end

-- 供手势/派发器调用
function ReaderWeRead:onShowWeReadBar()
    return self:show()
end

return ReaderWeRead

--[[--
iReader: 书籍详情页（替代 KOReader 的「键：值」书籍信息表）。

    ‹ 返回 | 书籍详情                              全部信息 ›
    [封面]  书名
            作者
            EPUB · 0.9 MB · 741 页
            ━━━━━━━━──────  读到 23%
            [ 继续阅读 ]  [ 加入书单 ]
    ─────────────
    简介（最多 8 行，点按看全文）
    ─────────────
    信息：语言 / 丛书 / 关键词 / 文件 / 修改日期
    ─────────────
    我的评价：★★★☆☆  评语…（点按编辑）

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Kit = require("ui/wereadkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local Screen = Device.screen

local px, face = Kit.px, Kit.face
local GRAY = Kit.GRAY

local Detail = InputContainer:extend{
    covers_fullscreen = true,
    -- 由 BookInfo:show 传入
    bookinfo = nil, file = nil, book_props = nil, attr = nil,
    doc_settings_or_file = nil, summary = nil, is_current_doc = false,
}

local function band(w)
    return LineWidget:new{ background = Blitbuffer.COLOR_GRAY_D, dimen = Geom:new{ w = w, h = px(8) } }
end

local function sectionTitle(text, pad)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = pad },
        TextWidget:new{ text = text, face = face(30, true) },
    }
end

function Detail:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:build()
end

function Detail:build()
    local sw, pad = self.sw, px(44)
    local inner = sw - 2 * pad
    local file, props = self.file, self.book_props or {}
    local Shelf = require("apps/filemanager/wereadshelf")
    local _, _, cover_bb, cw, ch = Shelf.bookMeta(file)
    local title = Kit.clean_title(props.display_title or props.title or (file:match("([^/]+)$") or file))
    local authors = props.authors and props.authors:gsub("\n", "、") or nil
    local pct, status = Shelf.percent(file)

    local vg = VerticalGroup:new{ align = "left" }

    -- 顶部导航：返回 | 书籍详情 ……… 全部信息 ›
    local nav = Kit.NavRow:new{ width = sw }
    nav:set("书籍详情", function() self:onClose() end)
    local all_info = Kit.Tappable:new{
        width = px(200), height = nav.height, align = "right",
        content = TextWidget:new{ text = "全部信息 ›", face = face(28), fgcolor = GRAY },
        callback = function()
            UIManager:show(self.bookinfo.kvp_widget)
        end,
    }
    table.insert(vg, require("ui/widget/overlapgroup"):new{
        dimen = Geom:new{ w = sw, h = nav.height },
        nav,
        RightContainer:new{ dimen = Geom:new{ w = sw - px(32), h = nav.height - px(2) }, all_info },
    })

    -- 头部：大封面 + 书名信息
    local cover_w, cover_h = px(250), px(360)
    local cover
    if cover_bb then
        local img = ImageWidget:new{ image = cover_bb, scale_factor = math.min(cover_w / cw, cover_h / ch) }
        img:_render()
        local s = img:getSize()
        cover = FrameContainer:new{ width = s.w + 2, height = s.h + 2, padding = 0, margin = 0, bordersize = 1, img }
    else
        cover = FrameContainer:new{
            width = cover_w, height = cover_h, padding = px(14), margin = 0, bordersize = px(2),
            CenterContainer:new{
                dimen = Geom:new{ w = cover_w - px(32), h = cover_h - px(32) },
                TextBoxWidget:new{ text = title, face = face(30, true), width = cover_w - px(32), alignment = "center" },
            },
        }
    end
    if self.attr then
        cover = Kit.Tappable:new{
            width = cover:getSize().w, height = cover:getSize().h, content = cover,
            callback = function() self.bookinfo:onShowBookCover(file) end,
        }
    end

    local text_w = inner - cover_w - px(40)
    local meta = {}
    if self.attr then
        table.insert(meta, ((file:match("%.([^.]+)$") or ""):upper()))
        table.insert(meta, util.getFriendlySize(self.attr.size or 0))
    end
    if props.pages then table.insert(meta, props.pages .. " 页") end

    -- 进度条
    local bar_w = text_w
    local Widget = require("ui/widget/widget")
    local Bar = Widget:extend{}
    function Bar:getSize() return Geom:new{ w = bar_w, h = px(12) } end
    function Bar:paintTo(bb, x, y)
        bb:paintRect(x, y + px(4), bar_w, px(4), Blitbuffer.COLOR_GRAY_9)
        if pct then bb:paintRect(x, y + px(2), math.floor(bar_w * math.min(1, pct)), px(8), Blitbuffer.COLOR_BLACK) end
    end

    local primary_text = self.is_current_doc and "返回阅读" or (pct and "继续阅读" or "开始阅读")
    local btn_w = math.floor((text_w - px(20)) / 2)
    local buttons = HorizontalGroup:new{
        Kit.chip(primary_text, btn_w, px(84), true, function() self:openBook() end, 30),
        HorizontalSpan:new{ width = px(20) },
    }
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.collections and self.attr then
        table.insert(buttons, Kit.chip("加入书单", btn_w, px(84), false,
            fm.collections:genAddToCollectionButton(file).callback, 30))
    end

    local info_col = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = title, face = face(42, true), width = text_w,
            height = px(170), height_adjust = true, height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = px(10) },
        TextWidget:new{ text = authors or "佚名", face = face(30), fgcolor = GRAY, max_width = text_w },
        VerticalSpan:new{ width = px(10) },
        TextWidget:new{ text = table.concat(meta, " · "), face = face(26), fgcolor = GRAY, max_width = text_w },
        VerticalSpan:new{ width = px(26) },
        Bar:new{},
        VerticalSpan:new{ width = px(10) },
        TextWidget:new{ text = Shelf.progressText(pct, status), face = face(26) },
        VerticalSpan:new{ width = px(26) },
        buttons,
    }
    table.insert(vg, VerticalSpan:new{ width = px(30) })
    table.insert(vg, HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width = pad },
        cover,
        HorizontalSpan:new{ width = px(40) },
        info_col,
    })
    table.insert(vg, VerticalSpan:new{ width = px(34) })

    local used = vg:getSize().h
    local remaining = self.sh - used

    -- 我的评价（放最后，先算高度）
    local summary = self.summary or {}
    local rating = require("ui/widget/booklist").getBookRatingString(summary.rating or 0)
    local review_block = VerticalGroup:new{
        align = "left",
        band(sw),
        VerticalSpan:new{ width = px(20) },
        Kit.Tappable:new{
            width = sw, height = px(90), align = "left",
            content = HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = pad },
                TextWidget:new{ text = "我的评价", face = face(30, true) },
                HorizontalSpan:new{ width = px(30) },
                TextWidget:new{ text = rating, face = face(32) },
                HorizontalSpan:new{ width = px(24) },
                TextWidget:new{
                    text = (summary.note and summary.note ~= "") and summary.note or "点按写评价",
                    face = face(26), fgcolor = GRAY, max_width = inner - px(420),
                },
            },
            callback = self.attr and function()
                self.bookinfo:editSummary(self.doc_settings_or_file, self.book_props)
            end or nil,
        },
    }
    remaining = remaining - review_block:getSize().h

    -- 信息
    local rows = {}
    local function addRow(k, v, cb)
        if v and v ~= "" then table.insert(rows, { k, v, cb }) end
    end
    if props.series then
        addRow("丛书", props.series .. (props.series_index and (" #" .. props.series_index) or ""))
    end
    local LANGS = { zh = "中文", ["zh-cn"] = "简体中文", ["zh-hans"] = "简体中文", ["zh-tw"] = "繁体中文",
        ["zh-hant"] = "繁体中文", en = "英文", ["en-us"] = "英文", ["en-gb"] = "英文", ja = "日文", ko = "韩文",
        fr = "法文", de = "德文", es = "西班牙文", ru = "俄文" }
    addRow("语言", props.language and (LANGS[props.language:lower()] or props.language) or nil)
    addRow("关键词", props.keywords and props.keywords:gsub("\n", "、") or nil)
    addRow("文件", file:match("([^/]+)$"))
    if self.attr then addRow("修改日期", os.date("%Y-%m-%d %H:%M", self.attr.modification)) end
    local info_block = VerticalGroup:new{ align = "left", band(sw), VerticalSpan:new{ width = px(20) },
        sectionTitle("信息", pad), VerticalSpan:new{ width = px(10) } }
    for _, r in ipairs(rows) do
        table.insert(info_block, HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            LeftContainer:new{
                dimen = Geom:new{ w = px(170), h = px(56) },
                TextWidget:new{ text = r[1], face = face(26), fgcolor = GRAY },
            },
            TextWidget:new{ text = r[2], face = face(26), max_width = inner - px(170) },
        })
    end
    table.insert(info_block, VerticalSpan:new{ width = px(16) })
    remaining = remaining - info_block:getSize().h

    -- 简介：用剩余空间，超出省略，点按看全文
    local desc = props.description and util.htmlToPlainTextIfHtml(props.description) or nil
    if desc and desc ~= "" and remaining > px(200) then
        local desc_h = remaining - px(20) - px(60) - px(30)
        local desc_block = VerticalGroup:new{
            align = "left",
            band(sw),
            VerticalSpan:new{ width = px(20) },
            sectionTitle("简介", pad),
            VerticalSpan:new{ width = px(10) },
            Kit.Tappable:new{
                width = sw, height = desc_h, align = "left",
                content = HorizontalGroup:new{
                    HorizontalSpan:new{ width = pad },
                    TextBoxWidget:new{
                        text = desc, face = face(28), width = inner,
                        height = desc_h, height_adjust = true, height_overflow_show_ellipsis = true,
                    },
                },
                callback = function() self.bookinfo:showBookProp("description", desc) end,
            },
            VerticalSpan:new{ width = px(30) },
        }
        table.insert(vg, desc_block)
    end
    table.insert(vg, info_block)
    table.insert(vg, review_block)
    vg:resetLayout() -- 前面量过高度，追加内容后要重算偏移

    self[1] = FrameContainer:new{
        width = sw, height = self.sh, padding = 0, margin = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        vg,
    }
end

function Detail:openBook()
    local file = self.file
    self:onClose()
    if self.is_current_doc then return end
    UIManager:nextTick(function()
        local ReaderUI = require("apps/reader/readerui")
        if ReaderUI.instance then
            ReaderUI.instance:switchDocument(file)
        else
            local fm = require("apps/filemanager/filemanager").instance
            if fm then fm:openFile(file) else ReaderUI:showReader(file) end
        end
    end)
end

function Detail:paintTo(bb, x, y)
    local ok, err = pcall(InputContainer.paintTo, self, bb, x, y)
    if not ok then require("logger").warn("weread detail paint failed:", err) end
end

function Detail:onShow()
    UIManager:setDirty(self, "ui")
end

function Detail:onCloseWidget()
    if self.bookinfo then
        self.bookinfo.detail_widget = nil
        if self.bookinfo.kvp_widget and self.bookinfo.kvp_widget.close_callback then
            self.bookinfo.kvp_widget.close_callback()
        end
    end
    UIManager:setDirty(nil, "ui")
end

function Detail:onClose()
    UIManager:close(self)
    return true
end

return Detail

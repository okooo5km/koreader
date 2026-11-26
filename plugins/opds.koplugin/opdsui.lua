--[[--
iReader: 书库页的导航行与宫格卡片。

- NavRow：页头下方一行「‹ 返回   当前目录名」，固定高度，随浏览位置更新
- Tiles：导航类条目（字母排序、热门、作者……）与书库列表画成 2 列图标卡片

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Kit = require("ui/wereadkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen

local px, face = Kit.px, Kit.face

local UI = {}

---------------------------------------------------------------- 导航行（复用 Kit.NavRow，顶部多一条细线与页头分开）
function UI.newNavRow()
    return Kit.NavRow:new{}
end

---------------------------------------------------------------- 分类图标
local ICON_RULES = {
    { "字母", "az" }, { "alphabet", "az" }, { "title", "az" },
    { "热门", "fire" }, { "hot", "fire" }, { "popular", "fire" },
    { "评分", "star" }, { "rated", "star" }, { "rating", "star" },
    { "最近", "clock" }, { "最新", "clock" }, { "recent", "clock" }, { "new", "clock" }, { "latest", "clock" },
    { "随机", "shuffle" }, { "random", "shuffle" }, { "discover", "shuffle" },
    { "未读", "circle" }, { "unread", "circle" },
    { "已读", "check" }, { "read", "check" },
    { "作者", "person" }, { "author", "person" },
    { "出版", "building" }, { "publisher", "building" },
    { "分类", "tag" }, { "标签", "tag" }, { "categor", "tag" }, { "tag", "tag" }, { "genre", "tag" },
    { "丛书", "stack" }, { "系列", "stack" }, { "series", "stack" },
    { "语言", "globe" }, { "language", "globe" },
    { "格式", "file" }, { "format", "file" },
    { "书架", "shelf" }, { "shel", "shelf" },
    { "下载", "download" }, { "download", "download" },
}

function UI.iconFor(text)
    local t = (text or ""):lower()
    for _, r in ipairs(ICON_RULES) do
        if t:find(r[1], 1, true) then return "wr.cat." .. r[2] end
    end
    return "wr.cat.folder"
end

---------------------------------------------------------------- 卡片
local Tile = InputContainer:extend{ entry = nil, menu = nil, width = nil, height = nil }

function Tile:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    local GestureRange = require("ui/gesturerange")
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Hold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
    local e = self.entry
    local label = e.tile_title or e.text or ""
    local sub = e.tile_sub
    local inner_w = self.width - px(4) - px(28) - px(56) - px(22)
    local texts = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = label, face = face(32, true), max_width = inner_w },
    }
    if sub and sub ~= "" then
        table.insert(texts, VerticalSpan:new{ width = px(6) })
        table.insert(texts, TextWidget:new{
            text = sub, face = face(24), fgcolor = Blitbuffer.COLOR_GRAY_5, max_width = inner_w,
        })
    end
    self[1] = FrameContainer:new{
        width = self.width, height = self.height,
        bordersize = px(2), radius = px(14), padding = 0, margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        LeftContainer:new{
            dimen = Geom:new{ w = self.width - px(4), h = self.height - px(4) },
            HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = px(28) },
                Kit.icon(e.tile_icon or UI.iconFor(label), 56),
                HorizontalSpan:new{ width = px(22) },
                texts,
            },
        },
    }
end

function Tile:onTap()
    if self.entry.tile_callback then
        self.entry.tile_callback()
    else
        self.menu:onMenuSelect(self.entry)
    end
    return true
end

function Tile:onHold()
    if not self.entry.tile_callback then self.menu:onMenuHold(self.entry) end
    return true
end

---------------------------------------------------------------- 整页布局（替代 Menu:updateItems）
local COLS = 2

function UI.tileRows(menu)
    local top_h = menu.title_bar:getHeight()
    local bottom_h = math.max(menu.page_return_arrow:getSize().h, menu.page_info_text:getSize().h)
        + Size.padding.button
    local avail_h = menu.inner_dimen.h - top_h - bottom_h
    local tile_h = px(150)
    local gap = px(22)
    local rows = math.max(1, math.floor((avail_h - gap) / (tile_h + gap)))
    return rows, tile_h, gap
end

function UI.updateTiles(menu, select_number, extra_items)
    local old_dimen = menu.dimen and menu.dimen:copy()
    menu.layout = {}
    menu.item_group:clear()
    menu.page_info:resetLayout()
    menu.return_button:resetLayout()
    menu.content_group:resetLayout()

    -- 条目 + 额外卡片（如「添加书库」）
    local items = {}
    for _, it in ipairs(menu.item_table) do table.insert(items, it) end
    for _, it in ipairs(extra_items or {}) do table.insert(items, it) end

    local rows, tile_h, gap = UI.tileRows(menu)
    menu.perpage = rows * COLS
    menu.page_num = math.max(1, math.ceil(#items / menu.perpage))
    if menu.page > menu.page_num then menu.page = menu.page_num end
    if menu.page < 1 then menu.page = 1 end

    local side = px(30)
    local tile_w = math.floor((menu.inner_dimen.w - 2 * side - (COLS - 1) * gap) / COLS)
    local offset = (menu.page - 1) * menu.perpage
    local row, line_layout
    table.insert(menu.item_group, VerticalSpan:new{ width = gap })
    for i = 1, menu.perpage do
        local index = offset + i
        local entry = items[index]
        if not entry then break end
        if index <= #menu.item_table then entry.idx = index end
        if (i - 1) % COLS == 0 then
            if line_layout then table.insert(menu.layout, line_layout) end
            line_layout = {}
            row = HorizontalGroup:new{ HorizontalSpan:new{ width = side } }
            table.insert(menu.item_group, LeftContainer:new{
                dimen = Geom:new{ w = menu.inner_dimen.w, h = tile_h }, row,
            })
            table.insert(menu.item_group, VerticalSpan:new{ width = gap })
        else
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        local tile = Tile:new{ entry = entry, menu = menu, width = tile_w, height = tile_h }
        table.insert(row, tile)
        table.insert(line_layout, tile)
    end
    if line_layout then table.insert(menu.layout, line_layout) end

    menu:updatePageInfo(select_number)
    menu:mergeTitleBarIntoLayout()
    UIManager:setDirty(menu.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(menu.dimen) or menu.dimen
    end)
end

return UI

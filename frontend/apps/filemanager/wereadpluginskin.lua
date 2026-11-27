--[[--
给开源 weread.koplugin（finlater，AGPL-3.0，随包放在 plugins/weread.koplugin）换皮：
Kindle 与分享版的「微信读书」入口（书架右上角第一个标签）就是这里画的页面。

不改插件文件（插件会自更新覆盖），而是在插件加载后替换
`weread.ui.library_view` 模块表上的 show / getLayout：

  * 页头直接用 WeReadTitleBar（「书架」+ 本机/微信读书/书库/全部 + ⋯），与本机书架同一组件；
  * 书架主体是 KOReader Menu（与本机 FileChooser 同一套翻页条「‹ 上一页 1/2 下一页 ›」），
    网格尺寸复用 coverbrowser 的 MosaicMenu._recalculateDimen，格子按本机 mosaic 的参数绘制；
  * 顶部「继续阅读」卡复用 wereadshelf.buildCardWith；
  * 插件原顶栏（‹ 书籍·全部▾ 🔍 ⟳ ☰）的功能收进 ⋯ 操作单，另加阅读统计 / 账号；
  * 没登录时不弹插件的提示，而是同一个页头下画一页「登录微信读书」引导，扫码成功后直接进书架；
  * 插件的整页二级页面（书籍详情、书评、阅读统计、章节目录、划线章节匹配）页头统一换成「‹ 返回 | 标题」导航行。

插件内部数据流（排序/筛选/下载/封面抓取/进度同步/详情页）一概不碰，只换视图。
任何一步出错都 pcall 兜底回落到插件原版界面，不会因插件升级而崩。

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Kit = require("ui/wereadkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Screen = Device.screen

local px, face = Kit.px, Kit.face

local Skin = {}

local function warn(...) logger.warn("weread skin:", ...) end

---------------------------------------------------------------- 数据小工具
local function bookId(book)
    return book and tostring(book.bookId or book.book_id or "") or ""
end

local function isFinished(book)
    return tonumber(book and book.finishReading) == 1
end

-- 插件本地保存的书（下载过/读过的）可能带进度
local function savedProgress(plugin, book)
    local ok, pct = pcall(function()
        local saved = plugin.settings:get("books", {})
        local rec = saved[bookId(book)]
        return rec and tonumber(rec.progress)
    end)
    return ok and pct or nil
end

-- 封面下灰字：已读完 / 读到 x% / 某日读过 / 未读；已下载加前缀
function Skin.statusText(plugin, book, mode, read_time)
    if mode == "public_account" then return book.author or "" end
    local text
    if isFinished(book) then
        text = "已读完"
    else
        local pct = savedProgress(plugin, book)
        if pct and pct > 0 then
            text = string.format("读到 %d%%", math.floor(pct + 0.5))
        elseif (tonumber(read_time) or tonumber(book.readUpdateTime) or 0) > 0 then
            text = os.date("%Y.%m.%d 读过", tonumber(read_time) or tonumber(book.readUpdateTime))
        else
            text = "未读"
        end
    end
    if book._cached then text = "已下载 · " .. text end
    return text
end

-- 本机阅读历史里每本微信读书书籍最后一次打开的时间（book_id → 时间戳）。
-- 云端书架的 readUpdateTime 只在书架重新同步时更新，本机刚读过的书会落后，
-- 所以要把 KOReader 自己的 ReadHistory 也算进来（本机书架的卡就是用它）。
local function localReadTimes(plugin)
    local times = {}
    local ok, err = pcall(function()
        local Content = require("weread.lib.content")
        local dirs = {}
        for id, rec in pairs(plugin.settings:get("books", {})) do
            if type(rec) == "table" then
                local d = Content.book_resolved_dir(plugin.settings, id, rec)
                if type(d) == "string" and d ~= "" then
                    dirs[#dirs + 1] = { id = tostring(id), dir = d:gsub("/+$", "") .. "/" }
                end
            end
        end
        for _, item in ipairs(require("readhistory").hist or {}) do
            local f = item.file
            if type(f) == "string" then
                local id
                for _, e in ipairs(dirs) do
                    if f:sub(1, #e.dir) == e.dir then id = e.id break end
                end
                -- /sdcard 与 /storage/emulated/0 前缀可能不一致：按默认缓存布局兜底
                id = id or f:match("/weread/cache/([^/]+)/")
                if id then
                    local t = tonumber(item.time) or 0
                    if t > (times[id] or 0) then times[id] = t end
                end
            end
        end
    end)
    if not ok then warn("localReadTimes", err) end
    return times
end

-- 最近在读、未读完的一本（给「继续阅读」卡）：云端阅读时间与本机打开时间取较新者
function Skin.recentBook(plugin)
    local local_times = localReadTimes(plugin)
    local best, best_t
    for _, book in ipairs(plugin and plugin.shelf_regular or {}) do
        local t = math.max(tonumber(book.readUpdateTime) or 0, local_times[bookId(book)] or 0)
        if t > 0 and not isFinished(book) and (not best or t > best_t) then
            best, best_t = book, t
        end
    end
    return best, best_t
end

local function coverPath(plugin, book)
    local ok, path = pcall(function() return plugin:getShelfCoverCache():pathFor(book) end)
    return ok and path or nil
end

-- 本机 mosaic 的列/行设置（coverbrowser 存在 FileChooser 类上）
local function gridSpec(with_card)
    local ok, FileChooser = pcall(require, "ui/widget/filechooser")
    local cols = ok and FileChooser.nb_cols_portrait or 3
    local rows = ok and FileChooser.nb_rows_portrait or 3
    if Screen:getWidth() > Screen:getHeight() then
        cols = ok and FileChooser.nb_cols_landscape or 4
        rows = ok and FileChooser.nb_rows_landscape or 2
    elseif with_card then
        rows = 2 -- 与 MosaicMenu 一致：挂了继续阅读卡时竖屏 2 行
    end
    return cols, rows
end

---------------------------------------------------------------- 封面格子（参数照抄本机 MosaicMenuItem）
local Cell = InputContainer:extend{
    book = nil, width = nil, height = nil, cover_path = nil, status = "", callback = nil,
}

function Cell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Hold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
    local caption_h = px(112)
    local dimen = Geom:new{ w = self.width, h = self.height - caption_h }
    local border = Size.border.thin
    local max_w, max_h = dimen.w - 2 * border, dimen.h - 2 * border
    local title = Kit.clean_title(self.book.title or bookId(self.book))
    local widget
    if self.cover_path then
        local ok, img = pcall(function()
            local RenderImage = require("ui/renderimage")
            local bb = RenderImage:renderImageFile(self.cover_path, false)
            if not bb then return nil end
            local scale = math.min(max_w / bb:getWidth(), max_h / bb:getHeight())
            local w = ImageWidget:new{ image = bb, scale_factor = scale, image_disposable = true }
            w:_render()
            return w
        end)
        if ok and img then
            local s = img:getSize()
            self._cover_w = s.w + 2 * border -- 给顶部卡片对齐用
            widget = CenterContainer:new{
                dimen = dimen,
                FrameContainer:new{
                    width = s.w + 2 * border, height = s.h + 2 * border,
                    margin = 0, padding = 0, bordersize = border,
                    img,
                },
            }
        end
    end
    if not widget then
        -- 没封面（或还在抓取）：2:3 细框里竖排书名
        local h = max_h
        local w = math.min(max_w, math.floor(h * 2 / 3))
        h = math.min(h, math.floor(w * 3 / 2))
        self._cover_w = w
        widget = CenterContainer:new{
            dimen = dimen,
            FrameContainer:new{
                width = w, height = h, margin = 0, padding = px(12), bordersize = border,
                CenterContainer:new{
                    dimen = Geom:new{ w = w - px(24) - 2 * border, h = h - px(24) - 2 * border },
                    TextBoxWidget:new{
                        text = title, face = face(30, true), alignment = "center",
                        width = w - px(24) - 2 * border,
                        height = h - px(24) - 2 * border, height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    },
                },
            },
        }
    end
    self[1] = VerticalGroup:new{
        align = "center",
        widget,
        VerticalSpan:new{ width = px(10) },
        TextBoxWidget:new{
            text = title,
            face = face(26),
            width = self.width - px(8),
            alignment = "center",
            height = px(66), height_adjust = true, height_overflow_show_ellipsis = true,
        },
        TextWidget:new{
            text = self.status or "",
            face = face(22),
            fgcolor = Blitbuffer.COLOR_GRAY_5,
            max_width = self.width - px(8),
        },
    }
end

function Cell:onTap()
    if self.callback then self.callback() end
    return true
end

function Cell:onHold()
    if self.hold_callback then self.hold_callback() elseif self.callback then self.callback() end
    return true
end

---------------------------------------------------------------- 书架视图（Menu 子类）
local function buildView(plugin, data, cb)
    local Menu = require("ui/widget/menu")
    local WeReadTitleBar = require("ui/widget/wereadtitlebar")
    local Shelf = require("apps/filemanager/wereadshelf")
    local mode = data.mode or "books"
    local source = (mode == "public_account" and data.accounts or data.books) or {}
    local host = plugin.ui
    local view

    local function closeView()
        if view then UIManager:close(view) end
    end

    -- 「继续阅读」卡：书籍模式下最近在读的一本，点开插件详情页
    local card
    local recent, recent_time
    if mode == "books" then recent, recent_time = Skin.recentBook(plugin) end
    if recent then
        local ok, res = pcall(function()
            local bb, cw, ch
            local path = coverPath(plugin, recent)
            if path then
                bb = require("ui/renderimage"):renderImageFile(path, false)
                if bb then cw, ch = bb:getWidth(), bb:getHeight() end
            end
            return Shelf.buildCardWith{
                title = Kit.clean_title(recent.title or bookId(recent)),
                authors = recent.author,
                cover_bb = bb, cover_w = cw, cover_h = ch, cover_disposable = true,
                progress_text = Skin.statusText(plugin, recent, "books", recent_time),
                button_text = "继续阅读",
                callback = function()
                    local okr, err = pcall(Skin.readBook, plugin, recent)
                    if okr then return end
                    warn("readBook", err)
                    if cb.on_select then cb.on_select(recent, "books") end
                end,
            }
        end)
        if ok then card = res else warn("card", res) end
    end

    -- 副标题：共 N 本 / 分组 / 搜索词 / 选书场景标题
    local parts = {}
    if data.title and data.title ~= "" then table.insert(parts, data.title) end
    if mode == "public_account" then
        table.insert(parts, "公众号")
    elseif data.group_label and data.group_label ~= "" then
        table.insert(parts, data.group_label)
    end
    if data.keyword and data.keyword ~= "" then table.insert(parts, "搜索「" .. data.keyword .. "」") end
    table.insert(parts, string.format(mode == "public_account" and "共 %d 个" or "共 %d 本", #source))

    local title_bar = WeReadTitleBar:new{
        title = "书架",
        subtitle = table.concat(parts, " · "),
        subtitle_truncate_left = true,
        tabs = Shelf.sourceTabs(host and host.opds, "weread", function(key)
            if key == "weread" then return end
            Skin.leaveTo(key, host, closeView)
        end),
        more_callback = function() Skin.showMore(plugin, view, data, cb) end,
        extra_widget = card,
    }

    local items = {}
    for i, book in ipairs(source) do items[i] = { book = book } end

    local FileChooser = require("ui/widget/filechooser")
    local cols_p, rows_p = gridSpec(false)
    -- 方法要在 new{} 里给：Menu:init 末尾就会调 updateItems / _recalculateDimen
    view = Menu:new{
        name = "weread_shelf",
        custom_title_bar = title_bar,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_bar_fm_style = true,
        hide_return_arrow = true,
        item_table = items,
        nb_cols_portrait = cols_p, nb_rows_portrait = rows_p,
        nb_cols_landscape = FileChooser.nb_cols_landscape or 4,
        nb_rows_landscape = FileChooser.nb_rows_landscape or 2,
        _skin_ready = false,
        _shelf_mode = mode,
        _recalculateDimen = Skin.recalculateDimen,
        updateItems = function(self, select_number)
            if not self._skin_ready then return end
            Skin.updateItems(self, plugin, data, cb, select_number)
        end,
        -- 翻页交给插件（它会按新页抓封面并重建视图）
        onGotoPage = function(self, page)
            page = math.max(1, math.min(page or 1, self.page_num or 1))
            if page ~= self.page and cb.on_page_changed then
                cb.on_page_changed(page)
            end
            return true
        end,
    }

    -- 插件期望的视图接口
    view.on_refresh = cb.on_refresh
    view.getScrollOffset = function() return nil end
    view.setRefreshing = function() end

    view._skin_ready = true
    view.page = math.max(1, tonumber(data.page) or 1)
    view:updateItems(1)
    view.page_size = view.perpage
    return view
end

-- 优先复用 coverbrowser 的 MosaicMenu._recalculateDimen，保证网格尺寸与本机书架一致
function Skin.recalculateDimen(menu)
    if Skin._mosaic_recalc == nil then
        local ok, MosaicMenu = pcall(require, "mosaicmenu")
        Skin._mosaic_recalc = ok and MosaicMenu and MosaicMenu._recalculateDimen or false
    end
    if Skin._mosaic_recalc then
        local ok, err = pcall(Skin._mosaic_recalc, menu)
        if ok then return end
        warn("mosaic recalc", err)
    end
    -- 兜底：同一套公式
    menu.nb_cols, menu.nb_rows = gridSpec(menu.title_bar and menu.title_bar.extra_widget)
    menu.perpage = menu.nb_rows * menu.nb_cols
    menu.page_num = math.ceil(#menu.item_table / menu.perpage)
    if menu.page_num > 0 and menu.page > menu.page_num then menu.page = menu.page_num end
    local others = 0
    if menu.title_bar then
        others = menu.title_bar.dimen.h + (menu.page_info and menu.page_info:getSize().h or 0)
    end
    menu.item_margin = Screen:scaleBySize(10)
    menu.item_height = math.floor((menu.inner_dimen.h - others - (1 + menu.nb_rows) * menu.item_margin) / menu.nb_rows)
    menu.item_width = math.floor((menu.inner_dimen.w - (1 + menu.nb_cols) * menu.item_margin) / menu.nb_cols)
    menu.item_dimen = Geom:new{ x = 0, y = 0, w = menu.item_width, h = menu.item_height }
end

-- 网格构建（照抄 CoverMenu.updateItems + MosaicMenu._updateItemsBuildUI 的结构）
function Skin.updateItems(menu, plugin, data, cb, select_number)
    local old_dimen = menu.dimen and menu.dimen:copy()
    menu.layout = {}
    menu.item_group:clear()
    menu.page_info:resetLayout()
    menu.return_button:resetLayout()
    menu.content_group:resetLayout()
    menu:_recalculateDimen()
    if menu.page_num < 1 then menu.page_num = 1 end
    if menu.page > menu.page_num then menu.page = menu.page_num end

    local mode = menu._shelf_mode
    local paths = data.cover_paths or {}
    local cur_row, line_layout = nil, {}
    local offset = (menu.page - 1) * menu.perpage
    for idx = 1, menu.perpage do
        local entry = menu.item_table[offset + idx]
        if not entry then break end
        entry.idx = offset + idx
        local book = entry.book
        if idx % menu.nb_cols == 1 or menu.nb_cols == 1 then
            if idx > 1 then table.insert(menu.layout, line_layout) end
            line_layout = {}
            table.insert(menu.item_group, VerticalSpan:new{ width = menu.item_margin })
            cur_row = HorizontalGroup:new{}
            table.insert(menu.item_group, LeftContainer:new{
                dimen = Geom:new{ w = menu.inner_dimen.w, h = menu.item_height },
                cur_row,
            })
            table.insert(cur_row, HorizontalSpan:new{ width = menu.item_margin })
        end
        local cell = Cell:new{
            book = book,
            width = menu.item_width,
            height = menu.item_height,
            cover_path = paths[book] or coverPath(plugin, book),
            status = Skin.statusText(plugin, book, mode),
            -- 单击直接读，长按进详情（与本机书架一致）；公众号、选书场景（插件带标题弹出的书架）保持插件原行为
            callback = function()
                if mode == "books" and not (data.title and data.title ~= "") then
                    local ok, err = pcall(Skin.readBook, plugin, book)
                    if ok then return end
                    warn("readBook", err)
                end
                if cb.on_select then cb.on_select(book, mode) end
            end,
            hold_callback = function()
                if cb.on_select then cb.on_select(book, mode) end
            end,
        }
        table.insert(cur_row, cell)
        table.insert(cur_row, HorizontalSpan:new{ width = menu.item_margin })
        table.insert(line_layout, cell)
    end
    table.insert(menu.layout, line_layout)
    table.insert(menu.item_group, VerticalSpan:new{ width = menu.item_margin })
    if #menu.item_table == 0 then
        table.insert(menu.item_group, CenterContainer:new{
            dimen = Geom:new{ w = menu.inner_dimen.w, h = px(200) },
            TextWidget:new{
                text = (data.keyword and data.keyword ~= "") and "没有匹配的书"
                    or (mode == "public_account" and "还没有关注公众号" or "书架是空的"),
                face = face(30), fgcolor = Kit.GRAY,
            },
        })
    end

    -- 顶部「继续阅读」卡与首行封面左右对齐
    local oka, erra = pcall(function()
        require("apps/filemanager/wereadshelf").alignHeaderCard(menu, menu.layout[1])
    end)
    if not oka then warn("align card", erra) end

    menu:updatePageInfo(select_number)
    -- _recalculateDimen 量高度时已缓存了翻页条尺寸（那时页码还是空串），重新排一次
    menu.page_info:resetLayout()
    menu:mergeTitleBarIntoLayout()
    UIManager:setDirty(menu.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(menu.dimen) or menu.dimen
    end)
end

---------------------------------------------------------------- ⋯ 操作单
function Skin.showGroupPicker(data, cb)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function pick(key)
        return function()
            UIManager:close(dialog)
            if cb.on_select_group then cb.on_select_group(key) end
        end
    end
    local buttons = {{{
        text = string.format("全部书籍（%d）", data.total_books or #(data.books or {})),
        checked_func = function() return data.group_key == nil end,
        callback = pick(nil),
    }}}
    for _, group in ipairs(data.groups or {}) do
        table.insert(buttons, {{
            text = string.format("%s（%d）", group.label or "", #(group.books or {})),
            checked_func = function() return data.group_key == group.key end,
            callback = pick(group.key),
        }})
    end
    dialog = ButtonDialog:new{
        title = "选择分组", title_align = "center",
        buttons = buttons,
        rows_per_page = math.max(4, math.floor(Screen:getHeight() / px(110)) - 3),
    }
    UIManager:show(dialog)
end

function Skin.showMore(plugin, view, data, cb)
    local mode = data.mode or "books"
    local actions = {}
    local function add(a) table.insert(actions, a) end
    if mode == "books" then
        add{
            icon = "wr.cat.folder", text = "分组",
            value = data.group_label or "全部",
            enabled = #(data.groups or {}) > 0,
            callback = function() Skin.showGroupPicker(data, cb) end,
        }
    end
    add{
        icon = mode == "books" and "wr.cat.person" or "wr.cat.book",
        text = mode == "books" and "公众号" or "书籍",
        enabled = mode ~= "books" or data.wp_enable ~= false,
        callback = function()
            if cb.on_switch then cb.on_switch(mode == "books" and "public_account" or "books") end
        end,
    }
    add{
        icon = "wr.search", text = "搜索书架", separator = true,
        value = (data.keyword and data.keyword ~= "") and data.keyword or nil,
        callback = function() if cb.on_search then cb.on_search() end end,
    }
    add{
        icon = "wr.cat.az", text = "排序", value = data.sort_label,
        callback = function() if cb.on_sort then cb.on_sort() end end,
    }
    if mode == "books" then
        add{
            icon = "wr.cat.tag", text = "筛选", value = data.filter_label,
            callback = function() if cb.on_filter then cb.on_filter() end end,
        }
    end
    add{
        icon = "cre.render.reload", text = "刷新书架", separator = true,
        callback = function() if cb.on_refresh then cb.on_refresh() end end,
    }
    local store_search = plugin.showSearch or plugin.onShowWeReadSearch
    if type(store_search) == "function" then
        add{
            icon = "wr.cat.globe", text = "搜索微信读书",
            callback = function()
                local ok, err = pcall(store_search, plugin)
                if not ok then warn("store search", err) end
            end,
        }
    end
    if type(plugin.showReadStats) == "function" then
        add{
            icon = "wr.cat.clock", text = "阅读统计", separator = type(store_search) ~= "function",
            callback = function()
                local ok, err = pcall(plugin.showReadStats, plugin)
                if not ok then warn("read stats", err) end
            end,
        }
    end
    if type(plugin.showAccountStatus) == "function" then
        add{
            icon = "wr.cat.person", text = "账号",
            callback = function()
                local ok, err = pcall(plugin.showAccountStatus, plugin)
                if not ok then warn("account", err) end
            end,
        }
    end
    UIManager:show(require("ui/widget/wereadactionsheet"):new{ actions = actions })
end

---------------------------------------------------------------- 整页二级页面：页头换成导航行
-- 插件的书籍详情 / 书评 / 阅读统计 / 章节目录 / 划线章节匹配都是「TitleBar(×) + 内容」的整页，
-- 这里把 view.title_bar 原位换成本机详情页同款「‹ 返回 | 标题」导航行，高度不变（内容区按原高度算过）。
-- 同时把 view.title_bar 指向导航行：划线章节匹配翻页时会用 self.title_bar 重建页面。
local function findChild(w, target, depth)
    if type(w) ~= "table" or depth > 5 then return nil end
    for i, c in ipairs(w) do
        if c == target then return w, i end
        local g, j = findChild(c, target, depth + 1)
        if g then return g, j end
    end
end

function Skin.swapTitleBar(view, title)
    local tb = view and view.title_bar
    if type(tb) ~= "table" or type(tb.getHeight) ~= "function" or tb._ireader_nav then return end
    local group, idx = findChild(view[1], tb, 0)
    if not group then return end
    local nav = Kit.NavRow:new{ width = tb.width or Screen:getWidth(), height = tb:getHeight() }
    nav:set(Kit.clean_title(title or tb.title or ""), function()
        if type(view.onClose) == "function" then view:onClose() else UIManager:close(view) end
    end)
    nav._ireader_nav = true
    group[idx] = nav
    view.title_bar = nav
    if type(group.resetLayout) == "function" then group:resetLayout() end
end

function Skin.reskinDetail(view, ddata)
    Skin.swapTitleBar(view, (ddata and ddata.title) or "书籍详情")
end

-- 其余整页：包住模块的 show（每次切换周期 / 模式插件都会重新 show 一页）
local PAGE_MODULES = {
    "weread.ui.book_reviews_view",
    "weread.ui.read_stats_view",
    "weread.ui.chapter_list_view",
    "weread.ui.annotation_chapter_picker",
}

function Skin.patchPages()
    if Skin._pages_patched then return end
    Skin._pages_patched = true
    for _, name in ipairs(PAGE_MODULES) do
        local ok, M = pcall(require, name)
        if ok and type(M) == "table" and type(M.show) == "function" then
            local orig = M.show
            M.show = function(...)
                local view = orig(...)
                local okr, errr = pcall(Skin.swapTitleBar, view)
                if not okr then warn("page reskin", name, errr) end
                return view
            end
        else
            warn("page module missing", name)
        end
    end
end

-- ensureChaptersLoaded 从目录缓存读到时只返回、不写回 book.chapters，统一在这里接住
function Skin.ensureChapters(plugin, book)
    local chapters = plugin:ensureChaptersLoaded(book)
    if type(book.chapters) ~= "table" and type(chapters) == "table" then book.chapters = chapters end
    return book.chapters
end

---------------------------------------------------------------- 书籍详情页（iReader 同款版式）
--   ‹ 返回 | 书籍详情
--   [封面]  书名 / 作者 / 推荐值 · 点评 · 字数 / 读到 x% · 已缓存 a/b 章
--   [ 阅读 ]  [ 下载全书 ]
--   章节目录 › / 书评 › / 获取最新信息 › / 清除缓存 ›
--   简介（截断，点开看全文）
--   出版社 · 出版时间 · ISBN
-- 数据来自插件 showBookMenu 传给 book_detail_view 的 ddata（回调原样接上）+ 当前这本书对象。
local function countText(n)
    n = tonumber(n)
    if not n or n <= 0 then return nil end
    if n >= 10000 then return string.format("%.1f 万", n / 10000) end
    return tostring(math.floor(n))
end

local function coverWidget(plugin, book, w, h)
    local path = coverPath(plugin, book)
    if path then
        local ok, img = pcall(function()
            local bb = require("ui/renderimage"):renderImageFile(path, false)
            if not bb then return nil end
            local scale = math.min(w / bb:getWidth(), h / bb:getHeight())
            local iw = ImageWidget:new{ image = bb, scale_factor = scale, image_disposable = true }
            iw:_render()
            return iw
        end)
        if ok and img then
            local sz = img:getSize()
            return FrameContainer:new{ width = sz.w + 2, height = sz.h + 2, padding = 0, margin = 0, bordersize = 1, img }
        end
    end
    return FrameContainer:new{
        width = w, height = h, padding = px(12), margin = 0, bordersize = px(2),
        CenterContainer:new{
            dimen = Geom:new{ w = w - px(28), h = h - px(28) },
            TextBoxWidget:new{
                text = Kit.clean_title(book.title or ""), face = face(26, true), width = w - px(28),
                alignment = "center", height = h - px(28), height_adjust = true, height_overflow_show_ellipsis = true,
            },
        },
    }
end

-- 列表行：左标题，右灰值 + ›，下细线
local function listRow(w, text, value, callback, enabled)
    local h = px(96)
    local pad = px(48)
    local value_w = math.floor(w * 0.45)
    local color = enabled == false and Kit.GRAY or Blitbuffer.COLOR_BLACK
    local row = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = pad },
        LeftContainer:new{
            dimen = Geom:new{ w = w - pad * 2 - value_w - px(40), h = h },
            TextWidget:new{ text = text, face = face(30), fgcolor = color, max_width = w - pad * 2 - value_w - px(40) },
        },
        require("ui/widget/container/rightcontainer"):new{
            dimen = Geom:new{ w = value_w, h = h },
            TextWidget:new{ text = value or "", face = face(26), fgcolor = Kit.GRAY, max_width = value_w },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = px(40), h = h },
            TextWidget:new{ text = "›", face = face(34), fgcolor = Kit.GRAY },
        },
    }
    return Kit.Tappable:new{
        width = w, height = h + px(1), align = "left",
        content = VerticalGroup:new{
            align = "left", row,
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, Kit.line(w - pad * 2, px(1)) },
        },
        callback = enabled ~= false and callback or nil,
    }
end

local function findAction(list, words)
    for _, a in ipairs(list or {}) do
        local t = tostring(a.text or "")
        for _, wd in ipairs(words) do
            if t:find(wd, 1, true) then return a end
        end
    end
end

local DetailPage = InputContainer:extend{
    plugin = nil, book = nil, ddata = nil, dcallbacks = nil,
    covers_fullscreen = true,
}

function DetailPage:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    local plugin, book, d = self.plugin, self.book or {}, self.ddata or {}
    local cb = self.dcallbacks or {}
    local page = self
    local nav = Kit.NavRow:new{ width = sw }
    nav:set("书籍详情", function() page:onClose() end)

    local pad = px(48)
    local cover_w, cover_h = px(240), px(340)
    local text_w = sw - pad * 2 - cover_w - px(36)
    local meta = {}
    local rating = tonumber(book.newRating)
    if rating and rating > 0 then table.insert(meta, string.format("推荐值 %.1f%%", rating / 10)) end
    local raters = countText(book.newRatingCount)
    if raters then table.insert(meta, raters .. " 人点评") end
    local words = countText(book.wordCount or book.totalWords)
    if words then table.insert(meta, words .. " 字") end
    local status = {}
    if isFinished(book) then
        table.insert(status, "已读完")
    elseif (tonumber(book.progress) or 0) > 0 then
        table.insert(status, string.format("读到 %d%%", math.floor(tonumber(book.progress) + 0.5)))
    end
    -- 插件状态行「进度 x%  ·  已缓存 a/b 章」：取带 a/b 的那段（按「·」整串拆，别放进字符类——会按字节误伤汉字）
    for seg in (tostring(d.status_line or "") .. "·"):gmatch("(.-)·") do
        if seg:find("%d+%s*/%s*%d+") then
            table.insert(status, (seg:gsub("^%s+", ""):gsub("%s+$", "")))
            break
        end
    end
    local head_text = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = Kit.clean_title(book.title or d.title or ""), face = face(44, true), width = text_w,
            height = px(120), height_adjust = true, height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = px(14) },
        TextBoxWidget:new{ text = d.author_line ~= "" and d.author_line or (book.author or ""), face = face(30), fgcolor = Kit.GRAY, width = text_w },
    }
    if #meta > 0 then
        table.insert(head_text, VerticalSpan:new{ width = px(14) })
        table.insert(head_text, TextBoxWidget:new{ text = table.concat(meta, " · "), face = face(26), width = text_w })
    end
    if #status > 0 then
        table.insert(head_text, VerticalSpan:new{ width = px(10) })
        table.insert(head_text, TextWidget:new{ text = table.concat(status, " · "), face = face(24), fgcolor = Kit.GRAY, max_width = text_w })
    end
    local head = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width = pad },
        coverWidget(plugin, book, cover_w, cover_h),
        HorizontalSpan:new{ width = px(36) },
        head_text,
    }

    -- 主按钮：阅读 / 下载全书（插件 bottom_actions：下载全书、章节目录、阅读）
    local acts = d.bottom_actions or {}
    local read_a = findAction(acts, { "阅读", "Read" }) or acts[3]
    local dl_a = findAction(acts, { "下载", "Download" }) or acts[1]
    local toc_a = findAction(acts, { "目录", "Chapter" }) or acts[2]
    local function run(a)
        if a and a.enabled ~= false and a.callback then a.callback() end
    end
    local read_label = (tonumber(book.progress) or 0) > 0 and not isFinished(book) and "继续阅读" or "阅读"
    local buttons = HorizontalGroup:new{
        align = "center",
        Kit.chip(read_label, px(300), px(90), true, function() run(read_a) end, 32),
        HorizontalSpan:new{ width = px(40) },
        Kit.chip("下载全书", px(300), px(90), false, function() run(dl_a) end, 32),
    }

    local rows = VerticalGroup:new{ align = "left", Kit.line(sw, px(1)) }
    local total_ch = type(book.chapters) == "table" and #book.chapters or nil
    table.insert(rows, listRow(sw, "章节目录", total_ch and string.format("共 %d 章", total_ch) or nil, function() run(toc_a) end))
    if d.review_action then
        table.insert(rows, listRow(sw, "书评", "推荐 / 最新", function() run(d.review_action) end))
    end
    local refreshed = d.refresh_date and (tostring(d.refresh_date):find("%d") and ("更新于 " .. d.refresh_date) or d.refresh_date)
    table.insert(rows, listRow(sw, "获取最新信息", refreshed, function()
        if cb.on_refresh then cb.on_refresh() end
    end))
    for _, a in ipairs(d.actions or {}) do
        table.insert(rows, listRow(sw, tostring(a.text or ""), nil, function() run(a) end, a.enabled))
    end

    -- 出版信息：一行灰字
    local pub = {}
    if book.publisher and book.publisher ~= "" then table.insert(pub, book.publisher) end
    if book.publishTime then -- 可能是时间戳，也可能是「2019-07-01 00:00:00」：交给插件自己的格式化
        local okd, date = pcall(function() return require("weread.lib.book_reviews").format_date(book.publishTime) end)
        if okd and type(date) == "string" and date ~= "" then table.insert(pub, date) end
    end
    if book.isbn and book.isbn ~= "" then table.insert(pub, "ISBN " .. book.isbn) end

    local nav_h = nav:getSize().h
    local fixed = nav_h + px(40) + math.max(cover_h, head:getSize().h) + px(44) + px(90) + px(40) + rows:getSize().h + px(36) + px(60)
        + (#pub > 0 and px(60) or 0) + px(30)
    local intro_text = d.intro or book.intro
    local body = VerticalGroup:new{
        align = "left",
        nav,
        VerticalSpan:new{ width = px(40) },
        head,
        VerticalSpan:new{ width = px(44) },
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = px(90) }, buttons },
        VerticalSpan:new{ width = px(40) },
        rows,
        VerticalSpan:new{ width = px(36) },
    }
    if intro_text and intro_text ~= "" then
        local intro_h = math.max(px(90), sh - fixed)
        table.insert(body, HorizontalGroup:new{
            HorizontalSpan:new{ width = pad },
            TextWidget:new{ text = "简介", face = face(30, true) },
        })
        table.insert(body, VerticalSpan:new{ width = px(16) })
        table.insert(body, Kit.Tappable:new{
            width = sw, height = intro_h, align = "left",
            content = HorizontalGroup:new{
                HorizontalSpan:new{ width = pad },
                TextBoxWidget:new{
                    text = intro_text, face = face(28), width = sw - pad * 2,
                    height = intro_h, height_adjust = false, height_overflow_show_ellipsis = true,
                },
            },
            callback = function()
                UIManager:show(require("ui/widget/textviewer"):new{ title = "简介", text = intro_text })
            end,
        })
    end
    if #pub > 0 then
        table.insert(body, VerticalSpan:new{ width = px(20) })
        table.insert(body, HorizontalGroup:new{
            HorizontalSpan:new{ width = pad },
            TextWidget:new{ text = table.concat(pub, " · "), face = face(22), fgcolor = Kit.GRAY, max_width = sw - pad * 2 },
        })
    end
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0,
        width = sw, height = sh, body,
    }
end

function DetailPage:onClose()
    UIManager:close(self)
    return true
end

function DetailPage:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

function Skin.showDetail(ddata, dcallbacks, book)
    local plugin = Skin.plugin
    if not (plugin and type(book) == "table") then return nil end
    local view = DetailPage:new{ plugin = plugin, book = book, ddata = ddata, dcallbacks = dcallbacks }
    UIManager:show(view)
    return view
end

---------------------------------------------------------------- 阅读页：微信读书单章 EPUB 的全书口径
-- 插件按章下载，每章是一个独立 EPUB；阅读页的书名、目录、上一章 / 下一章、进度都要换成全书口径，
-- 交互与 iReader 上的微信读书阅读页一致。返回 nil 表示不是单章书（整书 EPUB / 本机书照原样）。
function Skin.chapterContext(ui)
    local plugin = ui and ui.weread
    local file = ui and ui.document and ui.document.file
    if not (plugin and type(file) == "string" and file:find("/weread/cache/", 1, true)) then return nil end
    if ui._wr_open_ctx and ui._wr_open_ctx.file == file then return ui._wr_open_ctx.ctx end
    local ok, ctx = pcall(function()
        local book_id = plugin.detectWeReadBook and plugin:detectWeReadBook()
        if not book_id then return nil end
        local okp, WeRead = pcall(require, "weread.lib.protocol")
        if okp and WeRead.is_mp_book and WeRead.is_mp_book(book_id) then return nil end
        local books = plugin.settings:get("books", {})
        local book = books[book_id] or books[tostring(book_id)]
        if type(book) ~= "table" then return nil end
        Skin.ensureChapters(plugin, book)
        local idx, _cur, is_full_book = plugin:getChapterInfoFromFile(book, file)
        if is_full_book or not idx or type(book.chapters) ~= "table" or #book.chapters == 0 then return nil end
        return { plugin = plugin, book = book, idx = idx, chapters = book.chapters, file = file }
    end)
    if not ok then warn("chapterContext", ctx) ctx = nil end
    ui._wr_open_ctx = { file = file, ctx = ctx }
    return ctx
end

-- 打开第 idx 章：已缓存直接开，没缓存下载完自动开
function Skin.openChapterAt(ctx, idx)
    local plugin, book = ctx.plugin, ctx.book
    local ch = ctx.chapters[idx]
    if not ch then return false end
    local uid = tostring(ch.chapterUid or ch.chapterId or "")
    if idx == ctx.idx + 1 then
        Skin._advance = { book_id = tostring(book.book_id or book.bookId), to_idx = idx, expires = os.time() + 300 }
    end
    local cached = book.cached_chapters and book.cached_chapters[uid]
    if cached then
        local f = io.open(cached, "rb")
        if f then
            f:close()
            plugin:openFile(cached)
            return true
        end
    end
    if plugin.downloader:promotePrefetch(book, ch) then return true end
    local started = plugin.downloader:start(book, { ch }, "chapter", { single_chapter = true, open_on_complete = true })
    if started == false then Skin._advance = nil end
    return started ~= false
end

function Skin.chapterTitle(ctx)
    local ch = ctx and ctx.chapters[ctx.idx]
    return ch and Kit.clean_title(ch.title or "") or ""
end

-- 全书目录：当前章加粗，已下载的标「已下载」，点章节直接打开（没下载的下完即开）
function Skin.showBookToc(ctx)
    local Menu = require("ui/widget/menu")
    local items = {}
    local cached = ctx.book.cached_chapters or {}
    for i, ch in ipairs(ctx.chapters) do
        local uid = tostring(ch.chapterUid or ch.chapterId or "")
        local level = math.max(1, tonumber(ch.level) or 1)
        items[i] = {
            text = string.rep("    ", level - 1) .. (ch.title or ("第 " .. i .. " 章")),
            mandatory = cached[uid] and "已下载" or nil,
            bold = i == ctx.idx,
            idx = i,
        }
    end
    local menu
    menu = Menu:new{
        title = Kit.clean_title(ctx.book.title or "目录"),
        subtitle = string.format("共 %d 章", #items),
        item_table = items,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        single_line = true,
        title_bar_fm_style = true,
        onMenuSelect = function(_self, item)
            UIManager:close(menu)
            if item.idx ~= ctx.idx then
                local ok, err = pcall(Skin.openChapterAt, ctx, item.idx)
                if not ok then warn("toc open chapter", err) end
            end
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    -- 翻到当前章所在页
    local perpage = menu.perpage or 10
    menu:onGotoPage(math.floor((ctx.idx - 1) / perpage) + 1)
    UIManager:show(menu)
end

-- 阅读页「⋯」：书籍详情 / 书评 / 下载全书 / 阅读统计
function Skin.showReaderMore(ctx)
    local plugin, book = ctx.plugin, ctx.book
    local function call(name, ...)
        local args = { ... }
        return function()
            if type(plugin[name]) ~= "function" then return end
            local ok, err = pcall(plugin[name], plugin, unpack(args))
            if not ok then warn(name, err) end
        end
    end
    UIManager:show(require("ui/widget/wereadactionsheet"):new{ actions = {
        { icon = "wr.info", text = "书籍详情", callback = call("showBookRecord", book) },
        { icon = "wr.toc", text = "全书目录", callback = function() Skin.showBookToc(ctx) end },
        { icon = "wr.cat.star", text = "书评", callback = call("showBookReviews", book) },
        { icon = "wr.cat.download", text = "下载全书", separator = true, callback = call("confirmDownloadAllChapters", book) },
        { icon = "wr.cat.clock", text = "阅读统计", callback = call("showReadStats") },
    } })
end

---------------------------------------------------------------- 离开微信读书页（切到别的来源标签）
function Skin.leaveTo(key, host, close)
    local Shelf = require("apps/filemanager/wereadshelf")
    Shelf.rememberSource(key)
    if close then close() end
    if key ~= "local" and host and host.opds then
        host.opds:onShowOPDSCatalog(key ~= "all" and key or nil)
    end
end

---------------------------------------------------------------- 未登录：登录引导页
-- 与书架同一个页头（书架 + 来源标签 + ⋯），主体是居中的说明和「扫码登录」按钮。
-- 页面挂在 plugin.shelf_view 上：插件登录成功时 onWeReadAccountChanged → closeWeReadUI 会顺手关掉它。
local LoginPage = InputContainer:extend{
    plugin = nil,
    covers_fullscreen = true,
}

function LoginPage:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    local plugin = self.plugin
    local host = plugin.ui
    local Shelf = require("apps/filemanager/wereadshelf")
    local WeReadTitleBar = require("ui/widget/wereadtitlebar")
    local page = self
    local title_bar = WeReadTitleBar:new{
        title = "书架",
        subtitle = "微信读书 · 未登录",
        tabs = Shelf.sourceTabs(host and host.opds, "weread", function(key)
            if key == "weread" then return end
            Skin.leaveTo(key, host, function() UIManager:close(page) end)
        end),
        more_callback = function() Skin.showLoginMore(plugin) end,
    }
    local text_w = math.min(sw - px(160), px(820))
    local function para(text, size, color)
        return TextBoxWidget:new{
            text = text, face = face(size), fgcolor = color or Kit.GRAY,
            width = text_w, alignment = "center",
        }
    end
    local steps = TextBoxWidget:new{
        text = "1. 手机打开微信读书：我 › 设置 › 微信读书 Skill\n"
            .. "2. 点「获取 API Key」，确认已生成\n"
            .. "3. 回到这里点「扫码登录」，用微信扫码\n"
            .. "4. 手机确认页勾选「自动退出登录」再确认（不勾会报 401）",
        face = face(26), width = text_w, alignment = "left",
    }
    local content = VerticalGroup:new{
        align = "center",
        Kit.icon("wr.cat.book", 120),
        VerticalSpan:new{ width = px(32) },
        TextWidget:new{ text = "登录微信读书", face = face(44, true) },
        VerticalSpan:new{ width = px(18) },
        para("登录后在这里浏览微信读书书架、下载章节离线读，阅读进度和时长会同步回微信读书。", 28),
        VerticalSpan:new{ width = px(44) },
        FrameContainer:new{
            bordersize = px(2), radius = px(18), padding = px(28), margin = 0,
            color = Kit.GRAY, background = Blitbuffer.COLOR_WHITE,
            steps,
        },
        VerticalSpan:new{ width = px(56) },
        Kit.chip("扫码登录", px(360), px(88), true, function() Skin.startLogin(plugin) end, 32),
        VerticalSpan:new{ width = px(28) },
        para("账号信息只保存在这台设备的 KOReader 设置里。", 24),
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0,
        width = sw, height = sh,
        VerticalGroup:new{
            align = "left",
            title_bar,
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = sh - title_bar:getHeight() },
                content,
            },
        },
    }
end

function LoginPage:onClose()
    UIManager:close(self)
    return true
end

function LoginPage:onCloseWidget()
    if self.plugin and self.plugin.shelf_view == self then self.plugin.shelf_view = nil end
    UIManager:setDirty(nil, "full")
end

function Skin.isLoggedIn(plugin)
    local ok, res = pcall(function() return plugin.settings:is_api_configured() end)
    return ok and res
end

function Skin.startLogin(plugin)
    Skin._await_login = true
    local ok, err = pcall(function() plugin.qr_login:start() end)
    if not ok then
        Skin._await_login = nil
        warn("qr login", err)
    end
end

function Skin.showLogin(plugin)
    local page = LoginPage:new{ plugin = plugin }
    plugin.shelf_view = page
    UIManager:show(page)
    return page
end

-- 登录页的 ⋯：扫码登录 / 搜索微信读书 / 插件设置在 KOReader 菜单「工具 › 微信读书」里
function Skin.showLoginMore(plugin)
    UIManager:show(require("ui/widget/wereadactionsheet"):new{ actions = {
        {
            icon = "wr.cat.person", text = "扫码登录",
            callback = function() Skin.startLogin(plugin) end,
        },
        {
            icon = "wr.info", text = "更多设置", value = "菜单 › 工具 › 微信读书",
            enabled = false,
        },
    } })
end

---------------------------------------------------------------- 详情页「阅读」按需下载
-- 插件原版「阅读」只开离线缓存（enabled = has_cache），没缓存时是灰的。
-- 这里在没缓存时把它点亮：定位当前进度所在章 → 只下这一章 → 下完直接打开。
-- 下一章交给插件自带的「下载设置 › 章节预下载 › 自动预下载下一章」。
local function isReadAction(action)
    local t = type(action) == "table" and tostring(action.text or "") or ""
    return t:find("阅读", 1, true) or t:find("Read", 1, true)
end

-- 与插件 openBookForReading 的定位规则一致：chapter_uid › chapter_idx › 进度百分比
local function targetChapter(book, chapters)
    if type(chapters) ~= "table" or #chapters == 0 then return nil end
    local by_idx
    for index, chapter in ipairs(chapters) do
        local uid = tostring(chapter.chapterUid or chapter.chapterId or index)
        if book.chapter_uid ~= nil and uid == tostring(book.chapter_uid) then return chapter end
        if not by_idx and book.chapter_idx ~= nil
            and tonumber(chapter.chapterIdx or chapter.chapterIndex) == tonumber(book.chapter_idx) then
            by_idx = chapter
        end
    end
    if by_idx then return by_idx end
    local progress = math.max(0, math.min(100, tonumber(book.progress) or 0))
    return chapters[math.floor(progress / 100 * (#chapters - 1)) + 1]
end

function Skin.readOnDemand(plugin, book)
    plugin:loadChapters(book, function(chapters)
        local ok, err = pcall(function()
            local chapter = targetChapter(book, chapters)
            if not chapter then
                plugin:showInfo("没拿到章节目录，请先在「章节目录」里刷新。")
                return
            end
            -- 恰好在后台预下载这一章：直接升级为前台任务，下完即开
            if plugin.downloader:promotePrefetch(book, chapter) then return end
            plugin.downloader:start(book, { chapter }, "chapter", {
                single_chapter = true,
                open_on_complete = true,
            })
        end)
        if not ok then
            warn("readOnDemand", err)
            plugin:showInfo("按需下载失败：" .. tostring(err))
        end
    end)
end

---------------------------------------------------------------- 书架单击：直接读
-- 按云端进度定位章节：整书已下载 → 开整书；这一章已下载 → 直接开；
-- 一章都没下过（第一次读）→ 底部提示单：开始阅读（先下这一章）/ 下载全书 / 书籍详情；
-- 下过别的章但这章没有 → 只下这一章、下完即开。
local function fileExists(path)
    if type(path) ~= "string" or path == "" then return false end
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

-- 书架上的书对象只有书目字段，下载记录 / 云端位置在插件的书库记录里：合并一份
local function bookRecord(plugin, book)
    local id = bookId(book)
    local saved = plugin.settings:get("books", {})[id]
    if type(saved) ~= "table" then return book, false end
    for k, v in pairs(book) do
        if saved[k] == nil then saved[k] = v end
    end
    return saved, true
end

function Skin.showFirstReadSheet(plugin, book, chapter)
    local title = Kit.clean_title(book.title or "")
    local header = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = px(28) },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = px(44) },
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = title, face = face(36, true), max_width = Screen:getWidth() - px(88) },
                VerticalSpan:new{ width = px(12) },
                TextBoxWidget:new{
                    text = "这本书还没下载到本机。可以先读，后面的章节读到时自动下载；也可以先下载全书，之后不联网也能读。",
                    face = face(26), fgcolor = Kit.GRAY, width = Screen:getWidth() - px(88),
                },
            },
        },
        VerticalSpan:new{ width = px(20) },
    }
    local function start_chapter()
        local ok, err = pcall(function()
            if plugin.downloader:promotePrefetch(book, chapter) then return end
            plugin.downloader:start(book, { chapter }, "chapter", { single_chapter = true, open_on_complete = true })
        end)
        if not ok then warn("first read", err) end
    end
    UIManager:show(require("ui/widget/wereadactionsheet"):new{
        header = header,
        actions = {
            {
                icon = "wr.cat.book", text = "开始阅读",
                value = chapter and chapter.title and Kit.clean_title(chapter.title) or "先下载当前章节",
                enabled = chapter ~= nil,
                callback = start_chapter,
            },
            {
                icon = "wr.cat.download", text = "下载全书", value = "下载完离线也能读",
                callback = function()
                    local ok, err = pcall(plugin.confirmDownloadAllChapters, plugin, book)
                    if not ok then warn("download all", err) end
                end,
            },
            {
                icon = "wr.info", text = "书籍详情", separator = true,
                callback = function()
                    local ok, err = pcall(plugin.showBookRecord, plugin, book)
                    if not ok then warn("detail", err) end
                end,
            },
        },
    })
end

function Skin.readBook(plugin, book)
    local rec = bookRecord(plugin, book)
    local full = type(plugin.getFullBookCachePath) == "function" and plugin:getFullBookCachePath(rec)
    if fileExists(full) then
        plugin:openFile(full)
        return
    end
    plugin:loadChapters(rec, function(chapters)
        local ok, err = pcall(function()
            if type(chapters) == "table" and type(rec.chapters) ~= "table" then rec.chapters = chapters end
            local chapter = targetChapter(rec, chapters)
            local uid = chapter and tostring(chapter.chapterUid or chapter.chapterId or "")
            local path = uid and rec.cached_chapters and rec.cached_chapters[uid]
            if fileExists(path) then
                plugin:openFile(path)
                return
            end
            local has_any = type(plugin.bookRecordHasDownload) == "function" and plugin:bookRecordHasDownload(rec)
            if not has_any then
                Skin.showFirstReadSheet(plugin, rec, chapter)
                return
            end
            if not chapter then
                plugin:openBookForReading(rec)
                return
            end
            if plugin.downloader:promotePrefetch(rec, chapter) then return end
            plugin.downloader:start(rec, { chapter }, "chapter", { single_chapter = true, open_on_complete = true })
        end)
        if not ok then
            warn("readBook", err)
            plugin:showInfo("打开失败：" .. tostring(err))
        end
    end)
end

function Skin.patchReadAction(ddata)
    local plugin, book = Skin.plugin, Skin._detail_book
    if not (plugin and book and type(ddata) == "table") then return end
    if type(plugin.loadChapters) ~= "function" or type(plugin.downloader) ~= "table"
        or type(plugin.downloader.start) ~= "function" then return end
    for _i, action in ipairs(ddata.bottom_actions or {}) do
        if isReadAction(action) and action.enabled == false then
            action.enabled = true
            action.callback = function()
                local okc, errc = pcall(Skin.readOnDemand, plugin, book)
                if not okc then warn("readOnDemand", errc) end
            end
        end
    end
end

---------------------------------------------------------------- 正文图片尺寸
-- 微信读书正文里的插图一律带内联 style="width:100%"，不管原图多大都拉满版心（404px 的小图被放大两倍多）。
-- 改为「原图像素 1:1」：宽度百分比 = 原图宽(data-w) / 版心宽，最多 100%。没有 style 的图也补上同样的宽度。
-- 插件写 EPUB 前（单章 / 整书 / 整书断点续传的按章落盘）统一过一遍，插件文件本身不改。
-- 版心宽（设备像素）：iReader 1080 宽屏、页边 15 时实测 950，其它屏幕按同一比例
local function imgColumnPx()
    return math.max(1, math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 950 / 1080))
end

function Skin.fixImageWidths(xhtml)
    if type(xhtml) ~= "string" or not xhtml:find("<img", 1, true) then return xhtml end
    return (xhtml:gsub("<img[^>]*>", function(tag)
        local w = tonumber(tag:match('data%-w="(%d+)'))
        if not w or w <= 0 then return tag end
        local pct = math.min(100, math.floor(w / imgColumnPx() * 100 + 0.5))
        local width = "width:" .. pct .. "%%;" -- gsub 替换串里 % 要写成 %%
        if tag:find("width:%s*100%%;?") then
            return (tag:gsub("width:%s*100%%;?", width, 1))
        elseif not tag:find("style=", 1, true) then
            return (tag:gsub("^<img", '<img style="' .. width .. '"', 1))
        end
        return tag
    end))
end

function Skin.patchContent()
    if Skin._content_patched then return end
    local ok, err = pcall(function()
        local Content = require("weread.lib.content")
        if type(Content) ~= "table" then return end
        local function wrap(name, argi)
            local orig = Content[name]
            if type(orig) ~= "function" then
                warn("content." .. name .. " missing, image widths untouched")
                return
            end
            Content[name] = function(...)
                local args = { n = select("#", ...), ... }
                local okf, res = pcall(function()
                    local v = args[argi]
                    if type(v) == "string" then
                        args[argi] = Skin.fixImageWidths(v)
                    elseif type(v) == "table" then -- save_book_epub 的 chapter_bodies：uid → xhtml
                        for k, body in pairs(v) do
                            if type(body) == "string" then v[k] = Skin.fixImageWidths(body) end
                        end
                    end
                end)
                if not okf then warn("fix image widths", res) end
                return orig(unpack(args, 1, args.n))
            end
        end
        wrap("save_chapter_epub", 4)                    -- (settings, book, chapter, xhtml, ...)
        wrap("save_book_epub", 4)                       -- (settings, book, chapters, chapter_bodies, ...)
        wrap("save_full_download_rendered_chapter", 4)  -- (workspace, chapter, index, xhtml)
        Skin._content_patched = true
    end)
    if not ok then warn("patchContent", err) end
end

---------------------------------------------------------------- 挂载
-- 同进程里只改一次模块表；插件实例（FM / ReaderUI 各一个）各自包一层 showShelfView
function Skin.apply(plugin)
    if not plugin then return end
    Skin.plugin = plugin
    Skin.patchContent()
    local ok, err = pcall(function()
        if not Skin._patched then
            local LV = require("weread.ui.library_view")
            if type(LV) ~= "table" or type(LV.show) ~= "function" or type(LV.getLayout) ~= "function" then
                warn("library_view interface changed, keep stock UI")
                return
            end
            local orig_show, orig_layout = LV.show, LV.getLayout
            LV.getLayout = function(cover_mode, count, mode)
                local ok2, res = pcall(function()
                    local cols, rows = gridSpec(mode ~= "public_account" and Skin.recentBook(Skin.plugin) ~= nil)
                    return { columns = cols, rows = rows, page_size = cols * rows }
                end)
                if ok2 and res then return res end
                warn("getLayout", res)
                return orig_layout(cover_mode, count, mode)
            end
            LV.show = function(data, callbacks)
                local ok2, view = pcall(buildView, Skin.plugin, data or {}, callbacks or {})
                if ok2 and view then
                    UIManager:show(view)
                    return view
                end
                warn("show failed, fallback to stock UI:", view)
                return orig_show(data, callbacks)
            end
            Skin._patched = true
            Skin.patchPages()
            -- 书籍详情页：只把顶栏换成本机详情页同款「‹ 返回 | 书名」导航行
            local okd, BD = pcall(require, "weread.ui.book_detail_view")
            if okd and type(BD) == "table" and type(BD.show) == "function" then
                local orig_detail = BD.show
                BD.show = function(ddata, dcallbacks)
                    local okp, errp = pcall(Skin.patchReadAction, ddata)
                    if not okp then warn("patch read action", errp) end
                    local book = Skin._detail_book
                    Skin._detail_book = nil
                    local okv, ours = pcall(Skin.showDetail, ddata, dcallbacks, book)
                    if okv and ours then return ours end
                    if not okv then warn("detail page", ours) end
                    local view = orig_detail(ddata, dcallbacks)
                    local okr, errr = pcall(Skin.reskinDetail, view, ddata)
                    if not okr then warn("detail reskin", errr) end
                    return view
                end
            end
        end
        -- 始终按封面模式取数（插件只在封面模式下准备封面路径并后台抓取）
        if not plugin._ireader_skinned and type(plugin.showShelfView) == "function" then
            local orig = plugin.showShelfView
            plugin.showShelfView = function(self, ...)
                Skin.plugin = self
                local shelf = self.settings and self.settings:get("shelf")
                local saved = shelf and shelf.view_mode
                if shelf then shelf.view_mode = "cover" end
                local ok2, res = pcall(orig, self, ...)
                if shelf then shelf.view_mode = saved end
                if not ok2 then error(res, 0) end
                return res
            end
            plugin._ireader_skinned = true
        end
        -- 没登录（且没有缓存书架）时打开书架：画我们的登录引导页，不弹插件的「请先扫码」
        if not plugin._ireader_login_hooked and type(plugin.showBookshelf) == "function" then
            local orig_shelf = plugin.showBookshelf
            plugin.showBookshelf = function(self, ...)
                Skin.plugin = self
                local okc, cached = pcall(function()
                    local c = self.library_db and self.library_db:getShelf()
                    return c and #c > 0
                end)
                if not Skin.isLoggedIn(self) and not (okc and cached) then
                    local okl, page = pcall(Skin.showLogin, self)
                    if okl then return page end
                    warn("login page", page)
                end
                return orig_shelf(self, ...)
            end
            -- 扫码成功：插件先关掉它的页面（含登录页），再 refreshLoginMenu；这时接着打开书架
            if type(plugin.refreshLoginMenu) == "function" then
                local orig_refresh = plugin.refreshLoginMenu
                plugin.refreshLoginMenu = function(self, ...)
                    local res = orig_refresh(self, ...)
                    if Skin._await_login and Skin.isLoggedIn(self) then
                        Skin._await_login = nil
                        UIManager:scheduleIn(0.5, function()
                            local oks, errs = pcall(self.showBookshelf, self)
                            if not oks then warn("shelf after login", errs) end
                        end)
                    end
                    return res
                end
            end
            plugin._ireader_login_hooked = true
        end
        -- 记下当前详情页对应的书，供 BD.show 包装里改「阅读」按钮用
        if not plugin._ireader_detail_hooked and type(plugin.showBookMenu) == "function" then
            local orig_menu = plugin.showBookMenu
            plugin.showBookMenu = function(self, book, ...)
                Skin.plugin = self
                Skin._detail_book = book
                local ok2, res = pcall(orig_menu, self, book, ...)
                Skin._detail_book = nil
                if not ok2 then error(res, 0) end
                return res
            end
            plugin._ireader_detail_hooked = true
        end
        -- 单章读完翻页：直接接着读下一章（已缓存就开，没缓存就下载后自动开），不弹章末对话框
        if not plugin._ireader_eob_hooked and type(plugin.handleEndOfBook) == "function" then
            local orig_eob = plugin.handleEndOfBook
            plugin.handleEndOfBook = function(self, status_self)
                local okc, handled = pcall(Skin.continueNextChapter, self)
                if okc and handled then return true end
                if not okc then warn("continue next chapter", handled) end
                return orig_eob(self, status_self)
            end
            plugin._ireader_eob_hooked = true
        end
        -- 顺序翻到下一章后，云端还停在上一章末尾，插件会弹「阅读进度不一致」让人选。
        -- 往后读是正常前进：刚由 continueNextChapter 接续、且本机章节在云端之后时，静默保留本机进度。
        local ps = plugin.progress_sync
        if not plugin._ireader_sync_hooked and type(ps) == "table" and type(ps.on_choice) == "function" then
            local orig_choice = ps.on_choice
            ps.on_choice = function(context)
                local okk, handled = pcall(Skin.keepLocalAfterAdvance, context)
                if okk and handled then return end
                if not okk then warn("keep local after advance", handled) end
                return orig_choice(context)
            end
            plugin._ireader_sync_hooked = true
        end
    end)
    if not ok then warn("apply", err) end
end

-- 页脚 / 进度面板用：微信读书单章 EPUB 的「全书页码」估算。单章文件自己的页数只是这一章的（「1 / 2」）。
-- 没下载的章节没法排版，只能按目录字数 ÷ 每页字数估算。每页字数不能只看当前这一章——版权页、推荐序这种
-- 几十个字占两页的短章会算出每页十几个字，全书估成两万多页，而且一换章总页数就跳。所以：
--   * 每读到一章，记下这一章「目录字数 / 实际排出的页数」（按书、按排版签名存；排版一变就重新累计）；
--   * 每页字数 = 已记录章节字数之和 ÷ 页数之和，只用 ≥ CALIBRATE_WORDS 字的章节；累计到 STABLE_WORDS 后不再更新，
--     总页数从此固定，换章不变；
--   * 还没有可用章节时用当前章兜底，并把每页字数限制在 [WPP_MIN, WPP_MAX]，不会出现离谱的总页数。
-- 当前页 = (本章之前的字数 + 本章字数 × 本章阅读比例) ÷ 每页字数；总页数 = 全书字数 ÷ 每页字数。
-- 返回 当前页, 总页数；整书 EPUB 或算不出时返回 nil。
local CALIBRATE_WORDS = 1000
local STABLE_WORDS = 20000
local WPP_MIN, WPP_MAX = 150, 1500
local PAGINATION_KEY = "ireader_weread_pagination"

-- 排版签名：字体、字号、行距、页边距、屏幕尺寸，任何一项变了每页字数就要重新累计
local function layoutSignature(plugin)
    local ui = plugin and plugin.ui
    local doc = ui and ui.document
    local conf = doc and doc.configurable or {}
    local parts = { Screen:getWidth() .. "x" .. Screen:getHeight() }
    for _, k in ipairs{ "font_size", "line_spacing", "h_page_margins", "t_page_margin", "b_page_margin",
            "word_spacing", "word_expansion", "render_dpi", "embedded_css", "embedded_fonts" } do
        local v = conf[k]
        if type(v) == "table" then v = table.concat(v, ",") end
        parts[#parts + 1] = k .. "=" .. tostring(v)
    end
    local face = ui and ui.font and ui.font.font_face
    parts[#parts + 1] = "face=" .. tostring(face)
    return table.concat(parts, ";")
end

local function wordsPerPage(c, pages, sig)
    local all = G_reader_settings:readSetting(PAGINATION_KEY) or {}
    local rec = all[c.book_id]
    if type(rec) ~= "table" or rec.sig ~= sig then rec = { sig = sig, ch = {} } end
    local sum_w, sum_p = 0, 0
    for _, m in pairs(rec.ch) do
        if m.w >= CALIBRATE_WORDS then sum_w, sum_p = sum_w + m.w, sum_p + m.p end
    end
    -- 记下本章（够长、还没稳定、这一章还没记过或页数变了）
    if c.uid and c.cur >= CALIBRATE_WORDS and sum_w < STABLE_WORDS then
        local m = rec.ch[c.uid]
        if not m or m.p ~= pages then
            if m then sum_w, sum_p = sum_w - m.w, sum_p - m.p end
            rec.ch[c.uid] = { w = c.cur, p = pages }
            sum_w, sum_p = sum_w + c.cur, sum_p + pages
            all[c.book_id] = rec
            G_reader_settings:saveSetting(PAGINATION_KEY, all)
        end
    end
    local wpp
    if sum_p > 0 then
        wpp = sum_w / sum_p
    else
        wpp = Skin.layoutWordsPerPage(c.plugin) -- 兜底：还没有够长的章节，按版面估
    end
    if not wpp then return nil end
    return math.max(WPP_MIN, math.min(WPP_MAX, wpp))
end

-- 按版面估每页字数（中文一字一格）：每行字数 × 行数 × 0.85（段首缩进、段尾、标题留白）
function Skin.layoutWordsPerPage(plugin)
    local ok, wpp = pcall(function()
        local conf = plugin.ui.document.configurable
        local fs = tonumber(conf.font_size) or 22
        local fs_px = Screen:scaleBySize(fs) -- crengine 字号与界面同一套缩放
        local lh = fs_px * (tonumber(conf.line_spacing) or 115) / 100
        local hm = type(conf.h_page_margins) == "table" and conf.h_page_margins or { 15, 15 }
        local w = Screen:getWidth() - Screen:scaleBySize((tonumber(hm[1]) or 15) + (tonumber(hm[2]) or 15))
        local h = Screen:getHeight() - Screen:scaleBySize((tonumber(conf.t_page_margin) or 15) + (tonumber(conf.b_page_margin) or 15))
            - Screen:scaleBySize(40) -- 页脚
        return math.floor(w / fs_px) * math.floor(h / lh) * 0.85
    end)
    return ok and wpp and wpp > 0 and wpp or 450
end

function Skin.chapterBookPages(plugin, file, page, pages)
    page, pages = tonumber(page), tonumber(pages)
    if not (page and pages and pages > 0) then return nil end
    if not Skin.chapterBookFraction(plugin, file, page, pages) then return nil end
    local c = Skin._chapter_frac
    if not c.book_id then return nil end
    local sig = layoutSignature(plugin)
    c.plugin = plugin
    if c.wpp_sig ~= sig or c.wpp_pages ~= pages then
        c.wpp = wordsPerPage(c, pages, sig)
        c.wpp_sig, c.wpp_pages = sig, pages
    end
    local wpp = c.wpp
    if not wpp or wpp <= 0 then return nil end
    local total_pages = math.max(1, math.ceil(c.total / wpp))
    local read_words = c.prev + c.cur * math.min(1, math.max(0, (page - 1) / pages))
    local cur = math.max(1, math.min(total_pages, math.floor(read_words / wpp) + 1))
    return cur, total_pages
end

function Skin.chapterBookFraction(plugin, file, page, pages)
    if not (plugin and file) or not file:find("/weread/cache/", 1, true) then return nil end
    local c = Skin._chapter_frac
    if not c or c.file ~= file then
        c = { file = file }
        Skin._chapter_frac = c
        local book_id = plugin.detectWeReadBook and plugin:detectWeReadBook()
        c.book_id = book_id and tostring(book_id)
        local books = book_id and plugin.settings:get("books", {}) or {}
        local book = book_id and (books[book_id] or books[tostring(book_id)])
        if type(book) == "table" then
            Skin.ensureChapters(plugin, book)
            local idx, _cur, is_full_book = plugin:getChapterInfoFromFile(book, file)
            if idx and not is_full_book and type(book.chapters) == "table" then
                local total, prev = 0, 0
                for i, ch in ipairs(book.chapters) do
                    local w = tonumber(ch.wordCount) or 0
                    total = total + w
                    if i < idx then prev = prev + w end
                end
                if total > 0 then
                    local ch = book.chapters[idx]
                    c.prev, c.cur, c.total = prev, tonumber(ch.wordCount) or 0, total
                    c.uid = tostring(ch.chapterUid or ch.chapterId or idx)
                end
            end
        end
    end
    if not c.total then return nil end
    local p = (tonumber(pages) or 0) > 0 and math.min(1, page / pages) or 0
    return (c.prev + c.cur * p) / c.total
end

-- 返回 true 表示已接管（打开 / 开始下载下一章）；false 交回插件原逻辑（整书、最后一章、非微信读书书籍、下载起不来）
function Skin.continueNextChapter(plugin)
    local book_id = plugin.detectWeReadBook and plugin:detectWeReadBook()
    if not book_id then return false end
    local okp, WeRead = pcall(require, "weread.lib.protocol")
    if okp and WeRead.is_mp_book and WeRead.is_mp_book(book_id) then return false end -- 公众号文章
    local books = plugin.settings:get("books", {})
    local book = books[book_id] or books[tostring(book_id)]
    if type(book) ~= "table" then return false end
    Skin.ensureChapters(plugin, book)
    local file = plugin.ui and plugin.ui.document and plugin.ui.document.file
    local idx, _cur, is_full_book = plugin:getChapterInfoFromFile(book, file)
    if is_full_book or not idx or type(book.chapters) ~= "table" then return false end
    local next_ch = book.chapters[idx + 1]
    if not next_ch then return false end -- 最后一章：保留插件的章末对话框
    local uid = tostring(next_ch.chapterUid or next_ch.chapterId or "")
    local cached = book.cached_chapters and book.cached_chapters[uid]
    -- 记下「正在顺序翻到下一章」，打开后的进度冲突弹窗据此静默保留本机进度（新 ReaderUI 实例，所以放模块级）
    Skin._advance = { book_id = tostring(book_id), to_idx = idx + 1, expires = os.time() + 300 }
    if cached then
        local f = io.open(cached, "rb")
        if f then
            f:close()
            plugin:openFile(cached)
            return true
        end
    end
    -- 后台预下载正在下这一章：升级成前台任务，下完即开（Android 上插件的后台下载不可用，基本走不到）
    if plugin.downloader:promotePrefetch(book, next_ch) then return true end
    local started = plugin.downloader:start(book, { next_ch }, "chapter", {
        single_chapter = true,
        open_on_complete = true,
    })
    if started == false then Skin._advance = nil end
    return started ~= false
end

function Skin.keepLocalAfterAdvance(context)
    local a = Skin._advance
    if not a or os.time() > a.expires or type(context) ~= "table" or context.source_conflict then return false end
    local lp, rp = context.local_position, context.remote_position
    if type(lp) ~= "table" or type(rp) ~= "table" then return false end
    if lp.book_id and tostring(lp.book_id) ~= a.book_id then return false end
    local li, ri = tonumber(lp.chapter_idx), tonumber(rp.chapter_idx)
    local ahead
    if li and ri then
        ahead = li > ri
    else
        ahead = (tonumber(lp.fraction) or tonumber(lp.percent) or 0) >= (tonumber(rp.fraction) or tonumber(rp.percent) or 0)
    end
    if not ahead or type(context.keep_local) ~= "function" then return false end
    Skin._advance = nil
    context.keep_local()
    return true
end

return Skin

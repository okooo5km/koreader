--[[--
书架顶部「继续阅读」卡（微信读书式）。挂在文件管理器标题栏下方。

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Device = require("device")
local Kit = require("ui/wereadkit")
local IFeatures = require("ireader/features") -- 微信读书集成开关（分享版不带集成）
local lfs = require("libs/libkoreader-lfs")
local Screen = Device.screen

local px, face, chip, clean_title = Kit.px, Kit.face, Kit.chip, Kit.clean_title

local Shelf = {}

-- 最近读过且仍存在的一本书
function Shelf.lastBook()
    local ReadHistory = require("readhistory")
    for _, item in ipairs(ReadHistory.hist or {}) do
        -- 微信读书的单章缓存不算本机在读（它们在「微信读书」页有自己的继续阅读卡）
        -- （没有任何微信读书时不过滤这两类路径）
        if item.file and (not IFeatures.anyWeread() or (not item.file:find("/weread/cache/", 1, true)
                and not item.file:find("/wereader-cloud/", 1, true)))
                and lfs.attributes(item.file, "mode") == "file" then
            return item.file
        end
    end
end

local function readJson(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local ok, t = pcall(require("json").decode, s)
    return ok and type(t) == "table" and t or nil
end

-- 微信读书插件下载的书（…/weread/cache/<book_id>/xxx.epub）：书目、封面、整书进度都从插件落盘的文件取。
-- 单章 EPUB 不带封面、侧车进度也只是这一章的，所以不能按普通本地书处理。
-- 读书桌面（Books.java）用同一套文件和口径，两边改动要同步。
-- 返回 nil 或 { title, author, cover_path, pct(0~1 整书), finished }
function Shelf.wereadInfo(file)
    if not IFeatures.anyWeread() then return nil end
    local root, id = file:match("^(.*)/weread/cache/([^/]+)/[^/]+$")
    if not id then return nil end
    local dir = root .. "/weread/cache/" .. id .. "/"
    local meta = readJson(dir .. "metadata.json") or {}
    local state = readJson(dir .. "reading_state.json") or {}
    local info = { title = meta.title, author = meta.author, finished = tonumber(meta.finishReading) == 1 }
    local pos = type(state.last_local_position) == "table" and state.last_local_position or nil
    if pos and tonumber(pos.fraction) then
        info.pct = tonumber(pos.fraction)
    elseif tonumber(state.progress) then
        info.pct = tonumber(state.progress) / 100
    end
    if type(meta.cover) == "string" and meta.cover ~= "" then
        local p = root .. "/weread/shelf-covers/" .. require("ffi/sha2").md5(meta.cover) .. ".thumb.png"
        if lfs.attributes(p, "mode") == "file" then info.cover_path = p end
    end
    return info
end

local function bookMeta(file)
    local title, authors, cover_bb, cover_w, cover_h
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    if ok and BookInfoManager then
        local bi = BookInfoManager:getBookInfo(file, true)
        if bi then
            title, authors = bi.title, bi.authors
            if bi.has_cover and bi.cover_bb then
                cover_bb, cover_w, cover_h = bi.cover_bb, bi.cover_w, bi.cover_h
            end
        end
    end
    local disposable = false
    local okw, wr = pcall(Shelf.wereadInfo, file)
    if okw and wr then
        if wr.title and wr.title ~= "" then title = wr.title end -- 单章文件名带「 - 章节名」，用书目里的书名
        if (not authors or authors == "") and wr.author then authors = wr.author end
        if not cover_bb and wr.cover_path then
            local bb = require("ui/renderimage"):renderImageFile(wr.cover_path, false)
            if bb then
                cover_bb, cover_w, cover_h, disposable = bb, bb:getWidth(), bb:getHeight(), true
            end
        end
    end
    if not title or title == "" then
        title = file:match("([^/]+)%.[^.]+$") or file
        title = title:gsub("%s+%-%s+.*$", "")
    end
    if authors then authors = authors:gsub("\n", "、") end
    return clean_title(title), authors, cover_bb, cover_w, cover_h, disposable
end

Shelf.bookMeta = function(file) return bookMeta(file) end

-- 封面框：opts = { file=本机书路径 | wr_book=微信读书书目, title=, w=, h=, badge="读完"? }
-- 封面按框等比缩放后居中，1px 描边；没有封面画书名占位
function Shelf.coverBox(opts)
    local w, h = opts.w, opts.h
    local bb, bw, bh, disposable
    if opts.file then
        local _, _, cbb, cw, ch, disp = bookMeta(opts.file)
        bb, bw, bh, disposable = cbb, cw, ch, disp
    elseif opts.wr_book then
        local path = IFeatures.weread() and require("apps/filemanager/wereaderdata").coverPath(opts.wr_book)
        if path then
            local ok, img = pcall(function() return require("ui/renderimage"):renderImageFile(path, false) end)
            if ok and img then bb, bw, bh, disposable = img, img:getWidth(), img:getHeight(), true end
        end
    end
    local box
    if bb and bw and bh and bw > 0 and bh > 0 then
        local scale = math.min((w - 2) / bw, (h - 2) / bh)
        local img = ImageWidget:new{ image = bb, scale_factor = scale, image_disposable = disposable }
        img:_render()
        local sz = img:getSize()
        box = FrameContainer:new{ width = sz.w + 2, height = sz.h + 2, padding = 0, margin = 0, bordersize = 1, img }
    else
        box = FrameContainer:new{
            width = w, height = h, padding = px(10), margin = 0, bordersize = px(2),
            CenterContainer:new{
                dimen = Geom:new{ w = w - px(24), h = h - px(24) },
                TextBoxWidget:new{ text = clean_title(opts.title or ""), face = face(24, true), width = w - px(24), alignment = "center" },
            },
        }
    end
    local inner = box
    local inner_w = box:getSize().w
    if opts.badge then
        local OverlapGroup = require("ui/widget/overlapgroup")
        local RightContainer = require("ui/widget/container/rightcontainer")
        local bsz = box:getSize()
        local tag = FrameContainer:new{
            padding = px(4), padding_left = px(8), padding_right = px(8), margin = 0, bordersize = px(2),
            background = Blitbuffer.COLOR_WHITE,
            TextWidget:new{ text = opts.badge, face = face(22) },
        }
        inner = OverlapGroup:new{
            dimen = Geom:new{ w = bsz.w, h = bsz.h },
            box,
            RightContainer:new{ dimen = Geom:new{ w = bsz.w - px(6), h = tag:getSize().h + px(12) }, tag },
        }
    end
    if opts.bare then return inner end -- 不套定宽框：继续阅读卡里要封面左缘贴齐
    local c = CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, inner }
    c._cover_w = inner_w -- 实际封面宽，给网格与卡片对齐用
    return c
end

function Shelf.percent(file)
    -- 微信读书的书用插件记录的整书进度（侧车里只是单章文件的进度）
    local okw, wr = pcall(Shelf.wereadInfo, file)
    if okw and wr then return wr.pct, wr.finished and "complete" or "reading" end
    local BookList = require("ui/widget/booklist")
    local info = BookList.getBookInfo(file)
    return info and info.percent_finished, info and info.status
end

function Shelf.progressText(pct, status)
    if status == "complete" then return "已读完" end
    if not pct then return "未读" end
    local p = pct * 100
    if p < 1 then return "刚开始读" end
    return string.format("读到 %d%%", math.floor(p + 0.5))
end

-- 构建卡片；没有在读的书返回 nil
function Shelf.buildCard(open_callback)
    local file = Shelf.lastBook()
    if not file then return nil end
    local title, authors, cover_bb, cw, ch, disposable = bookMeta(file)
    local pct, status = Shelf.percent(file)
    return Shelf.buildCardWith{
        title = title, authors = authors,
        cover_bb = cover_bb, cover_w = cw, cover_h = ch, cover_disposable = disposable,
        progress_text = Shelf.progressText(pct, status),
        callback = function() open_callback(file) end,
    }
end

-- 卡片本体（本机书架与微信读书书架共用）
-- opts: title, authors, cover_bb/cover_w/cover_h（可空）, cover_disposable, progress_text, button_text, callback
function Shelf.buildCardWith(opts)
    local sw = Screen:getWidth()
    local pad = px(40)
    local h = px(250)
    local cover_h = px(210)
    local cover_w = px(150)
    local title, authors, cover_bb, cw, ch = opts.title or "", opts.authors, opts.cover_bb, opts.cover_w, opts.cover_h

    local cover
    if opts.cover_widget then
        cover = opts.cover_widget
    elseif cover_bb then
        local scale = math.min(cover_w / cw, cover_h / ch)
        local img = ImageWidget:new{ image = cover_bb, scale_factor = scale, image_disposable = opts.cover_disposable }
        img:_render()
        local s = img:getSize()
        cover = FrameContainer:new{
            width = s.w + 2, height = s.h + 2, padding = 0, margin = 0, bordersize = 1,
            img,
        }
    else
        cover = FrameContainer:new{
            width = cover_w, height = cover_h, padding = px(10), margin = 0, bordersize = px(2),
            CenterContainer:new{
                dimen = Geom:new{ w = cover_w - px(24), h = cover_h - px(24) },
                TextBoxWidget:new{ text = title, face = face(26, true), width = cover_w - px(24), alignment = "center" },
            },
        }
    end

    local btn_w = px(210)
    local button = chip(opts.button_text or "继续阅读", btn_w, px(84), true, opts.callback, 30)
    -- 分隔线下方留白：让「分隔线→首行封面」与「末行书名→页码」大致等宽
    local gap_below = px(64)
    local card = Kit.Tappable:new{
        width = sw, height = h + px(30) + gap_below, align = "left",
        content = VerticalSpan:new{ width = 0 },
        callback = opts.callback,
    }
    -- 左右内边距：封面左缘 = left，按钮右缘 = 屏宽 - right。
    -- 书架排好网格后用 Shelf.alignHeaderCard 改成与首行最左 / 最右封面对齐。
    function card:alignTo(left, right)
        left, right = math.max(0, math.floor(left)), math.max(0, math.floor(right))
        local key = left .. ":" .. right
        if self._insets == key then return false end
        self._insets = key
        local text_w = sw - left - right - cover_w - px(36) - btn_w - px(20)
        local info = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = "继续阅读", face = face(26), fgcolor = Kit.GRAY },
            VerticalSpan:new{ width = px(10) },
            TextBoxWidget:new{
                text = title, face = face(38, true), width = text_w,
                height = px(100), height_adjust = true, height_overflow_show_ellipsis = true,
            },
            VerticalSpan:new{ width = px(6) },
            TextWidget:new{ text = authors or "", face = face(26), fgcolor = Kit.GRAY, max_width = text_w },
            VerticalSpan:new{ width = px(10) },
            TextWidget:new{ text = opts.progress_text or "", face = face(28) },
        }
        local row = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = left },
            LeftContainer:new{ dimen = Geom:new{ w = cover_w, h = h }, cover }, -- 封面靠左，左缘精确落在 left
            HorizontalSpan:new{ width = px(36) },
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = h }, info },
            HorizontalSpan:new{ width = px(20) },
            button,
        }
        self[1] = LeftContainer:new{
            dimen = Geom:new{ w = sw, h = self.height },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = px(10) },
                row,
                VerticalSpan:new{ width = px(18) },
                Kit.line(sw, px(2), Blitbuffer.COLOR_LIGHT_GRAY), -- 浅灰，不抢网格的视线
                VerticalSpan:new{ width = gap_below },
            },
        }
        return true
    end
    card:alignTo(pad, pad)
    return card
end

-- 让书架顶部卡片与网格首行对齐：卡片封面左缘 = 首行最左封面左缘，按钮右缘 = 首行最右封面右缘。
-- menu: 已算好 item_margin / item_width 的网格菜单；first_row: 首行格子（各带 _cover_w = 封面框宽）。
-- 返回 true 表示卡片布局有变化（调用方负责重绘）。
function Shelf.alignHeaderCard(menu, first_row)
    local card = menu and menu.title_bar and menu.title_bar.extra_widget
    if not (card and card.alignTo and first_row and first_row[1]) then return false end
    local m, w = menu.item_margin or 0, menu.item_width or 0
    local function coverLeft(col, cw) -- 格子里封面居中（CenterContainer 取整方式）
        return m + (col - 1) * (w + m) + math.floor((w - cw) / 2)
    end
    local first, last = first_row[1], first_row[#first_row]
    if not (first._cover_w and last._cover_w) then return false end
    local left = coverLeft(1, first._cover_w)
    local right = left -- 首行只有一本时左右对称
    if #first_row > 1 then
        right = Screen:getWidth() - (coverLeft(#first_row, last._cover_w) + last._cover_w)
    end
    return card:alignTo(left, right)
end

-- 顶栏来源标签：本机 + 固定到书架的书库（最多 3 个）+ 全部
-- selected: "local" | 书库序号 | "all"；on_select(key)
function Shelf.sourceTabs(opds, selected, on_select)
    local tabs = { { text = "本机", selected = selected == "local", callback = function() on_select("local") end } }
    local servers = {}
    if opds and opds.getShelfServers then
        local ok, list = pcall(opds.getShelfServers, opds)
        if ok then servers = list end
    end
    for i, srv in ipairs(servers) do
        if i > 3 then break end
        table.insert(tabs, {
            text = srv.title, selected = selected == srv.idx,
            callback = function() on_select(srv.idx) end,
        })
    end
    if opds then
        table.insert(tabs, { text = "全部", selected = selected == "all", callback = function() on_select("all") end })
    end
    -- 「微信读书」标签：一律放在右上角第一个
    -- iReader 完整版用闭源 wereader（打开我们画的云端书架）；其余（Kindle / 分享版）用开源 weread.koplugin
    -- （打开插件书架，界面由 wereadpluginskin 换皮）
    local provider = require("ireader/target").wereadProvider()
    if (provider == "wereader" and IFeatures.weread() and require("apps/filemanager/wereaderdata").installed())
            or (provider == "weread" and Shelf.weReadHost(opds)) then
        table.insert(tabs, 1, { text = "微信读书", selected = selected == "weread", callback = function()
            on_select("weread")
        end })
    end
    return tabs
end

-- 来源标签统一处理：local=本机书架 / weread=微信读书书架 / 其余=OPDS 书库
function Shelf.onSourceTab(fm, key)
    Shelf.rememberSource(key)
    -- 没有闭源集成时没有 wereadhome（首页切页）：没有叠加页可切 / 可关
    local Home = IFeatures.weread() and require("apps/filemanager/wereadhome") or nil
    if key == "local" then
        if Home then Home.switchTo("local", fm) end
    elseif key == "weread" then
        if require("ireader/target").wereadProvider() == "weread" then
            Shelf.openWeRead(fm)
        elseif Home then
            Home.switchTo("weread", fm)
        end
    else
        if Home then Home.closePage() end
        if fm and fm.opds then fm.opds:onShowOPDSCatalog(key ~= "all" and key or nil) end
    end
end

-- 开源插件：记住上次停在哪个来源（weread / 其它），书架重建（开机、关书）时据此决定先落在哪一页
local SOURCE_KEY = "ireader_shelf_source"
function Shelf.rememberSource(key)
    if require("ireader/target").wereadProvider() ~= "weread" then return end
    local v = key == "weread" and "weread" or "local"
    if G_reader_settings:readSetting(SOURCE_KEY) ~= v then G_reader_settings:saveSetting(SOURCE_KEY, v) end
end

-- 书架建好后调用：上次停在「微信读书」（默认就是它）且已登录，就直接打开微信读书书架
function Shelf.openDefaultWeRead(fm)
    if require("ireader/target").wereadProvider() ~= "weread" then return end
    if G_reader_settings:readSetting(SOURCE_KEY, "weread") ~= "weread" then return end
    local plugin = fm and fm.weread
    local ok, logged = pcall(function() return plugin.settings:is_api_configured() end)
    if ok and logged then Shelf.openWeRead(fm) end
end

-- 开源 weread.koplugin 挂在 FileManager.weread 上
function Shelf.weReadHost(opds)
    local fm = opds and opds.ui
    if not (fm and fm.weread) then
        fm = require("apps/filemanager/filemanager").instance
    end
    return fm and fm.weread and fm or nil
end

function Shelf.openWeRead(fm)
    if require("ireader/target").wereadProvider() == "weread" then
        fm = (fm and fm.weread) and fm or Shelf.weReadHost()
        if fm then fm:handleEvent(require("ui/event"):new("ShowWeReadBookshelf")) end
        return
    end
    if IFeatures.weread() then require("apps/filemanager/wereadhome").switchTo("weread", fm) end
end

-- 书架头部：继续阅读卡（没有在读的书时返回 nil）
function Shelf.buildHeader(fm)
    return Shelf.buildCard(function(file) fm:openFile(file) end)
end

-- 书籍长按：底部操作单（封面头 + 常用操作 + 更多操作）
function Shelf.showBookSheet(fm, chooser, item)
    local file = item.path
    local sw = Screen:getWidth()
    local title, authors, cover_bb, cw, ch, cover_disposable = bookMeta(file)
    local pct, status = Shelf.percent(file)
    local BookList = require("ui/widget/booklist")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local UIManager = require("ui/uimanager")
    local lfs_attr = lfs.attributes(file) or {}
    local size_mb = (lfs_attr.size or 0) / 1048576
    local ext = (file:match("%.([^.]+)$") or ""):upper()

    -- 头部：封面 + 书名 / 作者 / 进度 · 格式 · 大小
    local cover_w, cover_h = px(120), px(170)
    local cover
    if cover_bb then
        local img = ImageWidget:new{ image = cover_bb, scale_factor = math.min(cover_w / cw, cover_h / ch), image_disposable = cover_disposable }
        img:_render()
        local sz = img:getSize()
        cover = FrameContainer:new{ width = sz.w + 2, height = sz.h + 2, padding = 0, margin = 0, bordersize = 1, img }
    else
        cover = FrameContainer:new{
            width = cover_w, height = cover_h, padding = px(8), margin = 0, bordersize = px(2),
            CenterContainer:new{
                dimen = Geom:new{ w = cover_w - px(20), h = cover_h - px(20) },
                TextBoxWidget:new{ text = title, face = face(22, true), width = cover_w - px(20), alignment = "center" },
            },
        }
    end
    local text_w = sw - px(44) - cover_w - px(36) - px(44)
    local header = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = px(44) },
        CenterContainer:new{ dimen = Geom:new{ w = cover_w, h = cover_h + px(50) }, cover },
        HorizontalSpan:new{ width = px(36) },
        VerticalGroup:new{
            align = "left",
            TextBoxWidget:new{
                text = title, face = face(36, true), width = text_w,
                height = px(96), height_adjust = true, height_overflow_show_ellipsis = true,
            },
            VerticalSpan:new{ width = px(8) },
            TextWidget:new{ text = authors or "", face = face(26), fgcolor = Kit.GRAY, max_width = text_w },
            VerticalSpan:new{ width = px(12) },
            TextWidget:new{
                text = string.format("%s · %s · %.1f MB", Shelf.progressText(pct, status), ext, size_mb),
                face = face(24), fgcolor = Kit.GRAY, max_width = text_w,
            },
        },
    }

    local refresh = function() chooser:refreshPath() end
    local doc = BookList.hasBookBeenOpened(file) and BookList.getDocSettings(file) or file
    local status_row = filemanagerutil.genStatusButtonsRow(doc, refresh)
    local actions = {
        {
            icon = "wr.cat.book", text = pct and "继续阅读" or "开始阅读",
            callback = function() fm:openFile(file) end,
        },
        status == "complete" and {
            icon = "wr.cat.circle", text = "标记为在读",
            callback = status_row[1].callback,
        } or {
            icon = "wr.cat.check", text = "标记为读完",
            callback = status_row[3].callback,
        },
        {
            icon = "wr.collection", text = "加入书单",
            callback = fm.collections:genAddToCollectionButton(file, nil, refresh).callback,
        },
        {
            icon = "wr.info", text = "书籍信息",
            callback = filemanagerutil.genBookInformationButton(doc, nil, function() end).callback,
        },
        {
            icon = "wr.trash", text = "删除", separator = true,
            callback = function() fm:showDeleteFileDialog(file, refresh) end,
        },
        {
            icon = "wr.more", text = "更多操作", value = "重命名、复制、封面…",
            callback = function() chooser:showFileDialog(item) end,
        },
    }
    UIManager:show(require("ui/widget/wereadactionsheet"):new{
        header = VerticalGroup:new{ VerticalSpan:new{ width = px(20) }, header, VerticalSpan:new{ width = px(20) } },
        actions = actions,
    })
end

return Shelf

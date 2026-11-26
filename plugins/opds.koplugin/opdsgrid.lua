--[[--
iReader: OPDS 书目封面网格（微信读书书城式 3×3）。

书目页（多数条目可下载）切换成封面网格，目录/导航页仍用列表。
封面按当前页逐张下载（每张之间让出 UI 循环，点按不卡），
缓存在 koreader/cache/opds-covers/，第二次打开直接读本地。

okooo5km(十里)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
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
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local md5 = require("ffi/sha2").md5
local socket = require("socket")
local socketutil = require("socketutil")
local Screen = Device.screen

local px, face = Kit.px, Kit.face

local COLS, ROWS = 3, 3
local CACHE_DIR = DataStorage:getDataDir() .. "/cache/opds-covers"

local Grid = {}

-- 当前条目表是不是「书」的列表（过半条目可下载）
function Grid.isBookList(item_table)
    local n, books = 0, 0
    for _, it in ipairs(item_table or {}) do
        n = n + 1
        if it.acquisitions and #it.acquisitions > 0 then books = books + 1 end
    end
    return n > 0 and books * 2 >= n
end

---------------------------------------------------------------- 封面缓存
local EXTS = { "jpg", "png", "gif", "webp" }

-- 已缓存则返回路径，否则 nil
local function cachedPath(url)
    local base = CACHE_DIR .. "/" .. md5(url)
    for _, ext in ipairs(EXTS) do
        local p = base .. "." .. ext
        if lfs.attributes(p, "mode") == "file" then return p end
    end
end

-- 按文件头判断格式（KOReader 解码按扩展名走）
local function sniffExt(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local head = fh:read(12) or ""
    fh:close()
    if head:sub(1, 2) == "\255\216" then return "jpg" end
    if head:sub(1, 4) == "\137PNG" then return "png" end
    if head:sub(1, 3) == "GIF" then return "gif" end
    if head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WEBP" then return "webp" end
end

local function download(url, user, password)
    local hit = cachedPath(url)
    if hit then return hit end
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(CACHE_DIR)
    end
    local base = CACHE_DIR .. "/" .. md5(url)
    local tmp = base .. ".part"
    local fh = io.open(tmp, "wb")
    if not fh then return nil end
    socketutil:set_timeout(5, 15)
    local code = socket.skip(1, http.request{
        url = url, method = "GET",
        headers = { ["Accept-Encoding"] = "identity" },
        sink = ltn12.sink.file(fh),
        user = user, password = password,
    })
    socketutil:reset_timeout()
    local ext = code == 200 and sniffExt(tmp)
    if ext then
        local path = base .. "." .. ext
        os.rename(tmp, path)
        return path
    end
    os.remove(tmp)
    logger.info("OPDS grid: cover download failed", code, url)
    return nil
end

---------------------------------------------------------------- 单格
local Cell = InputContainer:extend{
    entry = nil, menu = nil, width = nil, height = nil, cover_path = nil,
}

function Cell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.caption_h = px(100)
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Hold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
    self:build()
end

function Cell:build()
    local cw, ch = self.width - px(16), self.height - self.caption_h
    local cover
    if self.cover_path then
        local ok, img = pcall(function()
            local RenderImage = require("ui/renderimage")
            local bb = RenderImage:renderImageFile(self.cover_path, false)
            if not bb then return nil end
            local scale = math.min(cw / bb:getWidth(), ch / bb:getHeight())
            local w = ImageWidget:new{ image = bb, scale_factor = scale, image_disposable = true }
            w:_render()
            return w
        end)
        if ok and img then
            local s = img:getSize()
            cover = FrameContainer:new{
                width = s.w + 2, height = s.h + 2, padding = 0, margin = 0, bordersize = 1,
                img,
            }
        else
            self.cover_path = nil
        end
    end
    if not cover then
        -- 占位：书名竖排在细框里，像没封面的书
        local w = math.floor(ch * 0.7)
        cover = FrameContainer:new{
            width = w, height = ch, padding = px(12), margin = 0, bordersize = px(2),
            CenterContainer:new{
                dimen = Geom:new{ w = w - px(28), h = ch - px(28) },
                TextBoxWidget:new{
                    text = self.entry.title or self.entry.text or "",
                    face = face(26, true), width = w - px(28), alignment = "center",
                    height = ch - px(28), height_adjust = true, height_overflow_show_ellipsis = true,
                },
            },
        }
    end
    local title = Kit.clean_title(self.entry.title or self.entry.text or "")
    local author = self.entry.author
    if author == "Unknown Author" or author == "未知作者" then author = nil end
    self[1] = VerticalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = self.width, h = ch }, cover },
        VerticalSpan:new{ width = px(8) },
        TextBoxWidget:new{
            text = title, face = face(24), width = self.width - px(8), alignment = "center",
            height = px(60), height_adjust = true, height_overflow_show_ellipsis = true,
        },
        TextWidget:new{
            text = author or "", face = face(20), fgcolor = Blitbuffer.COLOR_GRAY_5,
            max_width = self.width - px(8),
        },
    }
end

function Cell:setCover(path)
    self.cover_path = path
    if self[1] then self[1]:free() end
    self:build()
end

function Cell:onTap()
    self.menu:onMenuSelect(self.entry)
    return true
end

function Cell:onHold()
    self.menu:onMenuHold(self.entry)
    return true
end

-- 每次进程只做一次：封面缓存超过 400 张时删掉最旧的，留 300 张
local pruned = false
local function pruneCache()
    if pruned then return end
    pruned = true
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then return end
    local files = {}
    for f in lfs.dir(CACHE_DIR) do
        if f ~= "." and f ~= ".." then
            local p = CACHE_DIR .. "/" .. f
            table.insert(files, { p = p, t = lfs.attributes(p, "modification") or 0 })
        end
    end
    if #files <= 400 then return end
    table.sort(files, function(a, b) return a.t < b.t end)
    for i = 1, #files - 300 do os.remove(files[i].p) end
end

---------------------------------------------------------------- 整页布局（替代 Menu:updateItems）
function Grid.updateItems(menu, select_number)
    pruneCache()
    local old_dimen = menu.dimen and menu.dimen:copy()
    menu.layout = {}
    menu.item_group:clear()
    menu.page_info:resetLayout()
    menu.return_button:resetLayout()
    menu.content_group:resetLayout()

    menu.perpage = COLS * ROWS
    local items = menu.item_table
    menu.page_num = math.max(1, math.ceil(#items / menu.perpage))
    if menu.page > menu.page_num then menu.page = menu.page_num end
    if menu.page < 1 then menu.page = 1 end

    local top_h = (menu.title_bar and not menu.no_title) and menu.title_bar:getHeight() or 0
    local bottom_h = math.max(menu.page_return_arrow:getSize().h, menu.page_info_text:getSize().h)
        + Size.padding.button
    local avail_h = menu.inner_dimen.h - top_h - bottom_h
    local margin = px(14)
    local cell_w = math.floor((menu.inner_dimen.w - (COLS + 1) * margin) / COLS)
    local cell_h = math.floor((avail_h - (ROWS + 1) * margin) / ROWS)

    menu._grid_gen = (menu._grid_gen or 0) + 1
    local gen = menu._grid_gen
    local queue = {}
    local offset = (menu.page - 1) * menu.perpage
    local row, line_layout
    for i = 1, menu.perpage do
        local index = offset + i
        local entry = items[index]
        if not entry then break end
        entry.idx = index
        if (i - 1) % COLS == 0 then
            if line_layout then table.insert(menu.layout, line_layout) end
            line_layout = {}
            table.insert(menu.item_group, VerticalSpan:new{ width = margin })
            row = HorizontalGroup:new{ HorizontalSpan:new{ width = margin } }
            table.insert(menu.item_group, LeftContainer:new{
                dimen = Geom:new{ w = menu.inner_dimen.w, h = cell_h }, row,
            })
        end
        local url = entry.thumbnail or entry.image
        local cached = url and cachedPath(url)
        local cell = Cell:new{
            entry = entry, menu = menu, width = cell_w, height = cell_h, cover_path = cached,
        }
        table.insert(row, cell)
        table.insert(row, HorizontalSpan:new{ width = margin })
        table.insert(line_layout, cell)
        if url and not cached then table.insert(queue, { cell = cell, url = url }) end
    end
    if line_layout then table.insert(menu.layout, line_layout) end

    menu:updatePageInfo(select_number)
    menu:mergeTitleBarIntoLayout()
    UIManager:setDirty(menu.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(menu.dimen) or menu.dimen
    end)

    -- 逐张下载封面；翻页/离开后旧队列自动作废
    local user, password = menu.root_catalog_username, menu.root_catalog_password
    local function step()
        if menu._grid_gen ~= gen or #queue == 0 then return end
        local job = table.remove(queue, 1)
        local ok, path = pcall(download, job.url, user, password)
        if menu._grid_gen ~= gen then return end
        if ok and path then
            job.cell:setCover(path)
            if job.cell.dimen and job.cell.dimen.x then
                UIManager:setDirty(menu.show_parent, "ui", job.cell.dimen)
            end
        end
        UIManager:scheduleIn(0.05, step)
    end
    if #queue > 0 then UIManager:scheduleIn(0.3, step) end
end

return Grid

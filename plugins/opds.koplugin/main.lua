local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local LuaSettings = require("luasettings")
local OPDSBrowser = require("opdsbrowser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local OPDS = WidgetContainer:extend{
    name = "opds",
    settings_file = DataStorage:getSettingsDir() .. "/opds.lua",
    settings = nil,
    opds_settings = nil,
    servers = nil,
    downloads = nil,
    pending_syncs = nil,
    updated = nil,
    default_servers = {
        {
            title = "Project Gutenberg",
            url = "https://m.gutenberg.org/ebooks.opds/?format=opds",
        },
        {
            title = "Standard Ebooks",
            url = "https://standardebooks.org/feeds/opds",
        },
        {
            title = "ManyBooks",
            url = "http://manybooks.net/opds/index.php",
        },
        {
            title = "Internet Archive",
            url = "https://bookserver.archive.org/",
        },
        {
            title = "textos.info (Spanish)",
            url = "https://www.textos.info/catalogo.atom",
        },
        {
            title = "Gallica (French)",
            url = "https://gallica.bnf.fr/opds",
        },
    },
}

function OPDS:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function OPDS:loadSettings()
    if self.settings then return end
    self.settings = LuaSettings:open(self.settings_file)
    if next(self.settings.data) == nil then
        self.updated = true -- first run, force flush
    end
    self.opds_settings = self.settings:readSetting("settings", {})
    self.servers = self.settings:readSetting("servers", self.default_servers)
    self.downloads = self.settings:readSetting("downloads", {})
    self.pending_syncs = self.settings:readSetting("pending_syncs", {})
end

function OPDS:onDispatcherRegisterActions()
    Dispatcher:registerAction("opds_show_catalog",
        {category="none", event="ShowOPDSCatalog", title=_("OPDS Catalog"), filemanager=true,}
    )
end

function OPDS:addToMainMenu(menu_items)
    if not self.ui.document then -- FileManager menu only
        menu_items.opds = {
            text = _("OPDS catalog"),
            callback = function()
                self:onShowOPDSCatalog()
            end,
        }
    end
end

-- iReader: 书架上的书库快捷方式
function OPDS:getShelfServers()
    self:loadSettings()
    local list = {}
    for i, server in ipairs(self.servers) do
        if require("opdsshelf").isOnShelf(server) then
            table.insert(list, { idx = i, title = server.title })
        end
    end
    return list
end

function OPDS:onShowOPDSCatalog(server_idx)
    self:loadSettings()
    -- iReader: 顶栏标签切换书库时，直接替换当前书库页
    if self.opds_browser then
        UIManager:close(self.opds_browser)
        self.opds_browser = nil
    end
    local WeReadTitleBar = require("ui/widget/wereadtitlebar")
    local Shelf = require("apps/filemanager/wereadshelf")
    local nav_row = require("opdsui").newNavRow()
    local selected = server_idx or "all"
    local server = server_idx and self.servers[server_idx]
    local title_bar = WeReadTitleBar:new{
        title = "书架",
        subtitle = server and ("在线书库 · " .. (server.url:match("^%a+://([^/]+)") or server.url)) or "全部在线书库",
        tabs = Shelf.sourceTabs(self, selected, function(key)
            if key == "local" or key == "weread" then
                if self.opds_browser then self.opds_browser.close_callback() end
                if key == "weread" then Shelf.onSourceTab(self.ui, "weread") end
            elseif key ~= selected then
                self:onShowOPDSCatalog(key ~= "all" and key or nil)
            end
        end),
        more_callback = function()
            if self.opds_browser and self.opds_browser.onLeftButtonTap then
                self.opds_browser.onLeftButtonTap()
            end
        end,
        extra_widget = nav_row,
    }
    self.opds_browser = OPDSBrowser:new{
        custom_title_bar = title_bar,
        nav_row = nav_row,
        hide_return_arrow = true,
        settings = self.opds_settings,
        servers = self.servers,
        downloads = self.downloads,
        pending_syncs = self.pending_syncs,
        title = _("OPDS catalog"),
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        _manager = self,
        file_downloaded_callback = function(file)
            self:showFileDownloadedDialog(file)
        end,
        close_callback = function()
            if self.opds_browser.download_list then
                self.opds_browser.download_list.close_callback()
            end
            UIManager:close(self.opds_browser)
            self.opds_browser = nil
            -- iReader: 书架快捷方式有变动时刷新书架头部
            if self.shelf_changed and self.ui.refreshShelfHeader then
                self.shelf_changed = nil
                self.ui:refreshShelfHeader()
            end
            if self.last_downloaded_file then
                if self.ui.file_chooser then
                    local pathname = util.splitFilePathName(self.last_downloaded_file)
                    self.ui.file_chooser:changeToPath(pathname, self.last_downloaded_file)
                end
                self.last_downloaded_file = nil
            end
        end,
    }
    UIManager:show(self.opds_browser)
    -- iReader: 直接进入指定书库（第 1 项是「下载」）
    if server_idx and self.opds_browser.item_table[server_idx + 1] then
        local item = self.opds_browser.item_table[server_idx + 1]
        item.idx = server_idx + 1
        self.opds_browser:onMenuSelect(item)
    end
end

function OPDS:showFileDownloadedDialog(file)
    self.last_downloaded_file = file
    local confirm_box = ConfirmBox:new{
        text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"), BD.filepath(file)),
        ok_text = _("Read now"),
        ok_callback = function()
            self.last_downloaded_file = nil
            self.opds_browser.close_callback()
            if self.ui.document then
                self.ui:switchDocument(file)
            else
                self.ui:openFile(file)
            end
        end,
    }
    -- As the InfoMessage "Downloading" is getting closed, show this ConfirmBox on the next UI tick to avoid e-Ink rendering congestion
    UIManager:nextTick(function()
        UIManager:show(confirm_box)
    end)
end

function OPDS:onFlushSettings()
    if self.updated then
        self.settings:flush()
        self.updated = nil
    end
end

return OPDS

--[[--
iReader: 哪些 OPDS 书库显示在书架快捷行。
shelf == true 显示、false 隐藏；未设置时，自己添加的（非内置）书库默认显示。

okooo5km(十里)
]]

local BUILTIN = {
    ["https://m.gutenberg.org/ebooks.opds/?format=opds"] = true,
    ["https://standardebooks.org/feeds/opds"] = true,
    ["http://manybooks.net/opds/index.php"] = true,
    ["https://bookserver.archive.org/"] = true,
    ["https://www.textos.info/catalogo.atom"] = true,
    ["https://gallica.bnf.fr/opds"] = true,
}

local M = {}

function M.isOnShelf(server)
    if not server then return false end
    if server.shelf ~= nil then return server.shelf and true or false end
    return not BUILTIN[server.url or ""]
end

return M

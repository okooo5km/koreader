--[[--
iReader: 中文长按按词选取。

crengine 对中文只能选单字。这里挂 LanguageSupport 的 WordSelection 钩子：
以点中的字为中心，左右各看最多 MAX_SIDE 个汉字，在词表里找「包含点中字的最长词」，
把选区扩成这个词（查词、划线都随之生效）。找不到就保持单字。

词表 words.txt 由 CC-CEDICT 词头导出（纯汉字、2~8 字），首次长按时懒加载进内存。

okooo5km(十里)
]]

local LanguageSupport = require("languagesupport")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")

local MAX_SIDE = 5   -- 点中字左右各看几个字
local MAX_WORD = 8   -- 词表最长词

local Chinese = WidgetContainer:extend{
    name = "chinese",
    pretty_name = "Chinese",
}

local words -- 懒加载的词集合

local function loadWords(path)
    if words then return words end
    words = {}
    local f = io.open(path .. "/words.txt", "r")
    if not f then
        logger.warn("chinese.koplugin: words.txt not found")
        return words
    end
    for w in f:lines() do words[w] = true end
    f:close()
    return words
end

-- 单个汉字（含扩展 A 区与〇）
local function isHan(ch)
    if not ch or ch == "" then return false end
    local b1, b2, b3 = ch:byte(1, 3)
    if not b3 or #ch ~= 3 then return false end
    local cp = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
    return (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF) or cp == 0x3007
end

function Chinese:init()
    LanguageSupport:registerPlugin(self)
end

function Chinese:supportsLanguage(language_code)
    return language_code and (language_code:match("^zh") ~= nil)
end

function Chinese:onWordSelection(args)
    local cb = args.callbacks
    local pos0 = args.pos0
    local first = cb.get_text_in_range(pos0, cb.get_next_char_pos(pos0))
    if not isHan(first) then return end

    -- 收集左右的字位置：P[k] 是第 k 个字的起点，k=0 为点中的字
    local P, C = { [0] = pos0 }, { [0] = first }
    local lo, hi = 0, 0
    local p = pos0
    for k = -1, -MAX_SIDE, -1 do
        p = cb.get_prev_char_pos(p)
        if not p then break end
        local ch = cb.get_text_in_range(p, P[k + 1])
        if not isHan(ch) then break end
        P[k], C[k], lo = p, ch, k
    end
    p = pos0
    for k = 1, MAX_SIDE + 1 do
        p = cb.get_next_char_pos(p)
        if not p then break end
        P[k] = p
        if k > MAX_SIDE then break end
        local nxt = cb.get_next_char_pos(p)
        local ch = nxt and cb.get_text_in_range(p, nxt)
        if not isHan(ch) then break end
        C[k], hi = ch, k
    end
    if not P[hi + 1] then return end

    local dict = loadWords(self.path)
    -- 找包含 0 号字的最长词；同长度优先从点中字开始的
    local best_i, best_j
    for len = math.min(MAX_WORD, hi - lo + 1), 2, -1 do
        for i = 0, lo, -1 do
            local j = i + len - 1
            if j >= 0 and j <= hi then
                local s = table.concat(C, "", i, j)
                if dict[s] then best_i, best_j = i, j break end
            end
        end
        if best_i then break end
    end
    if not best_i then return end
    logger.dbg("chinese.koplugin: selected", table.concat(C, "", best_i, best_j))
    return { P[best_i], P[best_j + 1] }
end

return Chinese

--[[--
功能开关：核心界面代码统一问这里，别各处自己探测。

分享版（ireader/build_share.sh）不带「微信读书集成」那批文件（wereader* / wereadhome 等、
ui/gohomeflag、读书桌面联动），核心代码靠这里判断集成是否存在，缺失就走「没有微信读书」的分支。
探测只看模块文件在不在，一次探测、结果缓存；完整版文件齐全，行为与以前完全一致。

    F.weread()  微信读书集成（云端书架 / 原生阅读页 / 插件换皮 / 首页底部导航）是否随包
    F.gohome()  读书桌面「回桌面 / 打开书」标记联动是否随包
    F.wereadSkin()  开源 weread.koplugin 的换皮层是否随包（分享版 / Kindle 也带，插件本身在 plugins/weread.koplugin）
    F.anyWeread()   上面两种微信读书任一可用（书架过滤单章缓存、读插件落盘书目时用）

okooo5km(十里)
]]

local F = {}

local cache = {}

local function exists(mod)
    if cache[mod] == nil then
        cache[mod] = package.searchpath(mod, package.path) ~= nil
    end
    return cache[mod]
end

-- 以 wereadhome（首页切页 / 默认书架）和 wereadernative（原生阅读页桥）两个主干模块为准，缺一个都按「没有集成」处理
function F.weread()
    return exists("apps/filemanager/wereadhome") and exists("apps/filemanager/wereadernative")
end

function F.wereadSkin()
    return exists("apps/filemanager/wereadpluginskin")
end

function F.anyWeread()
    return F.weread() or F.wereadSkin()
end

function F.gohome()
    return exists("ui/gohomeflag")
end

return F

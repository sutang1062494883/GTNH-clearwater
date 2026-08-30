-- installer.lua  (OpenComputers) —— 主控端安装器
local component  = require("component")
local filesystem = require("filesystem")
local shell      = require("shell")

-- ===== 配置 =====
-- 主控端仓库（master 分支 / water_control/）：全部文件统一从这里拉，只维护一份
local BASE_URL_MAIN = "https://raw.githubusercontent.com/sutang1062494883/GTNH-clearwater/master/water_control/"

-- 文件清单：src = "main" 表示从主控端 master/water_control 下载
--（保留 src 字段，与监控端安装器风格一致；未来若有文件需要单独分支维护，改这里即可）
local FILE_LIST = {
    { name = "config.lua",       src = "main" },
    { name = "utils.lua",        src = "main" },
    { name = "fluid.lua",        src = "main" },
    { name = "machine.lua",      src = "main" },
    { name = "scheduler.lua",    src = "main" },
    { name = "alert.lua",        src = "main" },
    { name = "report.lua",       src = "main" },
    { name = "persistence.lua",  src = "main" },
    { name = "sync.lua",         src = "main" },
    { name = "ui_config.lua",    src = "main" },
    { name = "ui_draw.lua",      src = "main" },
    { name = "ui_chart.lua",     src = "main" },
    { name = "interaction.lua",  src = "main" },
    { name = "net.lua",          src = "main" },
    { name = "main.lua",         src = "main" },   -- 主控端入口
}

-- 装到“当前工作目录/water_control”，用绝对路径避免歧义
local APP_DIR = (shell.getWorkingDirectory() .. "/water_control"):gsub("//+", "/")
-- ================

local function ensureDir(dir)
    if not filesystem.exists(dir) then
        local ok, err = filesystem.makeDirectory(dir)
        if not ok then error("无法创建目录 " .. dir .. ": " .. tostring(err)) end
    end
end

-- 用系统 wget 下载一个文件，返回 是否成功, 字节数或错误说明
local function wget(url, dest)
    if filesystem.exists(dest) then filesystem.remove(dest) end  -- 避免“已存在”导致 wget 拒绝
    local rc = shell.execute("wget " .. url .. " " .. dest)      -- 阻塞，直到下完
    if filesystem.exists(dest) and filesystem.size(dest) > 0 then
        return true, filesystem.size(dest)
    end
    return false, "wget 返回 " .. tostring(rc) .. " 且文件为空/不存在(多半是 404，请确认源文件已 push 到对应仓库/分支)"
end

local function main()
    if not component.isAvailable("internet") then
        error("未检测到因特网卡(Internet Card)，请先安装。")
    end
    ensureDir(APP_DIR)

    print("== 净化水线主控端 安装器（wget 版） ==")
    print("主控源:  " .. BASE_URL_MAIN)
    print("目标目录: " .. APP_DIR)
    print("文件数:   " .. #FILE_LIST)
    print()

    local ok_count, fail = 0, {}
    for i, item in ipairs(FILE_LIST) do
        local name = item.name
        local url  = BASE_URL_MAIN .. name
        local dest = APP_DIR .. "/" .. name
        local tag  = "[主控]"
        io.write(string.format("[%2d/%2d] %-14s %-18s ", i, #FILE_LIST, tag, name))
        local ok, info = wget(url, dest)
        if ok then
            print("OK  (" .. info .. " bytes)")
            ok_count = ok_count + 1
        else
            print("FAIL")
            fail[#fail + 1] = name .. "(" .. tag .. ") -> " .. tostring(info)
        end
    end

    -- 启动器（带 require 搜索路径引导，从任意目录启动都能加载模块）
    local launcher = APP_DIR .. "/start.lua"
    local f = filesystem.open(launcher, "wb")
    f:write([[
-- start.lua：把应用目录加入 require 搜索路径后加载主控端入口
local appDir = "]] .. APP_DIR .. [["
package.path = appDir .. "/?.lua;" .. appDir .. "/?/init.lua;" .. package.path
local fn, err = loadfile(appDir .. "/main.lua")
if not fn then error(err) end
fn()
]])
    f:close()

    print()
    print("完成: 成功 " .. ok_count .. "/" .. #FILE_LIST)
    if #fail > 0 then
        print("以下文件失败:")
        for _, m in ipairs(fail) do print("  - " .. m) end
        error("安装未完全成功。请确认共享文件已 push 到 master/water_control 目录。")
    end

    print()
    print("启动:  water_control/start   或   lua " .. APP_DIR .. "/main.lua")
    print("自启:  把  loadfile(\"" .. APP_DIR .. "/main.lua\")()  写入 /autorun.lua")
end

local ok, err = xpcall(main, debug.traceback)   -- 不要 pcall 吞错
if not ok then print("\n[安装出错]\n" .. tostring(err)) end

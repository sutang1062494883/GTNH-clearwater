-- installer.lua  (OpenComputers) —— 监控端 (monitor 分支) 安装器

local component  = require("component")
local filesystem = require("filesystem")
local shell      = require("shell")

-- ===== 配置 =====
-- raw 地址格式: https://raw.githubusercontent.com/<user>/<repo>/<branch>/<path>/
-- 这里 branch = monitor ，目录 = water_control_monitor
local BASE_URL = "https://raw.githubusercontent.com/sutang1062494883/GTNH-clearwater/monitor/water_control_monitor/"

-- 固定清单：与本地 water_control_monitor 截图 1:1（共 15 个）
local FILE_LIST = {
    "alert.lua",        -- 2 KB
    "config.lua",       -- 4 KB
    "fluid.lua",        -- 5 KB
    "interaction.lua",  -- 9 KB
    "machine.lua",      -- 6 KB
    "monitor.lua",      -- 4 KB  ← 监控端入口
    "net.lua",          -- 3 KB
    "persistence.lua",  -- 5 KB
    "report.lua",       -- 3 KB
    "scheduler.lua",    -- 7 KB
    "sync.lua",         -- 4 KB
    "ui_chart.lua",     -- 13 KB
    "ui_config.lua",    -- 2 KB
    "ui_draw.lua",      -- 25 KB
    "utils.lua",        -- 3 KB
}

-- 装到“当前工作目录/water_control_monitor”，用绝对路径避免歧义，
-- 也避免和主控端的 water_control 目录互相覆盖
local APP_DIR = (shell.getWorkingDirectory() .. "/water_control_monitor"):gsub("//+", "/")
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
    return false, "wget 返回 " .. tostring(rc) .. " 且文件为空/不存在(多半是 404，请确认该文件已 push 到 GitHub 的 monitor 分支 / water_control_monitor 目录)"
end

local function main()
    if not component.isAvailable("internet") then
        error("未检测到因特网卡(Internet Card)，请先安装。")
    end
    ensureDir(APP_DIR)

    print("== 净化水线监控端 安装器 (wget 版, monitor 分支) ==")
    print("源:       " .. BASE_URL)
    print("目标目录: " .. APP_DIR)
    print("文件数:   " .. #FILE_LIST)
    print()

    local ok_count, fail = 0, {}
    for i, name in ipairs(FILE_LIST) do
        local url  = BASE_URL .. name
        local dest = APP_DIR .. "/" .. name
        io.write(string.format("[%2d/%2d] %-20s ", i, #FILE_LIST, name))
        local ok, info = wget(url, dest)
        if ok then
            print("OK  (" .. info .. " bytes)")
            ok_count = ok_count + 1
        else
            print("FAIL")
            fail[#fail + 1] = name .. " -> " .. tostring(info)
        end
    end

    -- 启动器（不依赖不存在的 io/os）；监控端入口是 monitor.lua
    local launcher = APP_DIR .. "/start.lua"
    local f = filesystem.open(launcher, "wb")
    f:write('local fn, err = loadfile("' .. APP_DIR .. '/monitor.lua")\n' ..
            'if not fn then error(err) end\nfn()\n')
    f:close()

    print()
    print("完成: 成功 " .. ok_count .. "/" .. #FILE_LIST)
    if #fail > 0 then
        print("以下文件失败:")
        for _, m in ipairs(fail) do print("  - " .. m) end
        error("安装未完全成功。请检查网络环境")
    end

    print()
    print("请按照wiki中的步骤执行程序")
end

local ok, err = xpcall(main, debug.traceback)   -- 不要 pcall 吞错
if not ok then print("\n[安装出错]\n" .. tostring(err)) end

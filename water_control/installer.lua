-- installer.lua  (OpenComputers) —— 用系统 wget 下载，最稳
local component  = require("component")
local filesystem = require("filesystem")
local shell      = require("shell")

-- ===== 配置 =====
local BASE_URL = "https://raw.githubusercontent.com/sutang1062494883/GTNH-clearwater/master/water_control/"
local FILE_LIST = {
    "config.lua", "utils.lua", "fluid.lua", "machine.lua",
    "scheduler.lua", "alert.lua", "report.lua",
    "persistence.lua", "sync.lua", "ui_config.lua",
    "ui_draw.lua", "ui_chart.lua", "interaction.lua",
    "net.lua", "main.lua",
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
    return false, "wget 返回 " .. tostring(rc) .. " 且文件为空/不存在(多半是 404，请确认文件已 push 到 GitHub)"
end

local function main()
    if not component.isAvailable("internet") then
        error("未检测到因特网卡(Internet Card)，请先安装。")
    end
    ensureDir(APP_DIR)

    print("== 净化水线总控系统 安装器 (wget 版) ==")
    print("源:       " .. BASE_URL)
    print("目标目录: " .. APP_DIR)
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

    -- 启动器（不依赖不存在的 io/os）
    local launcher = APP_DIR .. "/start.lua"
    local f = filesystem.open(launcher, "wb")
    f:write('local fn, err = loadfile("' .. APP_DIR .. '/main.lua")\n' ..
            'if not fn then error(err) end\nfn()\n')
    f:close()

    print()
    print("完成: 成功 " .. ok_count .. "/" .. #FILE_LIST)
    if #fail > 0 then
        print("以下文件失败:")
        for _, m in ipairs(fail) do print("  - " .. m) end
        error("安装未完全成功。若提示 404/文件为空，请去 GitHub 确认这些文件已 push 到 master 分支的 water_control/ 目录。")
    end

    print()
    print("启动:lua " .. APP_DIR .. "/main.lua")
end

local ok, err = xpcall(main, debug.traceback)   -- 不要 pcall 吞错
if not ok then print("\n[安装出错]\n" .. tostring(err)) end

-- installer.lua
local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")

-- ===== 配置区域（可根据需要修改） =====
local BASE_URL = "http://example.com/watercontrol/"   -- 末尾带斜杠
local FILE_LIST = {
    "config.lua", "utils.lua", "fluid.lua", "machine.lua",
    "scheduler.lua", "alert.lua", "report.lua",
    "persistence.lua", "sync.lua", "ui_config.lua",
    "ui_draw.lua", "ui_chart.lua", "interaction.lua",
    "net.lua", "main.lua"
}
local APP_DIR = "/water_control"   -- 安装到哪个目录
-- ====================================

-- 获取因特网卡（如果有多张，自动取第一张）
local function getInternet()
    for address, _ in component.list("internet") do
        local proxy = component.proxy(address)
        if proxy then return proxy end
    end
    return nil
end

-- HTTP GET 下载文件到指定路径
local function downloadFile(url, path)
    local internet = getInternet()
    if not internet then error("未检测到因特网卡，请先安装并配置网络") end
    
    local success, response = pcall(internet.request, url)
    if not success or not response then
        error("无法连接到服务器: " .. tostring(response))
    end
    
    local ok, response = pcall(response.finishConnect)  -- 等待连接完成
    if not ok then error("连接失败: " .. tostring(response)) end
    
    local code = response.responseCode
    if code >= 300 and code < 400 then
        -- 处理重定向
        local newUrl = response.headers["Location"] or response.headers["location"]
        if newUrl then
            print("重定向到: " .. newUrl)
            return downloadFile(newUrl, path)
        else
            error("服务器返回重定向但未提供Location头")
        end
    elseif code ~= 200 then
        error("HTTP错误 " .. code)
    end
    
    -- 读取全部数据并写入文件
    local data = {}
    local chunk = response.read(4096)
    while chunk do
        table.insert(data, chunk)
        chunk = response.read(4096)
    end
    response.close()
    
    local content = table.concat(data)
    local file = io.open(path, "w")
    if file then
        file:write(content)
        file:close()
        return true
    else
        error("无法写入文件: " .. path)
    end
end

-- 主流程
local function main()
    if not filesystem.exists(APP_DIR) then
        filesystem.makeDirectory(APP_DIR)
    end
    
    print("开始下载净化水线总控系统...")
    for _, filename in ipairs(FILE_LIST) do
        local url = BASE_URL .. filename
        local dest = APP_DIR .. "/" .. filename
        print("下载: " .. filename)
        downloadFile(url, dest)
    end

    -- 创建启动脚本（方便用户直接 `rc` 或手动运行）
    local launcher = APP_DIR .. "/start.lua"
    local f = io.open(launcher, "w")
    f:write([[
        shell = require("shell")
        os.execute("lua " .. ]] .. APP_DIR .. [[ .. "/main.lua")
    ]])
    f:close()
    
    print("安装完成！")
    print("请运行以下命令启动程序：")
    print("  lua " .. APP_DIR .. "/main.lua")
    print("或添加开机自启：")
    print("  echo 'lua " .. APP_DIR .. "/main.lua' >> /etc/rc.d/boot.lua")
end

pcall(main)
print("安装脚本执行完毕。")
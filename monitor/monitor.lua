-- main.lua
-- 接收端（镜像端）入口：无线同步接收 + UI渲染 + 只读交互
local computer = require("computer")
local event = require("event")
local cfgModule = require("config")
local CONFIG = cfgModule.CONST and cfgModule.CONFIG or cfgModule.CONFIG
local UI = require("ui_config")
local ui_draw = require("ui_draw")
local interaction = require("interaction")
local net = require("net")
local sync = require("sync")

-- 标记为只读镜像端，自动禁用控制按钮
UI.readonly = true

-- 重绘回调包装
local function redrawAll(force)
    ui_draw.renderAll(force)
end

-- ==================== 主循环 ====================
local function mainLoop()
    while true do
        -- 先拉取事件，不提前解包所有参数，按事件类型分别处理
        local ev = { event.pull(1) }
        local eventName = ev[1]

        -- 1. 处理无线同步数据
        if eventName == "modem_message" then
            -- modem_message 参数顺序：event, receiverAddr, senderAddr, port, distance, data1, data2...
            local port = ev[4]
            local magic = ev[6]
            local seq = ev[7]
            local idx = ev[8]
            local total = ev[9]
            local ver = ev[10]
            local chunk = ev[11]

            if port == CONFIG.SYNC.PORT then
                local payload = net.feedMessage(magic, seq, idx, total, ver, chunk)
                if payload then
                    local snap = sync.unserialize(payload)
                    if snap then
                        sync.applySnapshot(snap)
                        -- 更新同步状态
                        UI.syncStatus = "已连接"
                    end
                end
            end

        -- 2. 处理屏幕点击交互
        elseif eventName == "touch" then
            -- touch 参数顺序：event, screenAddr, x, y, button, playerName
            local x = ev[3]
            local y = ev[4]
            interaction.handleClick(x, y, redrawAll)

        -- 3. 处理中断退出（Ctrl+C）
        elseif eventName == "interrupted" then
            UI.gpu.setBackground(0x000000)
            UI.gpu.setForeground(0xffffff)
            UI.gpu.fill(1, 1, UI.W, UI.H, " ")
            UI.gpu.set(1, 1, "接收端已退出")
            return
        end

        -- 清理过期的分片缓存，避免内存泄漏
        net.gcReassembly()

        -- 脏区域自动重绘（面板无变化则自动跳过，节省性能）
        ui_draw.renderAll()
    end
end

-- ==================== 程序入口 ====================
local function main()
    -- 设置分辨率，与控制端保持一致
    local maxW, maxH = UI.gpu.maxResolution()
    UI.gpu.setResolution(math.min(maxW, 160), math.min(maxH, 50))
    ui_draw.calculateLayout()

    -- 初始化无线网卡
    local netOk, netMsg = net.initialize()
    ui_draw.appendLog(netMsg)

    ui_draw.appendLog("[系统] 净水线监控接收端启动完成")
    ui_draw.appendLog("[提示] 等待控制端同步数据...")
    ui_draw.appendLog("[提示] 点击顶部标签切换总览/详细报表")
    ui_draw.appendLog("[提示] 点击等级行查看并行参数与短时趋势")

    -- 首次全量渲染
    ui_draw.renderAll(true)
    mainLoop()
end

-- ==================== 启动与异常保护 ====================
local ok, err = xpcall(main, debug.traceback)
if not ok then
    UI.gpu.setBackground(0x000000)
    UI.gpu.setForeground(0xff0000)
    UI.gpu.fill(1, 1, UI.W, UI.H, " ")
    UI.gpu.set(1, 1, "程序崩溃: " .. tostring(err))
end
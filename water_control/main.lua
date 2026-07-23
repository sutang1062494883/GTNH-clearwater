-- main.lua
-- 程序入口：初始化、主循环（脏区域重绘 + 流体缓存 + 无线广播）

local computer = require("computer")
local event = require("event")

local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local fluid = require("fluid")
local machine = require("machine")
local scheduler = require("scheduler")
local report = require("report")
local net = require("net")
local sync = require("sync")
local UI = require("ui_config")
local ui_draw = require("ui_draw")
local interaction = require("interaction")

-- 控制端非只读
UI.readonly = false

-- 交互回调包装：默认非 force，靠指纹自动决定重绘面板
local function redrawAll(force)
    ui_draw.renderAll(force)
end

-- ==================== 主循环 ====================
local function mainLoop()
    UI._lastFluidQuery = 0     -- 流体查询节流计时器
    UI.lastTick = computer.uptime()
    UI.lastSampleTime = computer.uptime()
    UI._lastBroadcast = 0
    UI._syncSeq = 0

    while true do
        -- 开帧：本帧内所有 getAmount 只读缓存
        if fluid.beginFrame then fluid.beginFrame() end

        local eventName, _, x, y = event.pull(1)
        -- 【新增】每帧预取
        if fluid.prefetch and CONFIG.FLUID_CACHE.PREFETCH then
            local qNow = computer.uptime()
            local qInt = (CONFIG.FLUID_CACHE.QUERY_INTERVAL) or 5.0
            if qNow - UI._lastFluidQuery >= qInt then
                UI._lastFluidQuery = qNow
                pcall(fluid.prefetch)
            end
        end
        
        if eventName == "touch" then
            interaction.handleClick(x, y, redrawAll)
        elseif eventName == "interrupted" then
            scheduler.shutdownAll()
            UI.gpu.setBackground(0x000000)
            UI.gpu.setForeground(0xffffff)
            UI.gpu.fill(1, 1, UI.W, UI.H, " ")
            UI.gpu.set(1, 1, "系统已退出")
            return
        end

        pcall(report.sampleFluidHistory)

        -- 详情图自动返回总览
        if UI.currentTab == "overview" and UI.chartMode == "detail"
            and computer.uptime() - UI.detailSwitchTime >= 20 then
            UI.chartMode = "overview"
            UI.currentDetailLevel = nil
        end

        -- 定时业务逻辑
        local now = computer.uptime()
        local interval = ui_draw.getPlantRunning()
            and CONFIG.CHECK_INTERVAL_RUNNING or CONFIG.CHECK_INTERVAL_STOPPED
        local businessTick = UI.systemRunning and (now - UI.lastTick >= interval)

        if businessTick then
            UI.lastTick = now
            -- 业务轮开始时预取流体（一次组件调用喂饱本轮）
            if fluid.prefetch and CONFIG.FLUID_CACHE.PREFETCH then
                pcall(fluid.prefetch)
            end
            local ok, err = pcall(function()
                machine.loadCacheConfigFromRequesters()
                machine.updateMinimumStocks()
                report.aggregateReportData()

                local _, logMsg = scheduler.monitorPlantStatus()
                if logMsg then ui_draw.appendLog(logMsg) end

                if not CONFIG.IS_PLANT_SHUTDOWN_FROM_RUNNING then
                    local lowestLevel = scheduler.getLowestShortageLevel()
                    if lowestLevel then
                        local allocationPlan = scheduler.calculateMultiLevelAllocation(lowestLevel)
                        if not scheduler.isAllocationSame(CONFIG.LAST_ACTIVE_LEVEL, allocationPlan) then
                            scheduler.startProductionByAllocation(allocationPlan)
                            if type(allocationPlan) == "table" and next(allocationPlan) then
                                local levels = {}
                                for l in pairs(allocationPlan) do table.insert(levels, l) end
                                table.sort(levels)
                                ui_draw.appendLog("[调度] 更新生产方案，开启等级：T" .. table.concat(levels, " T"))
                            end
                        end
                    else
                        if CONFIG.LAST_ACTIVE_LEVEL and next(CONFIG.LAST_ACTIVE_LEVEL) then
                            scheduler.shutdownAll()
                            ui_draw.appendLog("[调度] 所有等级水量充足，已关闭全部机器")
                        end
                    end
                end
            end)
            if not ok then
                ui_draw.appendLog("[错误] 运行异常: " .. tostring(err))
            end
        end

        -- 关帧：失效过期缓存
        if fluid.endFrame then fluid.endFrame() end

        -- 无线同步广播
        local syncNow = computer.uptime()
        if net.isReady() and syncNow - UI._lastBroadcast >= CONFIG.SYNC.BROADCAST_INTERVAL then
            UI._lastBroadcast = syncNow
            pcall(function()
                UI._runtime = UI._runtime or {}
                UI._runtime.plantRunning = ui_draw.getPlantRunning()
                UI._runtime.scanResult = ui_draw.getScanResult()
                UI._runtime.fluidCache = fluid.dumpCache and fluid.dumpCache() or {}
                local snap = sync.collectSnapshot(UI._runtime)
                local str = sync.serialize(snap)
                net.broadcast(UI._syncSeq, str)
                UI._syncSeq = UI._syncSeq + 1
            end)
        end

        -- 脏区域调度绘制（每轮调用，未变面板自动跳过）
        ui_draw.renderAll()
    end
end

-- ==================== 程序入口 ====================
local function main()
    local maxW, maxH = UI.gpu.maxResolution()
    UI.gpu.setResolution(math.min(maxW, 160), math.min(maxH, 50))
    ui_draw.calculateLayout()

    local fluidOk, fluidMsg = fluid.initialize()
    ui_draw.appendLog(fluidMsg)

    local netOk, netMsg = net.initialize()
    ui_draw.appendLog(netMsg)

    local machineOk, machineMsg = machine.initializeMachinesAndPower()
    if not machineOk then
        ui_draw.appendLog("[致命错误] 核心硬件初始化失败，程序无法运行")
        ui_draw.renderAll(true)
        return
    end
    ui_draw.appendLog(machineMsg)

    machine.loadCacheConfigFromRequesters()
    machine.calculateAndSaveLevelParams()
    machine.updateMinimumStocks()
    report.sampleFluidHistory(true)
    report.initTimeBase()

    ui_draw.appendLog("[系统] 净化水线总控系统加载完成")
    ui_draw.appendLog("[提示] 点击【启动系统】开始自动运行")
    ui_draw.appendLog("[提示] 点击顶部标签切换总览/详细报表")
    ui_draw.appendLog("[提示] 点击等级行查看并行参数与短时趋势")

    ui_draw.renderAll(true)
    mainLoop()
end

-- ==================== 启动 ====================
local ok, err = xpcall(main, debug.traceback)
if not ok then
    UI.gpu.setBackground(0x000000)
    UI.gpu.setForeground(0xff0000)
    UI.gpu.fill(1, 1, UI.W, UI.H, " ")
    UI.gpu.set(1, 1, "程序崩溃: " .. tostring(err))
end
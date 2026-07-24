-- main.lua
-- 程序入口：初始化、主循环（并行自动退出）
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
local persistence = require("persistence")
local UI = require("ui_config")
local ui_draw = require("ui_draw")
local interaction = require("interaction")
UI.readonly = false
local function redrawAll(force) ui_draw.renderAll(force) end
local function mainLoop()
    UI._lastFluidQuery = 0
    UI.lastTick = computer.uptime()
    UI.lastSampleTime = computer.uptime()
    UI._lastBroadcast = 0
    UI._syncSeq = 0
    while true do
        if fluid.beginFrame then fluid.beginFrame() end
        local eventName, _, x, y = event.pull(1)
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
            -- 退出前强制保存历史数据
            pcall(persistence.save)
            UI.gpu.setBackground(0x000000)
            UI.gpu.setForeground(0xffffff)
            UI.gpu.fill(1,1,UI.W,UI.H," ")
            UI.gpu.set(1,1,"系统已退出，历史数据已保存")
            return
        end
        pcall(report.sampleFluidHistory)
        -- 图表详情自动返回总览
        if UI.currentTab == "overview" and UI.chartMode == "detail"
            and computer.uptime() - UI.detailSwitchTime >= 20 then
            UI.chartMode = "overview"
            UI.currentDetailLevel = nil
        end
        -- 并行详情自动返回概况
        if UI.parallelMode == "detail" and UI.parallelDetailLevel
            and computer.uptime() - UI.parallelDetailSwitchTime >= 20 then
            UI.parallelMode = "overview"
            UI.parallelDetailLevel = nil
        end
        local now = computer.uptime()
        local interval = ui_draw.getPlantRunning()
            and CONFIG.CHECK_INTERVAL_RUNNING or CONFIG.CHECK_INTERVAL_STOPPED
        local businessTick = UI.systemRunning and (now - UI.lastTick >= interval)
        if businessTick then
            UI.lastTick = now
            if fluid.prefetch and CONFIG.FLUID_CACHE.PREFETCH then pcall(fluid.prefetch) end
            local ok, err = pcall(function()
                machine.loadCacheConfigFromRequesters()
                machine.updateMinimumStocks()
                report.aggregateReportData()
                -- 每次数据聚合后自动存档，意外崩溃不丢数据
                pcall(persistence.save)
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
            if not ok then ui_draw.appendLog("[错误] 运行异常: " .. tostring(err)) end
        end
        if fluid.endFrame then fluid.endFrame() end
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
        ui_draw.renderAll()
    end
end
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

    -- 优先加载历史存档
    local loadOk, loadMsg = persistence.load()
    ui_draw.appendLog(loadMsg)
    if not loadOk then
        report.initTimeBase()
    end

    -- 【关键修复】先预取一次流体数据，确保首次采样数值准确
    pcall(fluid.prefetch)
    report.sampleFluidHistory(true)

    report.sampleFluidHistory(true)
    ui_draw.appendLog("[系统] 净化水线总控系统加载完成")
    ui_draw.appendLog("[提示] 点击【启动系统】开始自动运行")
    ui_draw.appendLog("[提示] 点击顶部标签切换总览/详细报表")
    ui_draw.appendLog("[提示] 点击等级行查看并行参数与短时趋势")
    ui_draw.renderAll(true)
    mainLoop()
end
local ok, err = xpcall(main, debug.traceback)
if not ok then
    UI.gpu.setBackground(0x000000)
    UI.gpu.setForeground(0xff0000)
    UI.gpu.fill(1,1,UI.W,UI.H," ")
    UI.gpu.set(1,1,"程序崩溃: " .. tostring(err))
end
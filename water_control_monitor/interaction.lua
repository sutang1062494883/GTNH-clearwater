-- interaction.lua
-- 点击事件处理：按钮、标签切换、等级行点击
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local ok_machine, machine = pcall(require, "machine")
if not ok_machine then machine = nil end
local ok_scheduler, scheduler = pcall(require, "scheduler")
if not ok_scheduler then scheduler = nil end
local ok_report, report = pcall(require, "report")
if not ok_report then report = nil end
local UI = require("ui_config")
local ui_draw = require("ui_draw")
local interaction = {}

function interaction.handleClick(x, y, redrawAll)
    -- 全局标签切换
    if UI.tabButtons then
        for id, btn in pairs(UI.tabButtons) do
            if x >= btn.x and x < btn.x+btn.w and y >= btn.y and y < btn.y+btn.h then
                if UI.currentTab ~= id then
                    UI.currentTab = id
                    redrawAll()
                end
                return
            end
        end
    end
    -- 报表页交互
    if UI.currentTab == "report" then
        for name, btn in pairs(UI.reportPanel.tabButtons) do
            if x >= btn.x and x < btn.x+btn.w and y >= btn.y and y < btn.y+btn.h then
                if btn.action == "time_hour" then
                    UI.reportPanel.timeDimension = "hour"
                elseif btn.action == "time_day" then
                    UI.reportPanel.timeDimension = "day"
                elseif btn.action:sub(1,6) == "level_" then
                    local level = tonumber(btn.action:sub(7))
                    if level and level >= 1 and level <= 8 then
                        UI.reportPanel.viewLevel = level
                    end
                end
                redrawAll()
                return
            end
        end
        return
    end
    -- 总览页控制按钮（只读模式下不响应）
    if not UI.readonly then
        for name, btn in pairs(UI.buttons) do
            if x >= btn.x and x < btn.x+btn.w and y >= btn.y and y < btn.y+btn.h then
                if btn.action == "start" then
                    interaction._handleStart()
                elseif btn.action == "refresh" then
                    interaction._handleRefresh()
                elseif btn.action == "fullpower" then
                    interaction._handleFullPower()
                end
                redrawAll()
                return
            end
        end
    end
    -- 等级行点击 -> 并行面板详情
    for level, row in pairs(UI.levelRows) do
        if x >= row.x and x < row.x+row.w and y >= row.y and y < row.y+row.h then
            if UI.currentTab == "overview" then
                UI.parallelMode = "detail"
                UI.parallelDetailLevel = level
                UI.parallelDetailSwitchTime = computer.uptime()
                redrawAll()
            end
            return
        end
    end
    -- 图表区点击 -> 返回总览（仅图表自己的详情模式）
    local chartArea = UI.areas.chart
    if chartArea and x >= chartArea.x and x < chartArea.x+chartArea.w
        and y >= chartArea.y and y < chartArea.y+chartArea.h then
        if UI.chartMode == "detail" then
            UI.chartMode = "overview"
            UI.currentDetailLevel = nil
            redrawAll()
            return
        end
    end
end

function interaction._handleStart()
    if not machine or not scheduler then return end
    if not UI.systemRunning then
        UI.systemRunning = true
        CONFIG.LAST_PLANT_STATUS = machine.isWaterPlantRunning()
        scheduler.shutdownAll()
        ui_draw.appendLog("[系统] 自动控制系统已启动")
    else
        UI.systemRunning = false
        scheduler.shutdownAll()
        ui_draw.appendLog("[系统] 自动控制系统已停止")
    end
end

function interaction._handleRefresh()
    if not machine or not scheduler or not report then return end
    ui_draw.appendLog("[系统] 执行全量刷新扫描")
    pcall(function()
        machine.initializeMachinesAndPower()
        machine.loadCacheConfigFromRequesters()
        machine.calculateAndSaveLevelParams()
        machine.updateMinimumStocks()
        report.sampleFluidHistory(true)
        if UI.systemRunning and not CONFIG.SYSTEM_EMERGENCY_STOPPED then
            scheduler.monitorPlantStatus()
            if not CONFIG.IS_PLANT_SHUTDOWN_FROM_RUNNING then
                local allocationPlan = scheduler.calculateMultiLevelAllocation()
                if not scheduler.isAllocationSame(CONFIG.LAST_ACTIVE_LEVEL, allocationPlan) then
                    scheduler.startProductionByAllocation(allocationPlan)
                    if type(allocationPlan) == "table" and next(allocationPlan) then
                        local levels = {}
                        for l in pairs(allocationPlan) do table.insert(levels, l) end
                        table.sort(levels)
                        ui_draw.appendLog("[调度] 刷新后更新生产方案，开启等级：T" .. table.concat(levels, " T"))
                    else
                        scheduler.shutdownAll()
                        ui_draw.appendLog("[调度] 刷新后无缺水等级，已关闭全部机器")
                    end
                end
            end
        end
    end)
end

function interaction._handleFullPower()
    if not scheduler then return end
    UI.fullPowerMode = not UI.fullPowerMode
    ui_draw.appendLog("[模式] 切换为" .. (UI.fullPowerMode and "全力生产模式" or "普通库存模式"))
    if UI.systemRunning and not CONFIG.IS_PLANT_SHUTDOWN_FROM_RUNNING then
        pcall(function()
            local alloc = scheduler.calculateMultiLevelAllocation()
            scheduler.startProductionByAllocation(alloc)
        end)
    end
end

return interaction
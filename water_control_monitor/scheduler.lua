-- scheduler.lua
-- 生产调度：多级分配、启停控制、状态监控

local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST
local fluid = require("fluid")
local machine = require("machine")
local UI = require("ui_config")

local scheduler = {}

function scheduler.isLevelOverMaxStock(level)
    local cfg = CONFIG.CACHED_CONFIG[level]
    if not cfg then return true end
    local fluidName = cfg.fluidId or CONST.FLUID_NAMES[level]
    local current = fluid.getAmount(fluidName)
    local minStock = CONFIG.CALCULATED.MINIMUM_STOCK[level] or 0
    if cfg.enabled then
        local stopThreshold = math.max((cfg.threshold or 0) * CONST.MAX_STOCK_MULTIPLIER, minStock)
        return current >= stopThreshold
    else
        return minStock > 0 and current >= minStock
    end
end

function scheduler.isLevelInShortage(level)
    local cfg = CONFIG.CACHED_CONFIG[level]
    if not cfg then return false end
    local fluidName = cfg.fluidId or CONST.FLUID_NAMES[level]
    local current = fluid.getAmount(fluidName)
    local playerThreshold = (cfg.enabled and cfg.threshold) or 0
    local minStock = CONFIG.CALCULATED.MINIMUM_STOCK[level] or 0
    local minRequired = math.max(playerThreshold, minStock)
    return current < minRequired
end

function scheduler.checkMaterialSufficient(targetLevel)
    if targetLevel == 1 then return true end
    local inputLevel = targetLevel - 1
    local inputFluid = CONST.FLUID_NAMES[inputLevel]
    local currentStock = fluid.getAmount(inputFluid)
    local totalParallel = CONFIG.CALCULATED.LEVEL_TOTAL_PARALLEL[targetLevel] or 0
    return totalParallel > 0 and currentStock > totalParallel * CONST.STOCK_PER_PARALLEL
end

function scheduler.getLowestShortageLevel()
    local machines = machine.getMachines()
    for level = 1, 8 do
        if #machines[level].proxies > 0 then
            if scheduler.isLevelInShortage(level) and not scheduler.isLevelOverMaxStock(level) then
                return level
            end
        end
    end
    return nil
end

function scheduler.calculateMultiLevelAllocation(lowestLevel)
    local allocation = {}
    local machines = machine.getMachines()
    local ok, err = pcall(function()
        local remainingPower = CONFIG.TOTAL_POWER
        local priorityList = UI.fullPowerMode and CONFIG.FULL_POWER_PRIORITY or CONFIG.PRIORITY_ORDER

        if UI.fullPowerMode then
            for _, level in ipairs(priorityList) do
                local levelPower = CONFIG.CALCULATED.LEVEL_TOTAL_POWER[level] or 0
                local machineCount = #machines[level].proxies
                if levelPower > 0 and machineCount > 0 and levelPower <= remainingPower then
                    local materialOk = level == 1 or scheduler.checkMaterialSufficient(level)
                    if materialOk then
                        allocation[level] = true
                        remainingPower = remainingPower - levelPower
                    end
                end
            end
            return
        end

        for _, level in ipairs(priorityList) do
            local machineCount = #machines[level].proxies
            local levelPower = CONFIG.CALCULATED.LEVEL_TOTAL_POWER[level] or 0
            if machineCount > 0 and levelPower > 0 and levelPower <= remainingPower then
                if scheduler.isLevelInShortage(level) and not scheduler.isLevelOverMaxStock(level) then
                    local materialOk = (level == 1) or scheduler.checkMaterialSufficient(level)
                    if materialOk then
                        allocation[level] = true
                        remainingPower = remainingPower - levelPower
                    end
                end
            end
        end
    end)
    if not ok then
        return allocation, "[警告] 分配计算异常: " .. tostring(err)
    end
    return allocation, nil
end

function scheduler.isAllocationSame(oldAlloc, newAlloc)
    if type(oldAlloc) ~= "table" or type(newAlloc) ~= "table" then return false end
    for level = 1, 8 do
        if (oldAlloc[level] or false) ~= (newAlloc[level] or false) then
            return false
        end
    end
    return true
end

function scheduler.emergencyShutdownAllMachines()
    local machines = machine.getMachines()
    for level = 1, 8 do
        for _, m in ipairs(machines[level].proxies) do
            pcall(m.setWorkAllowed, false)
        end
    end
    CONFIG.LAST_ACTIVE_LEVEL = nil
    CONFIG.IS_PLANT_SHUTDOWN_FROM_RUNNING = true
    CONFIG.SYSTEM_EMERGENCY_STOPPED = true
    return "[紧急] 所有净水机器已强制停机"
end

function scheduler.startProductionByAllocation(allocationPlan)
    if CONFIG.SYSTEM_EMERGENCY_STOPPED then return false end
    if type(allocationPlan) ~= "table" then return false end
    local machines = machine.getMachines()
    for level = 1, 8 do
        local shouldEnable = allocationPlan[level] == true
        for _, m in ipairs(machines[level].proxies) do
            pcall(m.setWorkAllowed, shouldEnable)
        end
    end
    CONFIG.LAST_ACTIVE_LEVEL = allocationPlan
    return true
end

function scheduler.monitorPlantStatus()
    local currentStatus = machine.isWaterPlantRunning()
    local logMsg = nil
    if CONFIG.LAST_PLANT_STATUS ~= currentStatus then
        if currentStatus then
            CONFIG.IS_PLANT_SHUTDOWN_FROM_RUNNING = false
            CONFIG.SYSTEM_EMERGENCY_STOPPED = false
            logMsg = "[状态] 净水主机恢复运行，解除机器锁定"
        else
            CONFIG.IS_PLANT_SHUTDOWN_FROM_RUNNING = true
            scheduler.emergencyShutdownAllMachines()
            logMsg = "[警告] 净水主机停机，已紧急关闭所有单元"
        end
        CONFIG.LAST_PLANT_STATUS = currentStatus
    end
    return currentStatus, logMsg
end

function scheduler.shutdownAll()
    local machines = machine.getMachines()
    for level = 1, 8 do
        for _, m in ipairs(machines[level].proxies) do
            pcall(m.setWorkAllowed, false)
        end
    end
    CONFIG.LAST_ACTIVE_LEVEL = nil
end

return scheduler
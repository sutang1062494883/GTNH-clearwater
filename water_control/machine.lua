-- machine.lua
-- 机器扫描、功率计算、等级参数计算

local component = require("component")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST
local utils = require("utils")

local machine = {}

local machines = {}
for level = 0, 8 do machines[level] = { proxies = {} } end

local MACHINE_SCAN_RESULT = { total = 0, host = 0, units = {} }

function machine.getMachines() return machines end
function machine.getScanResult() return MACHINE_SCAN_RESULT end

function machine.scanAndCalculateTotalPower()
    local totalPower = 0
    local hasValidEnergyHatch = false
    for address, _ in component.list("gt_machine") do
        local proxy = component.proxy(address)
        if not proxy then goto continue end
        local success, machineName = pcall(proxy.getName)
        if not success then goto continue end
        if machineName:find("hatch.energytunnel") then
            totalPower = totalPower + math.floor(proxy.getEUCapacity() / 24)
            hasValidEnergyHatch = true
        elseif machineName:find("hatch.energywirelesstunnel") then
            local ampLevel = tonumber(machineName:match("tunnel(%d+)"))
            local inputVoltage = proxy.getInputVoltage()
            if ampLevel and ampLevel >= 1 and inputVoltage and inputVoltage > 0 then
                local ampNum = 256 * math.pow(4, ampLevel - 1)
                totalPower = totalPower + ampNum * inputVoltage
                hasValidEnergyHatch = true
            else
                totalPower = totalPower + math.floor(proxy.getEUCapacity() / 4000)
                hasValidEnergyHatch = true
            end
        elseif machineName:find("hatch.energymulti") or machineName:find("hatch.energywirelessmulti") then
            local multiNum = tonumber(machineName:match("multi(%d+)") or machineName:match("tier.(%d+)"))
            local inputVoltage = proxy.getInputVoltage()
            if multiNum and inputVoltage and inputVoltage > 0 then
                totalPower = totalPower + multiNum * inputVoltage
                hasValidEnergyHatch = true
            end
        end
        ::continue::
    end
    CONFIG.TOTAL_POWER = totalPower
    return hasValidEnergyHatch, totalPower
end

function machine.initializeMachinesAndPower()
    for level = 0, 8 do machines[level].proxies = {} end
    MACHINE_SCAN_RESULT = { total = 0, host = 0, units = {} }
    for address, _ in component.list("gt_machine") do
        local proxy = component.proxy(address)
        if not proxy then goto continue end
        local success, machineName = pcall(proxy.getName)
        if not success then goto continue end
        local level = CONST.MACHINE_NAMES[machineName]
        if level then
            table.insert(machines[level].proxies, proxy)
            MACHINE_SCAN_RESULT.total = MACHINE_SCAN_RESULT.total + 1
            MACHINE_SCAN_RESULT.units[level] = (MACHINE_SCAN_RESULT.units[level] or 0) + 1
            if level == 0 then MACHINE_SCAN_RESULT.host = MACHINE_SCAN_RESULT.host + 1 end
        end
        ::continue::
    end
    if #machines[0].proxies == 0 then
        return false, "[错误] 未检测到净水厂主机"
    end
    local hasValidEnergy, totalPower = machine.scanAndCalculateTotalPower()
    return hasValidEnergy, string.format("[扫描] 发现净水机器 %d 台，总可用功率 %s EU/t",
        MACHINE_SCAN_RESULT.total, utils.formatNumber(totalPower))
end

function machine.loadCacheConfigFromRequesters()
    local cacheSlots = {}
    for address, _ in component.list("level_maintainer") do
        local proxy = component.proxy(address)
        if not proxy then goto continue end
        for slot = 1, 5 do
            local success, slotData = pcall(proxy.getSlot, slot)
            if success and slotData and slotData.isEnable and slotData.isFluid then
                local fluidName = slotData.fluid and slotData.fluid.name or slotData.name
                local cleanName = fluidName:lower():match(":(.+)$") or fluidName:lower()
                local level = tonumber(string.match(cleanName, "grade(%d+)%s*[_-]?%s*purifiedwater"))
                if level and level >= 1 and level <= 8 then
                    cacheSlots[level] = { buffer = slotData.quantity or 0, fluidId = fluidName }
                end
            end
        end
        ::continue::
    end
    CONFIG.CACHED_LEVELS = {}
    for level = 1, 8 do
        local slotInfo = cacheSlots[level]
        if slotInfo then
            CONFIG.CACHED_CONFIG[level] = { threshold = slotInfo.buffer, enabled = true, fluidId = slotInfo.fluidId }
            table.insert(CONFIG.CACHED_LEVELS, level)
        else
            CONFIG.CACHED_CONFIG[level] = { threshold = 0, enabled = false, fluidId = CONST.FLUID_NAMES[level] }
        end
    end
    return true
end

function machine.calculateAndSaveLevelParams()
    for level = 1, 8 do
        local deployedCount = #machines[level].proxies
        local powerPerParallel = CONST.POWER_LEVELS[level] or 0
        if deployedCount > 0 and powerPerParallel > 0 then
            local systemMaxTotalParallel = math.floor(CONFIG.TOTAL_POWER / powerPerParallel)
            local suggestSingleParallel = math.min(
                math.floor(systemMaxTotalParallel / deployedCount), CONST.MAX_SINGLE_PARALLEL)
            CONFIG.CALCULATED.SUGGEST_SINGLE_PARALLEL[level] = suggestSingleParallel
            CONFIG.CALCULATED.SINGLE_MACHINE_POWER[level] = powerPerParallel * suggestSingleParallel
            CONFIG.CALCULATED.LEVEL_TOTAL_POWER[level] = deployedCount * CONFIG.CALCULATED.SINGLE_MACHINE_POWER[level]
            CONFIG.CALCULATED.LEVEL_TOTAL_PARALLEL[level] = deployedCount * suggestSingleParallel
        else
            CONFIG.CALCULATED.SUGGEST_SINGLE_PARALLEL[level] = 0
            CONFIG.CALCULATED.SINGLE_MACHINE_POWER[level] = 0
            CONFIG.CALCULATED.LEVEL_TOTAL_POWER[level] = 0
            CONFIG.CALCULATED.LEVEL_TOTAL_PARALLEL[level] = 0
        end
    end
end

function machine.updateMinimumStocks()
    CONFIG.CALCULATED.MINIMUM_STOCK = {}
    local maxEnabledLevel = 0
    for level = 1, 8 do
        local cfg = CONFIG.CACHED_CONFIG[level]
        if cfg and cfg.enabled then
            maxEnabledLevel = math.max(maxEnabledLevel, level)
        end
    end
    for level = 1, maxEnabledLevel - 1 do
        local nextLevelParallel = CONFIG.CALCULATED.LEVEL_TOTAL_PARALLEL[level + 1]
        if nextLevelParallel and nextLevelParallel > 0 then
            CONFIG.CALCULATED.MINIMUM_STOCK[level] =
                nextLevelParallel * CONST.MIN_STOCK_MULTIPLIER * CONST.STOCK_PER_PARALLEL
        end
    end
end

function machine.isWaterPlantRunning()
    for _, plant in ipairs(machines[0].proxies) do
        local success, result = pcall(function()
            if plant.isMachineActive then return plant.isMachineActive() end
            return plant.getEUStored and plant.getEUStored() > 0
        end)
        if success and result then return true end
    end
    return false
end

return machine
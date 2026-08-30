-- machine.lua
-- 机器扫描、功率计算、等级参数计算

local component = require("component")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST
local utils = require("utils")

local machine = {}

local machines = {}
for level = 0, 8 do machines[level] = { proxies = {} } end

local MACHINE_SCAN_RESULT = { total = 0, host = 0, units = {} }

-- 传感器信息缓存（避免频繁调用）
local statsCache = {}
local STATS_CACHE_TTL = 10  -- 秒（原 5 秒，放宽以降低传感器轮询频率）

-- ★ 每个等级最近一次有效的并行数（>1 才认为是有效）
local lastValidParallel = {}

-- ★ ME 接口连接状态缓存（原每帧 component.list + proxy 调用）
local meStatusCache = nil
local meStatusCacheTime = 0
local ME_STATUS_CACHE_TTL = 3   -- 秒

-- ★ 净水主机运行状态缓存（原每帧组件调用）
local plantRunningCache = nil
local plantRunningCacheTime = 0
local PLANT_RUNNING_CACHE_TTL = 2  -- 秒

function machine.getMachines() return machines end
function machine.getScanResult() return MACHINE_SCAN_RESULT end

-- 清除传感器缓存（刷新时调用）
function machine.invalidateStatsCache()
    statsCache = {}
    meStatusCache = nil
    -- 注意：不清除 lastValidParallel，保留历史有效值
end

-- 获取ME接口连接状态（只返回 connected，带 3 秒缓存）
function machine.getMEInterfaceStatus()
    local now = computer.uptime()
    if meStatusCache ~= nil and now - meStatusCacheTime < ME_STATUS_CACHE_TTL then
        return meStatusCache
    end

    local candidates = {"fluid_interface", "me_dual_interface", "me_interface"}
    local address = nil
    for _, compType in ipairs(candidates) do
        local ok_list, iter = pcall(component.list, compType)
        if ok_list and iter then
            address = iter()
            if address then break end
        end
    end

    local connected = false
    if address then
        connected = true
        local proxy = component.proxy(address)
        if proxy then
            local statusMethods = {"isConnected", "getNetworkState", "getNetworkStatus"}
            for _, method in ipairs(statusMethods) do
                if type(proxy[method]) == "function" then
                    local ok, res = pcall(proxy[method], proxy)
                    if ok then
                        if type(res) == "boolean" then
                            connected = res
                        elseif type(res) == "table" then
                            connected = res.connected ~= false
                        end
                        break
                    end
                end
            end
        end
    end

    meStatusCache = connected
    meStatusCacheTime = now
    return connected
end

-- 读取某等级第一台机器的成功率和实际并行数（带缓存）
function machine.getMachineStats(level)
    local now = computer.uptime()
    local cache = statsCache[level]
    if cache and now - cache.time < STATS_CACHE_TTL then
        return cache.successRate, cache.actualParallel
    end

    local successRate, actualParallel = nil, nil
    local proxies = machines[level] and machines[level].proxies
    if proxies then
        for _, proxy in ipairs(proxies) do
            if proxy.getSensorInformation then
                local ok, result = pcall(proxy.getSensorInformation)
                if ok and type(result) == "table" then
                    for _, line in ipairs(result) do
                        local clean = line:gsub("§.", "")
                        local lowerLine = clean:lower()

                        -- 解析成功率：只从包含 success/成功率/成功 的行中提取，且优先带 %
                        if successRate == nil then
                            if lowerLine:find("success") or lowerLine:find("成功率") or lowerLine:find("成功") then
                                local num = clean:match("(%d+%.?%d*)%s*%%")
                                if num then
                                    successRate = tonumber(num)
                                else
                                    num = clean:match("(%d+%.?%d*)")
                                    if num then successRate = tonumber(num) end
                                end
                            end
                        end

                        -- 解析并行数（修复误抓问题）
                        if actualParallel == nil then
                            local isParallelLine = lowerLine:find("parallel") or lowerLine:find("并行") or lowerLine:find("并联")
                            if isParallelLine then
                                -- 跳过含 machine/count/机器/数量 的行，避免误抓 “Parallel machine count: 5”
                                local hasOtherInfo = lowerLine:find("machine") or lowerLine:find("count")
                                    or lowerLine:find("机器") or lowerLine:find("数量")
                                if not hasOtherInfo then
                                    local numStr = clean:match("parallel%s*[:：]?%s*([%d,]+)")
                                        or clean:match("并行%s*[:：]?%s*([%d,]+)")
                                        or clean:match("并联%s*[:：]?%s*([%d,]+)")
                                    -- 宽松匹配：但排除含 % 的行（避免与成功率混淆）
                                    if not numStr and not clean:find("%%") then
                                        numStr = clean:match("([%d,]+)")
                                    end
                                    if numStr then
                                        numStr = numStr:gsub(",", "")
                                        local num = tonumber(numStr)
                                        if num and num > 0 and num <= CONST.MAX_SINGLE_PARALLEL then
                                            actualParallel = num
                                        end
                                    end
                                end
                            end
                        end

                        if successRate and actualParallel then break end
                    end
                end
            end
            if successRate and actualParallel then break end
        end
    end

    -- 只接受 >1 的并行数为有效值，否则保留上次有效值
    local effectiveParallel
    if actualParallel and actualParallel > 1 then
        lastValidParallel[level] = actualParallel
        effectiveParallel = actualParallel
    else
        effectiveParallel = lastValidParallel[level]  -- 可能为 nil
    end

    -- 缓存时使用 effectiveParallel，而不是 actualParallel
    if successRate ~= nil or effectiveParallel ~= nil then
        statsCache[level] = { successRate = successRate, actualParallel = effectiveParallel, time = now }
    end
    return successRate, effectiveParallel
end

function machine.scanAndCalculateTotalPower()
    local totalPower = 0
    local hasValidEnergyHatch = false
    for address, _ in component.list("gt_machine") do
        local proxy = component.proxy(address)
        if not proxy then goto continue end
        local success, machineName = pcall(proxy.getName)
        if not success then goto continue end
        if machineName:find("hatch.energytunnel") then
            -- ★ 补 pcall，防止某个 proxy 缺方法导致整个程序崩溃
            local okCap, cap = pcall(proxy.getEUCapacity)
            if okCap and type(cap) == "number" then
                totalPower = totalPower + math.floor(cap / 24)
                hasValidEnergyHatch = true
            end
        elseif machineName:find("hatch.energywirelesstunnel") then
            local ampLevel = tonumber(machineName:match("tunnel(%d+)"))
            local okV, inputVoltage = pcall(proxy.getInputVoltage)
            if ampLevel and ampLevel >= 1 and okV and inputVoltage and inputVoltage > 0 then
                local ampNum = 256 * math.pow(4, ampLevel - 1)
                totalPower = totalPower + ampNum * inputVoltage
                hasValidEnergyHatch = true
            else
                local okCap, cap = pcall(proxy.getEUCapacity)
                if okCap and type(cap) == "number" then
                    totalPower = totalPower + math.floor(cap / 4000)
                    hasValidEnergyHatch = true
                end
            end
        elseif machineName:find("hatch.energymulti") or machineName:find("hatch.energywirelessmulti") then
            local multiNum = tonumber(machineName:match("multi(%d+)") or machineName:match("tier.(%d+)"))
            local okV, inputVoltage = pcall(proxy.getInputVoltage)
            if multiNum and okV and inputVoltage and inputVoltage > 0 then
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

-- 净水主机是否运行（带 2 秒缓存；业务 tick 间隔 >=5 秒，不受缓存影响）
function machine.isWaterPlantRunning()
    local now = computer.uptime()
    if plantRunningCache ~= nil and now - plantRunningCacheTime < PLANT_RUNNING_CACHE_TTL then
        return plantRunningCache
    end
    local result = false
    for _, plant in ipairs(machines[0].proxies) do
        local success, active = pcall(function()
            if plant.isMachineActive then return plant.isMachineActive() end
            return plant.getEUStored and plant.getEUStored() > 0
        end)
        if success and active then
            result = true
            break
        end
    end
    plantRunningCache = result
    plantRunningCacheTime = now
    return result
end

return machine

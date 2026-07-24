-- utils.lua
-- 通用工具函数：数字格式化、GT电压/电流解析

local CONST = require("config").CONST

local utils = {}

function utils.formatNumber(num)
    if not num or num == 0 then return "0" end
    local str = tostring(math.floor(num))
    local reversed = string.reverse(str)
    local formatted = string.gsub(reversed, "(%d%d%d)", "%1,")
    return string.reverse(formatted):gsub("^,", "")
end

function utils.formatShortNumber(num)
    if not num or num == 0 then return "0" end
    local absNum = math.abs(num)
    if absNum >= 1e12 then return string.format("%.2fT", num / 1e12)
    elseif absNum >= 1e9 then return string.format("%.2fG", num / 1e9)
    elseif absNum >= 1e6 then return string.format("%.2fM", num / 1e6)
    elseif absNum >= 1e3 then return string.format("%.2fK", num / 1e3)
    else return tostring(math.floor(num))
    end
end

function utils.getGTInfo(euPerTick)
    local voltageNames = CONST.VOLTAGE_NAMES
    local maxVoltageName = "MAX"
    if euPerTick == 0 then
        return "0A ", voltageNames[1]
    end
    local absValue = math.abs(euPerTick)
    if absValue >= CONST.MAX_VOLTAGE_VALUE then
        return string.format("%sA ", utils.formatNumber(absValue / CONST.MAX_VOLTAGE_VALUE)), maxVoltageName
    end
    local voltage_for_tier = absValue / 2 / (4 ^ CONST.GT_SHOW_LOWER_TIER)
    local tier = voltage_for_tier < 4 and 1 or math.floor(math.log(voltage_for_tier) / math.log(4))
    tier = math.max(1, math.min(tier, #voltageNames))
    local baseVoltage = 8 * (4 ^ (tier - 1))
    local current = absValue / baseVoltage
    return string.format("%.0fA ", current), voltageNames[tier]
end

function utils.getGTInfoHighVoltage(euPerTick)
    local voltageNames = CONST.VOLTAGE_NAMES
    local maxVoltageName = "MAX"
    if euPerTick == 0 then
        return "0A ", voltageNames[1]
    end
    local absValue = math.abs(euPerTick)
    if absValue >= CONST.MAX_VOLTAGE_VALUE then
        return string.format("%sA ", utils.formatNumber(absValue / CONST.MAX_VOLTAGE_VALUE)), maxVoltageName
    end
    local tier = #voltageNames
    while tier > 1 do
        local baseVoltage = 8 * (4 ^ (tier - 1))
        if absValue >= baseVoltage then break end
        tier = tier - 1
    end
    local baseVoltage = 8 * (4 ^ (tier - 1))
    local current = absValue / baseVoltage
    return string.format("%.2fA ", current), voltageNames[tier]
end

return utils
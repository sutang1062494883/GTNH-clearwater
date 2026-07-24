-- alert.lua
-- 告警状态判断：库存告警、功率负载告警

local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST
local fluid = require("fluid")

local alert = {}

function alert.getLevelStockAlert(level)
    local cfg = CONFIG.CACHED_CONFIG[level]
    if not cfg or not cfg.enabled then return "normal" end
    local fluidName = cfg.fluidId or CONST.FLUID_NAMES[level]
    local current = fluid.getAmount(fluidName)
    local target = math.max(cfg.threshold or 0, CONFIG.CALCULATED.MINIMUM_STOCK[level] or 0)
    if target <= 0 then return "normal" end
    local ratio = current / target
    if ratio <= CONFIG.ALERT.STOCK_CRITICAL_RATIO then
        return "critical"
    elseif ratio <= CONFIG.ALERT.STOCK_WARNING_RATIO then
        return "warning"
    end
    return "normal"
end

function alert.getPowerAlertStatus()
    local usedPower = 0
    if CONFIG.LAST_ACTIVE_LEVEL then
        for level = 1, 8 do
            if CONFIG.LAST_ACTIVE_LEVEL[level] then
                usedPower = usedPower + (CONFIG.CALCULATED.LEVEL_TOTAL_POWER[level] or 0)
            end
        end
    end
    if CONFIG.TOTAL_POWER <= 0 then return "normal" end
    local ratio = usedPower / CONFIG.TOTAL_POWER
    if ratio >= CONFIG.ALERT.POWER_HIGH_LOAD_RATIO then
        return "warning"
    end
    return "normal"
end

return alert
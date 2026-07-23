-- report.lua
-- 历史数据采样、小时/天级聚合

local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST
local fluid = require("fluid")
local UI = require("ui_config")

local report = {}

function report.sampleFluidHistory(force)
    local now = computer.uptime()
    if not force and now - UI.lastSampleTime < UI.SAMPLE_INTERVAL then return end
    UI.lastSampleTime = now

    local sample = { time = now, levels = {} }
    for level = 1, 8 do
        local cfg = CONFIG.CACHED_CONFIG[level]
        local fluidName = cfg and (cfg.fluidId or CONST.FLUID_NAMES[level]) or CONST.FLUID_NAMES[level]
        sample.levels[level] = fluid.getAmount(fluidName)
    end

    table.insert(UI.historyData, sample)
    while #UI.historyData > UI.MAX_HISTORY_POINTS do
        table.remove(UI.historyData, 1)
    end
end

function report.aggregateReportData()
    local now = computer.uptime()
    local const = CONST.REPORT_CONST

    if now - CONFIG.REPORT.lastHourAggTime >= const.HOUR_INTERVAL then
        CONFIG.REPORT.lastHourAggTime = now
        local hourSample = { time = now, levels = {} }
        if #UI.historyData > 0 then
            local latest = UI.historyData[#UI.historyData]
            for level = 1, 8 do
                hourSample.levels[level] = latest.levels[level] or 0
            end
        end
        table.insert(CONFIG.REPORT.HOUR_DATA, hourSample)
        while #CONFIG.REPORT.HOUR_DATA > const.MAX_HOUR_POINTS do
            table.remove(CONFIG.REPORT.HOUR_DATA, 1)
        end
    end

    if now - CONFIG.REPORT.lastDayAggTime >= const.DAY_INTERVAL then
        CONFIG.REPORT.lastDayAggTime = now
        local daySample = { time = now, levels = {} }
        if #CONFIG.REPORT.HOUR_DATA > 0 then
            local latestHour = CONFIG.REPORT.HOUR_DATA[#CONFIG.REPORT.HOUR_DATA]
            for level = 1, 8 do
                daySample.levels[level] = latestHour.levels[level] or 0
            end
        end
        table.insert(CONFIG.REPORT.DAY_DATA, daySample)
        while #CONFIG.REPORT.DAY_DATA > const.MAX_DAY_POINTS do
            table.remove(CONFIG.REPORT.DAY_DATA, 1)
        end
    end
end

function report.getFluid1hAgo(level)
    if #UI.historyData < 2 then return nil end
    return UI.historyData[1].levels[level] or nil
end

function report.initTimeBase()
    CONFIG.REPORT.lastHourAggTime = computer.uptime()
    CONFIG.REPORT.lastDayAggTime = computer.uptime()
end

return report
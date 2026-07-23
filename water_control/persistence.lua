-- persistence.lua
-- 历史数据与阈值配置持久化：重启自动恢复图表与配置
local serialization = require("serialization")
local filesystem = require("filesystem")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST
local UI = require("ui_config")
local persistence = {}
local SAVE_FILE = "/water_control_history.dat"

-- 保存所有历史数据与阈值配置到本地文件
function persistence.save()
    local data = {
        historyData = UI.historyData,
        lastSampleTime = UI.lastSampleTime,
        hourData = CONFIG.REPORT.HOUR_DATA,
        dayData = CONFIG.REPORT.DAY_DATA,
        lastHourAggTime = CONFIG.REPORT.lastHourAggTime,
        lastDayAggTime = CONFIG.REPORT.lastDayAggTime,
        cachedConfig = CONFIG.CACHED_CONFIG,
        saveUptime = computer.uptime()
    }
    
    local ok, err = pcall(function()
        local f = io.open(SAVE_FILE, "w")
        if not f then error("无法打开保存文件") end
        f:write(serialization.serialize(data))
        f:close()
    end)
    return ok, err
end

-- 从本地文件加载历史数据与配置并对齐时间轴
function persistence.load()
    if not filesystem.exists(SAVE_FILE) then
        return false, "无历史数据文件"
    end
    
    local ok, data = pcall(function()
        local f = io.open(SAVE_FILE, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return serialization.unserialize(content)
    end)
    
    if not ok or type(data) ~= "table" then
        return false, "数据文件损坏，已跳过"
    end
    local now = computer.uptime()

    -- 恢复阈值配置与启用等级列表
    if type(data.cachedConfig) == "table" then
        CONFIG.CACHED_CONFIG = data.cachedConfig
        CONFIG.CACHED_LEVELS = {}
        for level = 1, 8 do
            if CONFIG.CACHED_CONFIG[level] and CONFIG.CACHED_CONFIG[level].enabled then
                table.insert(CONFIG.CACHED_LEVELS, level)
            end
        end
    end

    -- 恢复高频采样数据并平移时间戳
    if type(data.historyData) == "table" and #data.historyData > 0 then
        UI.historyData = data.historyData
        while #UI.historyData > UI.MAX_HISTORY_POINTS do
            table.remove(UI.historyData, 1)
        end
        local latest = UI.historyData[#UI.historyData].time
        local offset = now - latest
        for i = 1, #UI.historyData do
            UI.historyData[i].time = UI.historyData[i].time + offset
        end
    end
    if type(data.lastSampleTime) == "number" then
        UI.lastSampleTime = data.lastSampleTime + (now - (data.saveUptime or 0))
    end

    -- 恢复小时级聚合数据并平移时间戳
    if type(data.hourData) == "table" and #data.hourData > 0 then
        CONFIG.REPORT.HOUR_DATA = data.hourData
        while #CONFIG.REPORT.HOUR_DATA > CONST.REPORT_CONST.MAX_HOUR_POINTS do
            table.remove(CONFIG.REPORT.HOUR_DATA, 1)
        end
        local latest = CONFIG.REPORT.HOUR_DATA[#CONFIG.REPORT.HOUR_DATA].time
        local offset = now - latest
        for i = 1, #CONFIG.REPORT.HOUR_DATA do
            CONFIG.REPORT.HOUR_DATA[i].time = CONFIG.REPORT.HOUR_DATA[i].time + offset
        end
    end
    if type(data.lastHourAggTime) == "number" then
        CONFIG.REPORT.lastHourAggTime = data.lastHourAggTime + (now - (data.saveUptime or 0))
    end

    -- 恢复天级聚合数据并平移时间戳
    if type(data.dayData) == "table" and #data.dayData > 0 then
        CONFIG.REPORT.DAY_DATA = data.dayData
        while #CONFIG.REPORT.DAY_DATA > CONST.REPORT_CONST.MAX_DAY_POINTS do
            table.remove(CONFIG.REPORT.DAY_DATA, 1)
        end
        local latest = CONFIG.REPORT.DAY_DATA[#CONFIG.REPORT.DAY_DATA].time
        local offset = now - latest
        for i = 1, #CONFIG.REPORT.DAY_DATA do
            CONFIG.REPORT.DAY_DATA[i].time = CONFIG.REPORT.DAY_DATA[i].time + offset
        end
    end
    if type(data.lastDayAggTime) == "number" then
        CONFIG.REPORT.lastDayAggTime = data.lastDayAggTime + (now - (data.saveUptime or 0))
    end
    
    return true, "历史数据与配置加载完成"
end

return persistence
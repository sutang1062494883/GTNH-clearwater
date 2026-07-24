-- sync.lua
-- 状态快照：控制端采集 / 序列化；接收端反序列化 / 应用

local serialization = require("serialization")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local UI = require("ui_config")

local sync = {}

local function cloneData(src, seen)
    seen = seen or {}
    if type(src) ~= "table" then return src end
    if seen[src] then return seen[src] end
    local t = {}
    seen[src] = t
    for k, v in pairs(src) do
        if type(k) ~= "function" and type(v) ~= "function" and type(v) ~= "userdata" then
            t[cloneData(k, seen)] = cloneData(v, seen)
        end
    end
    return t
end

function sync.collectSnapshot(runtime)
    runtime = runtime or {}
    local snap = {
        v = CONFIG.SYNC.VERSION,
        t = computer.uptime(),
        CACHED_CONFIG = cloneData(CONFIG.CACHED_CONFIG),
        CALCULATED = cloneData(CONFIG.CALCULATED),
        TOTAL_POWER = CONFIG.TOTAL_POWER,
        PRIORITY_ORDER = cloneData(CONFIG.PRIORITY_ORDER),
        FULL_POWER_PRIORITY = cloneData(CONFIG.FULL_POWER_PRIORITY),
        LAST_ACTIVE_LEVEL = cloneData(CONFIG.LAST_ACTIVE_LEVEL),
        SYSTEM_EMERGENCY_STOPPED = CONFIG.SYSTEM_EMERGENCY_STOPPED,
        ALERT = cloneData(CONFIG.ALERT),
        REPORT = {
            HOUR_DATA = cloneData(CONFIG.REPORT.HOUR_DATA),
            DAY_DATA = cloneData(CONFIG.REPORT.DAY_DATA),
        },
        fullPowerMode = UI.fullPowerMode,
        systemRunning = UI.systemRunning,
        logLines = cloneData(UI.logLines),
        historyData = cloneData(UI.historyData),
        plantRunning = runtime.plantRunning or false,
        scanResult = cloneData(runtime.scanResult or {}),
        fluidCache = cloneData(runtime.fluidCache or {}),
    }
    return snap
end

function sync.serialize(snap)
    return serialization.serialize(snap)
end

function sync.unserialize(str)
    local ok, snap = pcall(serialization.unserialize, str)
    if not ok or type(snap) ~= "table" then return nil end
    if snap.v ~= CONFIG.SYNC.VERSION then return nil end
    return snap
end

function sync.applySnapshot(snap)
    if not snap then return false end

    CONFIG.CACHED_CONFIG = snap.CACHED_CONFIG or CONFIG.CACHED_CONFIG
    CONFIG.CALCULATED = snap.CALCULATED or CONFIG.CALCULATED
    CONFIG.TOTAL_POWER = snap.TOTAL_POWER or 0
    CONFIG.PRIORITY_ORDER = snap.PRIORITY_ORDER or CONFIG.PRIORITY_ORDER
    CONFIG.FULL_POWER_PRIORITY = snap.FULL_POWER_PRIORITY or CONFIG.FULL_POWER_PRIORITY
    CONFIG.LAST_ACTIVE_LEVEL = snap.LAST_ACTIVE_LEVEL
    CONFIG.SYSTEM_EMERGENCY_STOPPED = snap.SYSTEM_EMERGENCY_STOPPED or false
    CONFIG.ALERT = snap.ALERT or CONFIG.ALERT
    if snap.REPORT then
        CONFIG.REPORT.HOUR_DATA = snap.REPORT.HOUR_DATA or {}
        CONFIG.REPORT.DAY_DATA = snap.REPORT.DAY_DATA or {}
    end

    UI.fullPowerMode = snap.fullPowerMode or false
    UI.systemRunning = snap.systemRunning or false
    UI.logLines = snap.logLines or {}
    UI.historyData = snap.historyData or {}

    UI._runtime = UI._runtime or {}
    UI._runtime.plantRunning = snap.plantRunning or false
    UI._runtime.scanResult = snap.scanResult or { total = 0, host = 0, units = {} }
    UI._runtime.fluidCache = snap.fluidCache or {}
    
    UI._runtime.enabled = true   -- 镜像端：启用运行时缓存通道
    UI._lastSyncTime = computer.uptime()
    return true
end

return sync
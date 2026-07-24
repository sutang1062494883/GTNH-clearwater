-- config.lua
-- 全局配置与常量定义
local sides = require("sides")
local CONFIG = {
    POWER_SWITCH_PORT = sides.west,
    TOTAL_POWER = 0,
    CACHED_CONFIG = {
        [1] = { threshold = 0, enabled = false, fluidId = "grade1purifiedwater" },
        [2] = { threshold = 0, enabled = false, fluidId = "grade2purifiedwater" },
        [3] = { threshold = 0, enabled = false, fluidId = "grade3purifiedwater" },
        [4] = { threshold = 0, enabled = false, fluidId = "grade4purifiedwater" },
        [5] = { threshold = 0, enabled = false, fluidId = "grade5purifiedwater" },
        [6] = { threshold = 0, enabled = false, fluidId = "grade6purifiedwater" },
        [7] = { threshold = 0, enabled = false, fluidId = "grade7purifiedwater" },
        [8] = { threshold = 0, enabled = false, fluidId = "grade8purifiedwater" },
    },
    CACHED_LEVELS = {},
    LAST_PLANT_STATUS = nil,
    SYSTEM_EMERGENCY_STOPPED = false,
    LAST_ACTIVE_LEVEL = nil,
    CHECK_INTERVAL_STOPPED = 5,
    CHECK_INTERVAL_RUNNING = 20,
    IS_PLANT_SHUTDOWN_FROM_RUNNING = false,
    CALCULATED = {
        SUGGEST_SINGLE_PARALLEL = {},
        SINGLE_MACHINE_POWER = {},
        LEVEL_TOTAL_POWER = {},
        LEVEL_TOTAL_PARALLEL = {},
        MINIMUM_STOCK = {}
    },
    PRIORITY_ORDER = {1, 2, 3, 4, 5, 6, 7, 8},
    FULL_POWER_PRIORITY = {8, 7, 6, 5, 4, 3, 2, 1},
    ALERT = {
        STOCK_WARNING_RATIO = 0.3,
        STOCK_CRITICAL_RATIO = 0.1,
        POWER_HIGH_LOAD_RATIO = 0.8
    },
    REPORT = {
        HOUR_DATA = {},
        DAY_DATA = {},
        lastHourAggTime = 0,
        lastDayAggTime = 0
    },
    -- 无线同步配置
    SYNC = {
        PORT = 13579,
        BROADCAST_INTERVAL = 1.0,
        PROTOCOL_MAGIC = "WCS_SYNC",
        FRAG_PAYLOAD = 4000,
        FRAG_TIMEOUT = 3.0,
        VERSION = 1
    },
    -- 流体缓存配置
    FLUID_CACHE = {
        TTL = 15.0,
        PREFETCH = true,
        QUERY_INTERVAL = 10.0
    },
}
local CONST = {
    MAX_STOCK_MULTIPLIER = 5,
    MAX_SINGLE_PARALLEL = 2147484,
    GT_SHOW_LOWER_TIER = 4,
    MAX_VOLTAGE_VALUE = 2147483640,
    POWER_LEVELS = {
        [1] = 30720, [2] = 30720, [3] = 122880, [4] = 122880,
        [5] = 491520, [6] = 491520, [7] = 1966080, [8] = 7864320
    },
    FLUID_NAMES = {
        [1] = "grade1purifiedwater", [2] = "grade2purifiedwater",
        [3] = "grade3purifiedwater", [4] = "grade4purifiedwater",
        [5] = "grade5purifiedwater", [6] = "grade6purifiedwater",
        [7] = "grade7purifiedwater", [8] = "grade8purifiedwater"
    },
    MACHINE_NAMES = {
        ["multimachine.purificationplant"] = 0,
        ["multimachine.purificationunitclarifier"] = 1,
        ["multimachine.purificationunitozonation"] = 2,
        ["multimachine.purificationunitflocculator"] = 3,
        ["multimachine.purificationunitphadjustment"] = 4,
        ["multimachine.purificationunitplasmaheater"] = 5,
        ["multimachine.purificationunituvtreatment"] = 6,
        ["multimachine.purificationunitdegasifier"] = 7,
        ["multimachine.purificationunitextractor"] = 8
    },
    VOLTAGE_NAMES = {
        "ULV", "LV", "MV", "HV", "EV", "IV",
        "LUV", "ZPM", "UV", "UHV", "UEV", "UIV", "UMV", "UXV"
    },
    MIN_STOCK_MULTIPLIER = 2,
    STOCK_PER_PARALLEL = 1000,
    REPORT_CONST = {
        HOUR_INTERVAL = 600,
        MAX_HOUR_POINTS = 144,
        DAY_INTERVAL = 21600,
        MAX_DAY_POINTS = 28
    }
}
return { CONFIG = CONFIG, CONST = CONST }
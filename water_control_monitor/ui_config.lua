-- ui_config.lua
-- UI 配置、颜色、布局与运行时状态

local component = require("component")

local UI = {
    COLORS = {
        BG = 0x0d1117,
        BORDER = 0x1e3a8a,
        BORDER_ALERT = 0x991b1b,
        TEXT = 0xe2e8f0,
        TEXT_CYAN = 0x38bdf8,
        TEXT_GREEN = 0x22c55e,
        TEXT_YELLOW = 0xf59e0b,
        TEXT_RED = 0xef4444,
        TEXT_PURPLE = 0xa855f7,
        BTN_BG = 0x1e293b,
        BTN_BG_HOVER = 0x334155,
        BTN_FULL_POWER = 0x7f1d1d,
        BAR_BG = 0x1e293b,
        BAR_FILL = 0x0ea5e9,
        BAR_BG_RUNNING = 0x3bd0ab,
        BAR_BG_IDLE = 0x334155,
        BAR_BG_NONE = 0x7f1d1d,
        ALERT_WARN_BG = 0x78350f,
        ALERT_CRITICAL_BG = 0x7f1d1d,
        ALERT_WARN_TEXT = 0xfbbf24,
        ALERT_CRITICAL_TEXT = 0xf87171
    },
    W = 0,
    H = 0,
    areas = {},
    buttons = {},
    levelRows = {},
    logLines = {},
    maxLogLines = 15,
    fullPowerMode = false,
    systemRunning = false,
    lastTick = 0,
    gpu = component.gpu,
    chartMode = "overview",
    currentDetailLevel = nil,
    detailSwitchTime = 0,
    historyData = {},
    SAMPLE_INTERVAL = 120,
    MAX_HISTORY_POINTS = 30,
    lastSampleTime = 0,
    tabs = {
        {id = "overview", name = "总览"},
        {id = "report", name = "详细报表"}
    },
    currentTab = "overview",
    tabButtons = {},
    reportPanel = {
        timeDimension = "hour",
        viewLevel = 1,
        tabButtons = {}
    },
    -- 只读模式（接收端=true）
    readonly = false,
    -- 运行时查询缓存（解耦 machine/fluid 组件，双端绘制统一读取）
    _runtime = {
        enabled = false,        -- 控制端=false；镜像端 applySnapshot 后置 true
        plantRunning = nil,
        scanResult = nil,
        fluidCache = nil
    },
    _lastSyncTime = 0,
    syncStatus = "未连接",
    -- 脏区域重绘调度
    render = {
        fingerprints = {},
        forceAll = true
    }
}

return UI
-- ui_draw.lua
-- UI 基础绘制 + 统一解耦读取 + 脏区域重绘调度器
local unicode = require("unicode")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST
local utils = require("utils")
local UI = require("ui_config")
-- 软依赖
local ok_machine, machine = pcall(require, "machine")
if not ok_machine then machine = nil end
local ok_scheduler, scheduler = pcall(require, "scheduler")
if not ok_scheduler then scheduler = nil end
local ok_alert, alert = pcall(require, "alert")
if not ok_alert then alert = nil end
local ok_fluid, fluid = pcall(require, "fluid")
if not ok_fluid then fluid = nil end
-- 懒加载 ui_chart
local _ui_chart = nil
local function getChart()
    if not _ui_chart then _ui_chart = require("ui_chart") end
    return _ui_chart
end
local ui_draw = {}

-- ========= 统一读取入口 =========
local function normClean(name)
    local raw = name
    if not raw:find(":") then raw = "gregtech:" .. raw end
    return raw:lower():match(":(.+)$") or raw:lower()
end
function ui_draw.getFluidAmount(fluidName)
    if UI._runtime and UI._runtime.enabled and UI._runtime.fluidCache then
        local clean = normClean(fluidName)
        local v = UI._runtime.fluidCache[clean]
        if v ~= nil then return v end
    end
    if fluid then return fluid.getAmount(fluidName) end
    return 0
end
function ui_draw.getPlantRunning()
    if UI._runtime and UI._runtime.enabled and UI._runtime.plantRunning ~= nil then
        return UI._runtime.plantRunning
    end
    if machine then return machine.isWaterPlantRunning() end
    return false
end
function ui_draw.getScanResult()
    if UI._runtime and UI._runtime.enabled and UI._runtime.scanResult then
        return UI._runtime.scanResult
    end
    if machine then return machine.getScanResult() end
    return { total = 0, host = 0, units = {} }
end
function ui_draw.getLevelMachineCount(level)
    local sr = ui_draw.getScanResult()
    return (sr.units and sr.units[level]) or 0
end

-- ========= 基础绘制工具 =========
function ui_draw.drawBorder(x, y, w, h, color, bgColor)
    color = color or UI.COLORS.BORDER
    bgColor = bgColor or UI.COLORS.BG
    UI.gpu.setForeground(color)
    UI.gpu.setBackground(bgColor)
    UI.gpu.set(x, y, "┌" .. string.rep("─", w-2) .. "┐")
    for i = y+1, y+h-2 do
        UI.gpu.set(x, i, "│")
        UI.gpu.set(x+w-1, i, "│")
    end
    UI.gpu.set(x, y+h-1, "└" .. string.rep("─", w-2) .. "┘")
end

function ui_draw.drawText(x, y, text, color, bgColor)
    color = color or UI.COLORS.TEXT
    bgColor = bgColor or UI.COLORS.BG
    UI.gpu.setForeground(color)
    UI.gpu.setBackground(bgColor)
    UI.gpu.set(x, y, text)
end

function ui_draw.drawButton(x, y, w, text, color, bgColor)
    bgColor = bgColor or UI.COLORS.BTN_BG
    color = color or UI.COLORS.TEXT
    UI.gpu.setBackground(bgColor)
    UI.gpu.setForeground(color)
    local padding = math.floor((w - unicode.len(text)) / 2)
    UI.gpu.set(x, y, string.rep(" ", padding) .. text .. string.rep(" ", w - padding - unicode.len(text)))
    UI.gpu.setBackground(UI.COLORS.BG)
end

function ui_draw.appendLog(text)
    table.insert(UI.logLines, text)
    if #UI.logLines > UI.maxLogLines then
        table.remove(UI.logLines, 1)
    end
end
function ui_draw.clearLog()
    UI.logLines = {}
end

-- ========= 布局计算（三栏） =========
function ui_draw.calculateLayout()
    UI.W, UI.H = UI.gpu.getResolution()
    UI.areas.title = { x=1, y=1, w=UI.W, h=2 }
    UI.areas.tabBar = { x=2, y=3, w=UI.W-2, h=1 }
    local contentStartY = 4
    local totalContentH = UI.H - contentStartY + 1
    local upperH = math.floor(totalContentH * 0.5)
    local lowerAreaH = totalContentH - upperH - 1
    local ctrlW = math.floor(UI.W * 0.3)
    
    UI.areas.control = { x=2, y=contentStartY, w=ctrlW, h=upperH }
    UI.areas.status = { x=ctrlW+3, y=contentStartY, w=UI.W-ctrlW-4, h=upperH }
    
    local lowerStartY = contentStartY + upperH + 1
    local chartX = 2
    local chartW = ctrlW
    local parallelX = chartX + ctrlW + 1
    local parallelW = UI.W - 2*ctrlW - 4
    local logW = ctrlW
    local logX = UI.W - logW - 1
    
    UI.areas.chart = { x=chartX, y=lowerStartY, w=chartW, h=lowerAreaH }
    UI.areas.parallel = { x=parallelX, y=lowerStartY, w=parallelW, h=lowerAreaH }
    UI.areas.log = { x=logX, y=lowerStartY, w=logW, h=lowerAreaH }
    UI.areas.report = { x=2, y=contentStartY, w=UI.W-4, h=totalContentH-1 }
    
    UI.maxLogLines = lowerAreaH - 3
    UI.render.forceAll = true
end

-- ========= 面板绘制（全部增加背景清除） =========
function ui_draw.drawTitle()
    local area = UI.areas.title
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    local title = "净化水线总控系统 v4.3"
    ui_draw.drawText(math.floor((area.w - unicode.len(title))/2), area.y+1, title, UI.COLORS.TEXT_CYAN)
end

function ui_draw.drawTabBar()
    local area = UI.areas.tabBar
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local tabW = 12
    local x = area.x
    UI.tabButtons = {}
    for i, tab in ipairs(UI.tabs) do
        local isActive = UI.currentTab == tab.id
        local bgColor = isActive and UI.COLORS.BTN_BG_HOVER or UI.COLORS.BTN_BG
        local textColor = isActive and UI.COLORS.TEXT_CYAN or UI.COLORS.TEXT
        ui_draw.drawButton(x, area.y, tabW, tab.name, textColor, bgColor)
        UI.tabButtons[tab.id] = { x=x, y=area.y, w=tabW, h=1, id=tab.id }
        x = x + tabW + 1
    end
end

function ui_draw.drawControlPanel()
    local area = UI.areas.control
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    ui_draw.drawText(area.x+2, area.y+1, "控制面板", UI.COLORS.TEXT_CYAN)
    local y = area.y + 3
    local plantRunning = ui_draw.getPlantRunning()
    local statusText, statusColor
    if CONFIG.SYSTEM_EMERGENCY_STOPPED then
        statusText = "紧急停机"; statusColor = UI.COLORS.TEXT_RED
    elseif UI.systemRunning then
        statusText = plantRunning and "运行中" or "待机中"
        statusColor = plantRunning and UI.COLORS.TEXT_GREEN or UI.COLORS.TEXT_YELLOW
    else
        statusText = "未启动"; statusColor = UI.COLORS.TEXT_YELLOW
    end
    ui_draw.drawText(area.x+2, y, "系统状态：", UI.COLORS.TEXT)
    ui_draw.drawText(area.x+12, y, statusText, statusColor)
    y = y + 2
    ui_draw.drawText(area.x+2, y, "净水主机：", UI.COLORS.TEXT)
    ui_draw.drawText(area.x+12, y, plantRunning and "运行中" or "已停机",
        plantRunning and UI.COLORS.TEXT_GREEN or UI.COLORS.TEXT_RED)
    y = y + 1
    ui_draw.drawText(area.x+2, y, "运行模式：", UI.COLORS.TEXT)
    ui_draw.drawText(area.x+12, y, UI.fullPowerMode and "全力模式" or "普通模式",
        UI.fullPowerMode and UI.COLORS.TEXT_RED or UI.COLORS.TEXT_CYAN)
    y = y + 1
    ui_draw.drawText(area.x+2, y, "可用功率：", UI.COLORS.TEXT)
    ui_draw.drawText(area.x+12, y, utils.formatNumber(CONFIG.TOTAL_POWER).." EU/t", UI.COLORS.TEXT_CYAN)
    y = y + 1
    ui_draw.drawText(area.x+2, y, "总电压级：", UI.COLORS.TEXT)
    local currStr, voltStr = utils.getGTInfo(CONFIG.TOTAL_POWER)
    ui_draw.drawText(area.x+12, y, currStr, UI.COLORS.TEXT_CYAN)
    ui_draw.drawText(area.x+12 + unicode.wlen(currStr), y, voltStr, UI.COLORS.TEXT_PURPLE)
    y = y + 1
    local currentUsedPower = 0
    if CONFIG.LAST_ACTIVE_LEVEL then
        for lv=1,8 do
            if CONFIG.LAST_ACTIVE_LEVEL[lv] then
                currentUsedPower = currentUsedPower + (CONFIG.CALCULATED.LEVEL_TOTAL_POWER[lv] or 0)
            end
        end
    end
    ui_draw.drawText(area.x+2, y, "使用功率：", UI.COLORS.TEXT)
    local usePowerColor
    if alert then
        usePowerColor = alert.getPowerAlertStatus() == "warning"
            and UI.COLORS.ALERT_WARN_TEXT or UI.COLORS.TEXT_GREEN
    else
        local ratio = CONFIG.TOTAL_POWER>0 and (currentUsedPower/CONFIG.TOTAL_POWER) or 0
        usePowerColor = ratio >= (CONFIG.ALERT and CONFIG.ALERT.POWER_HIGH_LOAD_RATIO or 0.8)
            and UI.COLORS.ALERT_WARN_TEXT or UI.COLORS.TEXT_GREEN
    end
    ui_draw.drawText(area.x+12, y, utils.formatNumber(currentUsedPower).." EU/t", usePowerColor)
    y = y + 1
    ui_draw.drawText(area.x+2, y, "使用电压：", UI.COLORS.TEXT)
    local useCurrStr, useVoltStr = utils.getGTInfo(currentUsedPower)
    ui_draw.drawText(area.x+12, y, useCurrStr, UI.COLORS.TEXT_GREEN)
    ui_draw.drawText(area.x+12 + unicode.wlen(useCurrStr), y, useVoltStr, UI.COLORS.TEXT_PURPLE)
    y = y + 1
    local scanResult = ui_draw.getScanResult()
    ui_draw.drawText(area.x+2, y, "部署机器：", UI.COLORS.TEXT)
    ui_draw.drawText(area.x+12, y, (scanResult.total or 0).." 台", UI.COLORS.TEXT_CYAN)
    y = y + 1
    local interval = plantRunning and CONFIG.CHECK_INTERVAL_RUNNING or CONFIG.CHECK_INTERVAL_STOPPED
    ui_draw.drawText(area.x+2, y, "刷新间隔：", UI.COLORS.TEXT)
    ui_draw.drawText(area.x+12, y, interval.." 秒", UI.COLORS.TEXT_CYAN)
    y = y + 3
    local btnW = area.w - 10
    if UI.readonly then
        local disabledColor = 0x64748b
        ui_draw.drawButton(area.x+3, y, btnW, "启动系统[只读]", disabledColor, UI.COLORS.BTN_BG)
        y = y+2
        ui_draw.drawButton(area.x+3, y, btnW, "刷新扫描[只读]", disabledColor, UI.COLORS.BTN_BG)
        y = y+2
        ui_draw.drawButton(area.x+3, y, btnW, "全力模式[只读]", disabledColor, UI.COLORS.BTN_BG)
        y = y+2
        ui_draw.drawText(area.x+2, y, "镜像同步：" .. tostring(UI.syncStatus), UI.COLORS.TEXT_YELLOW)
    else
        UI.buttons.start = { x=area.x+3, y=y, w=btnW, h=1, label="启动系统", action="start" }
        ui_draw.drawButton(area.x+3, y, btnW, "启动系统", UI.COLORS.TEXT,
            UI.systemRunning and UI.COLORS.TEXT_GREEN or UI.COLORS.BTN_BG)
        y = y+2
        UI.buttons.refresh = { x=area.x+3, y=y, w=btnW, h=1, label="刷新扫描", action="refresh" }
        ui_draw.drawButton(area.x+3, y, btnW, "刷新扫描", UI.COLORS.TEXT, UI.COLORS.BTN_BG)
        y = y+2
        UI.buttons.fullpower = { x=area.x+3, y=y, w=btnW, h=1, label="全力模式", action="fullpower" }
        local fpBg = UI.fullPowerMode and UI.COLORS.BTN_FULL_POWER or UI.COLORS.BTN_BG
        ui_draw.drawButton(area.x+3, y, btnW, "全力模式", UI.COLORS.TEXT, fpBg)
    end
end

function ui_draw.drawStatusPanel()
    local area = UI.areas.status
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    ui_draw.drawText(area.x+2, area.y+1, "各级净水状态", UI.COLORS.TEXT_CYAN)
    UI.levelRows = {}
    local y = area.y + 3
    local rowH = 2
    local barX = area.x + 3
    local barW = area.w - 6
    local rightEdge = barX + barW
    for level = 1,8 do
        local cfg = CONFIG.CACHED_CONFIG[level]
        local fluidName = cfg and (cfg.fluidId or CONST.FLUID_NAMES[level]) or CONST.FLUID_NAMES[level]
        local current = ui_draw.getFluidAmount(fluidName)
        local machineCount = ui_draw.getLevelMachineCount(level)
        local isProducing = CONFIG.LAST_ACTIVE_LEVEL and CONFIG.LAST_ACTIVE_LEVEL[level]
        local target = math.max((cfg and cfg.enabled and cfg.threshold or 0),
            CONFIG.CALCULATED.MINIMUM_STOCK[level] or 0)
        UI.levelRows[level] = { x=area.x+2, y=y, w=area.w-4, h=rowH }
        local leftText = string.format("T%d级水 | %s / %s", level,
            utils.formatShortNumber(current), utils.formatShortNumber(target))
        ui_draw.drawText(barX, y, leftText, UI.COLORS.TEXT)
        local statusText, statusColor
        if machineCount == 0 then
            statusText = "未部署"; statusColor = UI.COLORS.TEXT_RED
        elseif isProducing then
            statusText = "运行中"; statusColor = UI.COLORS.TEXT_GREEN
        else
            statusText = "已停止"; statusColor = UI.COLORS.TEXT_YELLOW
        end
        local rightPrefix = string.format("部署机器数：%d台 | ", machineCount)
        local totalRightWidth = unicode.wlen(rightPrefix) + unicode.wlen(statusText)
        local rightStartX = rightEdge - totalRightWidth
        ui_draw.drawText(rightStartX, y, rightPrefix, UI.COLORS.TEXT)
        ui_draw.drawText(rightStartX + unicode.wlen(rightPrefix), y, statusText, statusColor)
        local barY = y+1
        local percent = target>0 and math.min(1, current/target) or 0
        local barBgColor
        if machineCount==0 then barBgColor = UI.COLORS.BAR_BG_NONE
        elseif isProducing then barBgColor = UI.COLORS.BAR_BG_RUNNING
        else barBgColor = UI.COLORS.BAR_BG_IDLE end
        UI.gpu.setBackground(barBgColor)
        UI.gpu.fill(barX, barY, barW, 1, " ")
        local fillWidth = math.floor(barW * percent)
        if fillWidth > 0 then
            UI.gpu.setBackground(UI.COLORS.BAR_FILL)
            UI.gpu.fill(barX, barY, fillWidth, 1, " ")
        end
        UI.gpu.setBackground(UI.COLORS.BG)
        y = y + rowH
    end
end

-- 辅助函数：按显示宽度拆行
local function wrapText(text, maxWidth)
    local lines = {}
    local currentLine = ""
    for i = 1, unicode.len(text) do
        local char = unicode.sub(text, i, i)
        if unicode.wlen(currentLine .. char) > maxWidth then
            table.insert(lines, currentLine)
            currentLine = char
        else
            currentLine = currentLine .. char
        end
    end
    if #currentLine > 0 then
        table.insert(lines, currentLine)
    end
    return lines
end

function ui_draw.drawLogPanel()
    local area = UI.areas.log
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    ui_draw.drawText(area.x+2, area.y+1, "系统日志", UI.COLORS.TEXT_CYAN)

    local y = area.y + 3
    local maxLines = area.h - 3
    local maxWidth = area.w - 4
    local renderedLines = {}

    for i = 1, #UI.logLines do
        local wrapped = wrapText(UI.logLines[i], maxWidth)
        for _, line in ipairs(wrapped) do
            table.insert(renderedLines, line)
        end
    end

    local startLine = math.max(1, #renderedLines - maxLines + 1)
    for i = startLine, #renderedLines do
        if y > area.y + area.h - 2 then break end
        ui_draw.drawText(area.x+2, y, renderedLines[i], UI.COLORS.TEXT)
        y = y + 1
    end
end

-- ========= 并行面板（两列四行，状态底色+水蓝运行，白色文字） =========
local function getLevelDetailLines(level)
    local lines = {}
    table.insert(lines, string.rep("=", 30))
    table.insert(lines, string.format("T%d 级净水单元并行计算详情", level))
    table.insert(lines, string.rep("=", 30))
    local deployedCount = ui_draw.getLevelMachineCount(level)
    local powerPerParallel = CONST.POWER_LEVELS[level] or 0
    if deployedCount > 0 and powerPerParallel > 0 then
        local calc = CONFIG.CALCULATED
        local currSingle, voltSingle = utils.getGTInfoHighVoltage(powerPerParallel)
        local currMachine, voltMachine = utils.getGTInfo(calc.SINGLE_MACHINE_POWER[level] or 0)
        local currLevel, voltLevel = utils.getGTInfo(calc.LEVEL_TOTAL_POWER[level] or 0)
        table.insert(lines, string.format("已部署机器数量：%d 台", deployedCount))
        table.insert(lines, string.format("单并行功耗：%s EU/t (%s%s)", utils.formatNumber(powerPerParallel), currSingle, voltSingle))
        table.insert(lines, string.format("单台最大并行上限：%s", utils.formatNumber(CONST.MAX_SINGLE_PARALLEL)))
        table.insert(lines, string.format("系统总功率允许总并行上限：%s", utils.formatNumber(math.floor(CONFIG.TOTAL_POWER / powerPerParallel))))
        table.insert(lines, "----------------------------------------")
        table.insert(lines, string.format("建议每台设置并行数：%s", utils.formatNumber(calc.SUGGEST_SINGLE_PARALLEL[level] or 0)))
        table.insert(lines, string.format("单台功耗：%s EU/t (%s%s)", utils.formatNumber(calc.SINGLE_MACHINE_POWER[level] or 0), currMachine, voltMachine))
        table.insert(lines, string.format("该等级全开总功耗：%s EU/t (%s%s)", utils.formatNumber(calc.LEVEL_TOTAL_POWER[level] or 0), currLevel, voltLevel))
        table.insert(lines, string.format("该等级总并行数：%s", utils.formatNumber(calc.LEVEL_TOTAL_PARALLEL[level] or 0)))
    else
        table.insert(lines, "该等级未部署有效机器")
    end
    return lines
end

function ui_draw.drawParallelPanel()
    local area = UI.areas.parallel
    -- 清除整个区域
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)

    if UI.parallelMode == "detail" and UI.parallelDetailLevel then
        -- 详情模式
        local title = string.format("并行详情 - T%d级", UI.parallelDetailLevel)
        ui_draw.drawText(area.x+2, area.y+1, title, UI.COLORS.TEXT_CYAN)
        local lines = getLevelDetailLines(UI.parallelDetailLevel)
        local y = area.y + 3
        local maxLines = area.h - 3
        for i = 1, math.min(#lines, maxLines) do
            local line = lines[i]
            if unicode.wlen(line) > area.w-4 then
                line = unicode.sub(line, 1, area.w-5) .. "~"
            end
            ui_draw.drawText(area.x+2, y, line, UI.COLORS.TEXT)
            y = y + 1
        end
    else
        -- 概况模式：两列四行，防溢出
        ui_draw.drawText(area.x+2, area.y+1, "并行概况", UI.COLORS.TEXT_CYAN)
        local gridX = area.x + 2
        local gridY = area.y + 3
        local gridW = area.w - 4
        local gridH = area.h - 4
        if gridW < 20 or gridH < 8 then return end

        local cols, rows = 2, 4
        local gapX, gapY = 2, 1

        -- 动态计算卡片高度，绝不越界
        local maxCellH = math.floor((gridH - gapY * (rows - 1)) / rows)
        local cellH = math.max(3, math.min(maxCellH, 6))   -- 最少3行，最多6行
        local usedH = cellH * rows + gapY * (rows - 1)
        if usedH > gridH then
            cellH = math.max(3, math.floor((gridH - gapY * (rows - 1)) / rows))
            usedH = cellH * rows + gapY * (rows - 1)
        end

        local cellW = math.floor((gridW - gapX * (cols - 1)) / cols)
        local usedW = cellW * cols + gapX * (cols - 1)
        local offsetX = gridX + math.floor((gridW - usedW) / 2)
        local offsetY = gridY + math.floor((gridH - usedH) / 2)

        -- 水蓝色运行底纹（仅用于“运行中”）
        local WATER_BLUE = 0x0ea5e9

        for level = 1, 8 do
            local row = (level - 1) % rows
            local col = math.floor((level - 1) / rows)
            local cx = offsetX + col * (cellW + gapX)
            local cy = offsetY + row * (cellH + gapY)

            local machineCount = ui_draw.getLevelMachineCount(level)
            local suggestSingle = CONFIG.CALCULATED.SUGGEST_SINGLE_PARALLEL[level] or 0
            local totalParallel = CONFIG.CALCULATED.LEVEL_TOTAL_PARALLEL[level] or 0
            local isActive = CONFIG.LAST_ACTIVE_LEVEL and CONFIG.LAST_ACTIVE_LEVEL[level]
            local isDeployed = machineCount > 0

            -- ★ 底纹规则：与八级水状态栏完全一致，但“运行中”改为水蓝色
            local cardBgColor
            if not isDeployed then
                cardBgColor = UI.COLORS.BAR_BG_NONE      -- 深红
            elseif isActive then
                cardBgColor = WATER_BLUE                 -- 水蓝色（运行中）
            else
                cardBgColor = UI.COLORS.BAR_BG_IDLE      -- 灰色（待机/停止）
            end

            -- ★ 边框颜色根据底纹微调，更精致
            local cardBorderColor
            if not isDeployed then
                cardBorderColor = 0xff6b6b   -- 浅红
            elseif isActive then
                cardBorderColor = 0x7dd3fc   -- 浅蓝
            else
                cardBorderColor = 0x94a3b8   -- 浅灰
            end

            -- 填充卡片背景
            UI.gpu.setBackground(cardBgColor)
            UI.gpu.fill(cx, cy, cellW, cellH, " ")

            -- 绘制边框
            ui_draw.drawBorder(cx, cy, cellW, cellH, cardBorderColor, cardBgColor)

            local innerX = cx + 1
            local innerW = cellW - 2
            local CARD_TEXT = 0xffffff   -- 纯白文字

            -- 内容绘制（根据可用行数动态显示）
            if cellH >= 2 then
                local title = "T" .. level
                local titleX = innerX + math.floor((innerW - unicode.wlen(title)) / 2)
                ui_draw.drawText(titleX, cy + 1, title, CARD_TEXT, cardBgColor)
            end
            if cellH >= 3 then
                local machineText = string.format("%d台机组", machineCount)
                local machineX = innerX + math.floor((innerW - unicode.wlen(machineText)) / 2)
                ui_draw.drawText(machineX, cy + 2, machineText, CARD_TEXT, cardBgColor)
            end
            if cellH >= 4 then
                local parallelText = string.format("%s/%s",
                    utils.formatShortNumber(suggestSingle),
                    utils.formatShortNumber(totalParallel))
                local parallelX = innerX + math.floor((innerW - unicode.wlen(parallelText)) / 2)
                ui_draw.drawText(parallelX, cy + 3, parallelText, CARD_TEXT, cardBgColor)
            end
            if cellH >= 5 then
                -- 状态标签（保持彩色以突出显示）
                local tagText, tagColor
                if isActive then
                    tagText = "运行中"
                    tagColor = UI.COLORS.TEXT_GREEN   -- 绿色文字，与蓝底形成对比
                elseif isDeployed then
                    tagText = "待机"
                    tagColor = UI.COLORS.TEXT_YELLOW
                else
                    tagText = "未部署"
                    tagColor = UI.COLORS.TEXT_RED
                end
                local tagX = innerX + math.floor((innerW - unicode.wlen(tagText)) / 2)
                ui_draw.drawText(tagX, cy + 4, tagText, tagColor, cardBgColor)
            end
        end
    end
end

-- ========= 脏区域重绘 =========
local SEP = "\x1f"
local function usedPower()
    local u = 0
    if CONFIG.LAST_ACTIVE_LEVEL then
        for lv=1,8 do
            if CONFIG.LAST_ACTIVE_LEVEL[lv] then
                u = u + (CONFIG.CALCULATED.LEVEL_TOTAL_POWER[lv] or 0)
            end
        end
    end
    return u
end
local function fp_title()      return tostring(UI.fullPowerMode and 1 or 0) end
local function fp_tabBar()     return UI.currentTab or "" end
local function fp_control()
    local sr = ui_draw.getScanResult()
    return table.concat({
        UI.fullPowerMode and 1 or 0,
        UI.systemRunning and 1 or 0,
        CONFIG.SYSTEM_EMERGENCY_STOPPED and 1 or 0,
        ui_draw.getPlantRunning() and 1 or 0,
        CONFIG.TOTAL_POWER,
        usedPower(),
        sr.total or 0,
        UI.readonly and 1 or 0,
        UI.syncStatus or "",
    }, SEP)
end
local function fp_status()
    local parts = { tostring(UI.fullPowerMode and 1 or 0) }
    for lv=1,8 do
        local cfg = CONFIG.CACHED_CONFIG[lv]
        local name = cfg and (cfg.fluidId or CONST.FLUID_NAMES[lv]) or CONST.FLUID_NAMES[lv]
        local cur = ui_draw.getFluidAmount(name)
        local tgt = math.max((cfg and cfg.enabled and cfg.threshold or 0), CONFIG.CALCULATED.MINIMUM_STOCK[lv] or 0)
        local mc = ui_draw.getLevelMachineCount(lv)
        local prod = CONFIG.LAST_ACTIVE_LEVEL and CONFIG.LAST_ACTIVE_LEVEL[lv] and 1 or 0
        parts[#parts+1] = lv .. ":" .. cur .. "/" .. tgt .. "/" .. mc .. "/" .. prod
    end
    return table.concat(parts, SEP)
end
local function fp_chart()
    local n = #UI.historyData
    local firstT = n>0 and UI.historyData[1].time or 0
    local lastT  = n>0 and UI.historyData[n].time or 0
    local sum = 0
    if n>0 then
        local a,b = UI.historyData[1].levels, UI.historyData[n].levels
        for lv=1,8 do sum = sum + ((b[lv] or 0) - (a[lv] or 0)) end
    end
    return table.concat({
        UI.chartMode or "", UI.currentDetailLevel or 0, UI.fullPowerMode and 1 or 0,
        n, firstT, lastT, sum
    }, SEP)
end
local function fp_log()
    local n = #UI.logLines
    local first = n>0 and UI.logLines[1] or ""
    local last = n>0 and UI.logLines[n] or ""
    return table.concat({ tostring(UI.fullPowerMode and 1 or 0), n, first, last }, SEP)
end
local function fp_report()
    local rp = UI.reportPanel
    local src = rp.timeDimension=="hour" and CONFIG.REPORT.HOUR_DATA or CONFIG.REPORT.DAY_DATA
    local n = #src
    local lv = rp.viewLevel
    local lastVal = 0
    if n>0 then lastVal = src[n].levels[lv] or 0 end
    local firstT = n>0 and src[1].time or 0
    local lastT  = n>0 and src[n].time or 0
    return table.concat({
        tostring(UI.fullPowerMode and 1 or 0), rp.timeDimension or "", lv, n, lastVal, firstT, lastT
    }, SEP)
end
local function fp_parallel()
    local parts = { tostring(UI.parallelMode), tostring(UI.parallelDetailLevel or 0), tostring(UI.fullPowerMode and 1 or 0) }
    for lv=1,8 do
        local mc = ui_draw.getLevelMachineCount(lv)
        local ss = CONFIG.CALCULATED.SUGGEST_SINGLE_PARALLEL[lv] or 0
        local tp = CONFIG.CALCULATED.LEVEL_TOTAL_PARALLEL[lv] or 0
        local act = CONFIG.LAST_ACTIVE_LEVEL and CONFIG.LAST_ACTIVE_LEVEL[lv] and 1 or 0
        parts[#parts+1] = table.concat({lv, mc, ss, tp, act}, ":")
    end
    return table.concat(parts, SEP)
end

local PANELS = {
    title   = { draw = function() ui_draw.drawTitle() end,        fp = fp_title },
    tabBar  = { draw = function() ui_draw.drawTabBar() end,       fp = fp_tabBar },
    control = { draw = function() ui_draw.drawControlPanel() end, fp = fp_control },
    status  = { draw = function() ui_draw.drawStatusPanel() end,  fp = fp_status },
    chart   = { draw = function() getChart().drawChartPanel() end,fp = fp_chart },
    parallel= { draw = function() ui_draw.drawParallelPanel() end,fp = fp_parallel },
    log     = { draw = function() ui_draw.drawLogPanel() end,     fp = fp_log },
    report  = { draw = function() getChart().drawReportPanel() end,fp = fp_report },
}
local TAB_PANELS = {
    overview = { "title", "tabBar", "control", "status", "chart", "parallel", "log" },
    report   = { "title", "tabBar", "report" },
}

function ui_draw.invalidateAll() UI.render.forceAll = true end
function ui_draw.renderAll(forceAll)
    forceAll = forceAll or UI.render.forceAll
    local fps = UI.render.fingerprints
    if not forceAll then
        local tabFp = PANELS.tabBar.fp()
        if fps.tabBar ~= nil and fps.tabBar ~= tabFp then forceAll = true end
    end
    if forceAll then
        UI.gpu.setBackground(UI.COLORS.BG)
        UI.gpu.fill(1,1,UI.W,UI.H," ")
        for name in pairs(fps) do fps[name] = nil end
    end
    local list = TAB_PANELS[UI.currentTab] or TAB_PANELS.overview
    for _, name in ipairs(list) do
        local p = PANELS[name]
        local newFp = p.fp()
        if forceAll or fps[name] ~= newFp then
            p.draw()
            fps[name] = newFp
        end
    end
    UI.render.forceAll = false
end

return ui_draw
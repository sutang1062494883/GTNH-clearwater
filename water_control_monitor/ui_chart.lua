-- ui_chart.lua
local unicode = require("unicode")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local utils = require("utils")
local UI = require("ui_config")
local ui_draw = require("ui_draw")

local ui_chart = {}

-- 颜色混合辅助
local function blendColor(c1, c2, t)
    t = math.max(0, math.min(1, t))
    local r1 = math.floor(c1 / 65536) % 256
    local g1 = math.floor(c1 / 256) % 256
    local b1 = c1 % 256
    local r2 = math.floor(c2 / 65536) % 256
    local g2 = math.floor(c2 / 256) % 256
    local b2 = c2 % 256
    local r = math.floor(r1 + (r2 - r1) * t)
    local g = math.floor(g1 + (g2 - g1) * t)
    local b = math.floor(b1 + (b2 - b1) * t)
    return r * 65536 + g * 256 + b
end

-- 绘制网格（点状虚线）
local function drawGridArea(area)
    local x0, y0 = area.x + 2, area.y + 2
    local w, h = area.w - 4, area.h - 4
    if w < 10 or h < 4 then return end

    UI.gpu.setForeground(0x2a3a5a)  -- 低亮度
    -- 水平网格（4条）
    for i = 0, 3 do
        local y = y0 + math.floor(h * i / 4)
        for x = 0, w - 1 do
            UI.gpu.set(x0 + x, y, "·")
        end
    end
    -- 垂直网格（5条）
    for i = 0, 4 do
        local x = x0 + math.floor(w * i / 4)
        for y = 0, h - 1 do
            UI.gpu.set(x, y0 + y, "·")
        end
    end

    -- 坐标轴（用亮色画粗线）
    UI.gpu.setForeground(0x64748b)
    for i = 0, w - 1 do
        UI.gpu.set(x0 + i, y0 + h - 1, "─")
    end
    for i = 0, h - 1 do
        UI.gpu.set(x0 - 1, y0 + i, "│")
    end
    UI.gpu.set(x0 - 1, y0 + h - 1, "└")
end

-- 绘制折线（使用字符“█”连接）
local function drawLineChart(area, values, times, lineColor, fillColor)
    local x0, y0 = area.x + 2, area.y + 2
    local w, h = area.w - 4, area.h - 4
    if w < 10 or h < 4 then return end

    -- 清空绘图区
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(x0, y0, w, h, " ")

    -- 计算范围
    local n = #values
    if n < 2 then
        ui_draw.drawText(x0 + math.floor((w - 8) / 2), y0 + math.floor(h / 2), "数据采集中...", UI.COLORS.TEXT_YELLOW)
        return
    end
    local minVal = math.min(table.unpack(values))
    local maxVal = math.max(table.unpack(values))
    if minVal == maxVal then maxVal = minVal + 1 end

    -- 绘制网格
    drawGridArea(area)

    -- 计算点坐标
    local points = {}
    for i = 1, n do
        local px = x0 + math.floor((i - 1) / (n - 1) * (w - 1))
        local ratio = (values[i] - minVal) / (maxVal - minVal)
        local py = y0 + h - 1 - math.floor(ratio * (h - 1))
        table.insert(points, {x = px, y = py})
    end

    -- 填充区域（可选）
    if fillColor then
        UI.gpu.setForeground(fillColor)
        for i = 1, n - 1 do
            local p1, p2 = points[i], points[i + 1]
            local yMin, yMax = math.min(p1.y, p2.y), math.max(p1.y, p2.y)
            for y = yMax, y0 + h - 1 do
                for x = p1.x, p2.x do
                    UI.gpu.set(x, y, "░")  -- 浅色填充
                end
            end
        end
    end

    -- 绘制折线（用█字符，宽度1）
    UI.gpu.setForeground(lineColor)
    for i = 1, n - 1 do
        local p1, p2 = points[i], points[i + 1]
        -- 水平部分
        if p1.x == p2.x then
            local yMin, yMax = math.min(p1.y, p2.y), math.max(p1.y, p2.y)
            for y = yMin, yMax do UI.gpu.set(p1.x, y, "█") end
        else
            -- 简单插值绘制
            local steps = math.abs(p2.x - p1.x)
            for s = 0, steps do
                local x = p1.x + math.floor((p2.x - p1.x) * s / steps)
                local y = p1.y + math.floor((p2.y - p1.y) * s / steps)
                UI.gpu.set(x, y, "█")
            end
        end
    end

    -- Y轴刻度
    UI.gpu.setForeground(UI.COLORS.TEXT_YELLOW)
    ui_draw.drawText(x0 - 1, y0, utils.formatShortNumber(maxVal))
    ui_draw.drawText(x0 - 1, y0 + h - 1, utils.formatShortNumber(minVal))

    -- X轴时间标签
    local now = computer.uptime()
    local labelIndexes = {1, math.floor(n / 2) + 1, n}
    for _, idx in ipairs(labelIndexes) do
        local timeDiff = now - times[idx]
        local label
        if timeDiff < 60 then label = (idx == n) and "现在" or "刚刚"
        else label = string.format("-%dm", math.floor(timeDiff / 60)) end
        local px = points[idx].x
        local labelX = px - math.floor(unicode.wlen(label) / 2)
        labelX = math.max(x0, math.min(labelX, x0 + w - unicode.wlen(label)))
        ui_draw.drawText(labelX, y0 + h, label, UI.COLORS.TEXT)
    end
end

-- 绘制柱状图（渐变）
local function drawBarChart(area, changes, labels)
    local x0, y0 = area.x + 2, area.y + 3
    local w, h = area.w - 4, area.h - 4
    if h < 5 or w < 20 then return end

    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(x0, y0, w, h, " ")

    -- 计算最大值
    local maxAbs = 0
    for i = 1, #changes do maxAbs = math.max(maxAbs, math.abs(changes[i])) end
    if maxAbs == 0 then maxAbs = 1 end

    -- 绘制网格和坐标轴
    drawGridArea(area)

    local zeroY = y0 + math.floor(h / 2)
    -- 画零轴线
    UI.gpu.setForeground(UI.COLORS.TEXT_CYAN)
    for x = 0, w - 1 do UI.gpu.set(x0 + x, zeroY, "─") end

    local slotCount = #changes
    local slotW = math.floor(w / slotCount)
    local barW = math.max(1, math.min(slotW - 2, 3))

    for i, delta in ipairs(changes) do
        local slotCenterX = x0 + math.floor((i - 0.5) * slotW)
        local barX = slotCenterX - math.floor(barW / 2)
        local barHeight = math.floor((math.abs(delta) / maxAbs) * (h / 2 - 1))
        barHeight = math.max(0, barHeight)

        local topColor, bottomColor
        if delta >= 0 then
            topColor = UI.COLORS.TEXT_GREEN
            bottomColor = 0x064e3b
        else
            topColor = UI.COLORS.TEXT_RED
            bottomColor = 0x450a0a
        end

        -- 绘制渐变柱（逐行填充）
        if barHeight > 0 then
            for step = 0, barHeight - 1 do
                local t = step / math.max(1, barHeight - 1)
                local color = blendColor(topColor, bottomColor, t)
                UI.gpu.setBackground(color)
                local yPos = delta >= 0 and (zeroY - barHeight + step) or (zeroY + barHeight - step)
                for bx = barX, barX + barW - 1 do
                    UI.gpu.set(bx, yPos, " ")
                end
            end
        end
        UI.gpu.setBackground(UI.COLORS.BG)

        -- 数值标签
        local label = delta > 0 and "+" .. utils.formatShortNumber(delta) or utils.formatShortNumber(delta)
        local labelX = slotCenterX - math.floor(unicode.wlen(label) / 2)
        local labelY = delta >= 0 and (zeroY - barHeight - 1) or (zeroY + barHeight + 1)
        if labelY >= y0 and labelY < y0 + h then
            ui_draw.drawText(labelX, labelY, label, topColor)
        end

        -- 等级标签
        ui_draw.drawText(slotCenterX - math.floor(unicode.wlen(labels[i]) / 2), y0 + h, labels[i], UI.COLORS.TEXT)
    end
end

-- 对外接口
function ui_chart.drawBarChart(area)
    if #UI.historyData < 2 then
        local x0, y0 = area.x + 2, area.y + 3
        local w, h = area.w - 4, area.h - 4
        UI.gpu.setBackground(UI.COLORS.BG)
        UI.gpu.fill(x0, y0, w, h, " ")
        ui_draw.drawText(x0 + math.floor((w - 8) / 2), y0 + math.floor(h / 2), "数据采集中...", UI.COLORS.TEXT_YELLOW)
        return
    end

    local first = UI.historyData[1]
    local last = UI.historyData[#UI.historyData]
    local changes = {}
    for lv = 1, 8 do changes[lv] = (last.levels[lv] or 0) - (first.levels[lv] or 0) end
    local labels = {}
    for i = 1, 8 do labels[i] = "T" .. i end
    drawBarChart(area, changes, labels)
end

function ui_chart.drawLineChart(area)
    local level = UI.currentDetailLevel
    if not level then return end

    local data, times = {}, {}
    for i = 1, #UI.historyData do
        table.insert(data, UI.historyData[i].levels[level] or 0)
        table.insert(times, UI.historyData[i].time)
    end

    if #data < 2 then
        local x0, y0 = area.x + 2, area.y + 2
        local w, h = area.w - 4, area.h - 4
        UI.gpu.setBackground(UI.COLORS.BG)
        UI.gpu.fill(x0, y0, w, h, " ")
        ui_draw.drawText(x0 + math.floor((w - 8) / 2), y0 + math.floor(h / 2), "数据采集中...", UI.COLORS.TEXT_YELLOW)
        return
    end

    drawLineChart(area, data, times, UI.COLORS.TEXT_CYAN, nil)
end

function ui_chart.drawChartPanel()
    local area = UI.areas.chart
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    local title = UI.chartMode == "overview" and "水量变化(1h)" or string.format("T%d级趋势(1h)", UI.currentDetailLevel)
    ui_draw.drawText(area.x + 2, area.y + 1, title, UI.COLORS.TEXT_CYAN)

    if UI.chartMode == "overview" then
        ui_chart.drawBarChart(area)
    else
        ui_chart.drawLineChart(area)
    end
end

function ui_chart.drawReportPanel()
    local area = UI.areas.report
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")
    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    ui_draw.drawText(area.x + 2, area.y + 1, "详细报表", UI.COLORS.TEXT_CYAN)

    local toolY = area.y + 3
    local btnW = 10
    UI.reportPanel.tabButtons = {}

    -- 小时/天按钮
    UI.reportPanel.tabButtons.timeHour = { x = area.x + 3, y = toolY, w = btnW, h = 1, action = "time_hour" }
    local hourBg = UI.reportPanel.timeDimension == "hour" and UI.COLORS.BTN_BG_HOVER or UI.COLORS.BTN_BG
    local hourColor = UI.reportPanel.timeDimension == "hour" and UI.COLORS.TEXT_CYAN or UI.COLORS.TEXT
    ui_draw.drawButton(area.x + 3, toolY, btnW, "小时维度", hourColor, hourBg)

    UI.reportPanel.tabButtons.timeDay = { x = area.x + 3 + btnW + 1, y = toolY, w = btnW, h = 1, action = "time_day" }
    local dayBg = UI.reportPanel.timeDimension == "day" and UI.COLORS.BTN_BG_HOVER or UI.COLORS.BTN_BG
    local dayColor = UI.reportPanel.timeDimension == "day" and UI.COLORS.TEXT_CYAN or UI.COLORS.TEXT
    ui_draw.drawButton(area.x + 3 + btnW + 1, toolY, btnW, "天维度", dayColor, dayBg)

    -- 等级按钮
    local levelBtnStartX = area.x + 3 + btnW * 2 + 3
    for level = 1, 8 do
        local lvlBtnX = levelBtnStartX + (level - 1) * (btnW - 2 + 1)
        UI.reportPanel.tabButtons["level_" .. level] = { x = lvlBtnX, y = toolY, w = btnW - 2, h = 1, action = "level_" .. level }
        local isActive = UI.reportPanel.viewLevel == level
        local lvlBg = isActive and UI.COLORS.BTN_BG_HOVER or UI.COLORS.BTN_BG
        local lvlColor = isActive and UI.COLORS.TEXT_CYAN or UI.COLORS.TEXT
        ui_draw.drawButton(lvlBtnX, toolY, btnW - 2, "T" .. level, lvlColor, lvlBg)
    end

    -- 图表区域
    local chartY = toolY + 2
    local chartH = area.y + area.h - chartY - 2
    local chartX = area.x + 3
    local chartW = area.w - 6
    if chartH < 4 or chartW < 20 then return end

    local dataSource = UI.reportPanel.timeDimension == "hour" and CONFIG.REPORT.HOUR_DATA or CONFIG.REPORT.DAY_DATA
    local level = UI.reportPanel.viewLevel
    local data, times = {}, {}
    for i = 1, #dataSource do
        table.insert(data, dataSource[i].levels[level] or 0)
        table.insert(times, dataSource[i].time)
    end

    if #data < 2 then
        local tip = UI.reportPanel.timeDimension == "hour"
            and "小时数据采集中，请运行满1小时后查看"
            or "天数据采集中，请运行满1天后查看"
        ui_draw.drawText(chartX + math.floor((chartW - unicode.wlen(tip)) / 2),
            chartY + math.floor(chartH / 2), tip, UI.COLORS.TEXT_YELLOW)
        return
    end

    -- 折线图
    local plotArea = { x = chartX, y = chartY, w = chartW, h = chartH }
    drawLineChart(plotArea, data, times, UI.COLORS.TEXT_GREEN, blendColor(0x22c55e, UI.COLORS.BG, 0.7))
end

return ui_chart

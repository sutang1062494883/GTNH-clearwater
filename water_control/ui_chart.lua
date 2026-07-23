-- ui_chart.lua
-- 图表绘制：柱状图（总览）、折线图（详情）、报表页折线图
local unicode = require("unicode")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local utils = require("utils")
local UI = require("ui_config")
local ui_draw = require("ui_draw")
local ui_chart = {}

function ui_chart.drawBarChart(area)
    local paddingLeft = 1
    local paddingRight = 2
    local paddingTop = 1
    local paddingBottom = 2
    local chartX = area.x + 2
    local chartY = area.y + 3
    local chartW = area.w - 4
    local chartH = area.h - 4
    if chartH < 5 or chartW < 20 then return end

    -- 【修复】清空柱状图内部绘图区背景，消除上一帧残留
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(chartX, chartY, chartW, chartH, " ")

    local innerX = chartX + paddingLeft
    local innerY = chartY + paddingTop
    local innerW = chartW - paddingLeft - paddingRight
    local innerH = chartH - paddingTop - paddingBottom
    if innerH < 3 or innerW < 10 then return end

    if #UI.historyData < 2 then
        ui_draw.drawText(chartX + math.floor((chartW - 8) / 2),
            chartY + math.floor(chartH / 2), "数据采集中...", UI.COLORS.TEXT_YELLOW)
        return
    end

    local changes = {}
    local maxAbsChange = 0
    local firstSample = UI.historyData[1]
    local lastSample = UI.historyData[#UI.historyData]
    for level = 1, 8 do
        local delta = (lastSample.levels[level] or 0) - (firstSample.levels[level] or 0)
        changes[level] = delta
        maxAbsChange = math.max(maxAbsChange, math.abs(delta))
    end
    if maxAbsChange == 0 then maxAbsChange = 1 end

    local zeroLineY = innerY + math.floor(innerH / 2)
    UI.gpu.setForeground(UI.COLORS.TEXT)
    for y = innerY, innerY + innerH - 1 do
        UI.gpu.set(innerX - 1, y, "│")
    end
    UI.gpu.set(innerX - 1, innerY + innerH, "└")
    for x = innerX, innerX + innerW - 1 do
        UI.gpu.set(x, innerY + innerH, "─")
    end

    UI.gpu.setForeground(UI.COLORS.TEXT_CYAN)
    for x = innerX, innerX + innerW - 1 do
        UI.gpu.set(x, zeroLineY, "─")
    end

    local slotCount = 8
    local slotWidth = math.floor(innerW / slotCount)
    local barWidth = math.max(1, math.min(slotWidth - 2, 3))
    for level = 1, 8 do
        local delta = changes[level]
        local slotCenterX = innerX + math.floor((level - 0.5) * slotWidth)
        local barX = slotCenterX - math.floor(barWidth / 2)
        local barHeight = math.floor((math.abs(delta) / maxAbsChange) * (innerH / 2 - 1))
        barHeight = math.max(0, barHeight)
        local barColor = delta >= 0 and UI.COLORS.TEXT_GREEN or UI.COLORS.TEXT_RED

        UI.gpu.setBackground(barColor)
        if delta >= 0 then
            local yStart = zeroLineY - barHeight
            if barHeight > 0 then
                UI.gpu.fill(barX, yStart, barWidth, barHeight, " ")
                local valLabel = "+" .. utils.formatShortNumber(delta)
                local labelX = slotCenterX - math.floor(unicode.wlen(valLabel) / 2)
                ui_draw.drawText(labelX, yStart - 1, valLabel, barColor)
            end
        else
            local yStart = zeroLineY + 1
            if barHeight > 0 then
                UI.gpu.fill(barX, yStart, barWidth, barHeight, " ")
                local valLabel = utils.formatShortNumber(delta)
                local labelX = slotCenterX - math.floor(unicode.wlen(valLabel) / 2)
                ui_draw.drawText(labelX, yStart + barHeight, valLabel, barColor)
            end
        end
        UI.gpu.setBackground(UI.COLORS.BG)

        local label = "T" .. level
        local labelX = slotCenterX - math.floor(unicode.wlen(label) / 2)
        ui_draw.drawText(labelX, innerY + innerH + 1, label, UI.COLORS.TEXT)
    end
end

function ui_chart.drawLineChart(area)
    local level = UI.currentDetailLevel
    if not level then return end

    local chartX = area.x + 2
    local chartY = area.y + 3
    local chartW = area.w - 4
    local chartH = area.h - 4
    if chartH < 4 or chartW < 10 then return end

    -- 【修复】清空折线图内部绘图区背景，消除上一帧残留
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(chartX, chartY, chartW, chartH, " ")

    local now = computer.uptime()
    local data, times = {}, {}
    for i = 1, #UI.historyData do
        table.insert(data, UI.historyData[i].levels[level] or 0)
        table.insert(times, UI.historyData[i].time)
    end
    local pointCount = #data
    if pointCount < 2 then
        ui_draw.drawText(chartX, chartY + math.floor(chartH/2), "数据采集中...", UI.COLORS.TEXT_YELLOW)
        return
    end

    local minVal = math.min(table.unpack(data))
    local maxVal = math.max(table.unpack(data))
    if minVal == maxVal then maxVal = minVal + 1 end
    local valueRange = maxVal - minVal
    local innerH = chartH - 1
    local innerY = chartY

    local points = {}
    for i = 1, pointCount do
        local x = chartX + math.floor((i - 1) / (pointCount - 1) * (chartW - 1))
        local yRatio = (data[i] - minVal) / valueRange
        local y = innerY + innerH - 1 - math.floor(yRatio * (innerH - 1))
        table.insert(points, {x=x, y=y})
    end

    UI.gpu.setBackground(UI.COLORS.BAR_FILL)
    for _, p in ipairs(points) do
        local drawX = math.max(chartX, p.x - 1)
        local drawY = math.max(innerY, p.y - 1)
        local realW = math.min(2, chartX + chartW - drawX)
        local realH = math.min(2, innerY + innerH - drawY)
        if realW > 0 and realH > 0 then
            UI.gpu.fill(drawX, drawY, realW, realH, " ")
        end
    end
    UI.gpu.setBackground(UI.COLORS.BG)

    ui_draw.drawText(chartX, innerY, utils.formatShortNumber(maxVal), UI.COLORS.TEXT)
    ui_draw.drawText(chartX, innerY + innerH - 1, utils.formatShortNumber(minVal), UI.COLORS.TEXT)

    local xAxisY = innerY + innerH
    UI.gpu.setForeground(UI.COLORS.TEXT)
    UI.gpu.set(chartX - 1, xAxisY - 1, "└")
    for x = chartX, chartX + chartW - 1 do
        UI.gpu.set(x, xAxisY - 1, "─")
    end

    local labelIndexes = {1, math.floor(pointCount / 2) + 1, pointCount}
    for _, idx in ipairs(labelIndexes) do
        local timeDiff = now - times[idx]
        local label
        if timeDiff < 60 then
            label = idx == pointCount and "现在" or "刚刚"
        else
            label = string.format("-%dm", math.floor(timeDiff / 60))
        end
        local labelX = points[idx].x - math.floor(unicode.wlen(label) / 2)
        labelX = math.max(chartX, math.min(labelX, chartX + chartW - unicode.wlen(label)))
        ui_draw.drawText(labelX, xAxisY, label, UI.COLORS.TEXT)
    end
end

function ui_chart.drawChartPanel()
    local area = UI.areas.chart

    -- 【修复】整区域背景清空，彻底覆盖上一帧所有残留内容
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")

    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    local title = UI.chartMode == "overview" and "水量变化(1h)"
        or string.format("T%d级趋势(1h)", UI.currentDetailLevel)
    ui_draw.drawText(area.x + 2, area.y + 1, title, UI.COLORS.TEXT_CYAN)

    if UI.chartMode == "overview" then
        ui_chart.drawBarChart(area)
    else
        ui_chart.drawLineChart(area)
    end
end

function ui_chart.drawReportPanel()
    local area = UI.areas.report

    -- 【修复】报表页整区域背景清空，切换维度/等级时无残留
    UI.gpu.setBackground(UI.COLORS.BG)
    UI.gpu.fill(area.x, area.y, area.w, area.h, " ")

    local borderColor = UI.fullPowerMode and UI.COLORS.BORDER_ALERT or UI.COLORS.BORDER
    ui_draw.drawBorder(area.x, area.y, area.w, area.h, borderColor)
    ui_draw.drawText(area.x + 2, area.y + 1, "详细报表", UI.COLORS.TEXT_CYAN)

    local toolY = area.y + 3
    local btnW = 10
    UI.reportPanel.tabButtons = {}

    UI.reportPanel.tabButtons.timeHour = { x=area.x + 3, y=toolY, w=btnW, h=1, action="time_hour" }
    local hourBg = UI.reportPanel.timeDimension == "hour" and UI.COLORS.BTN_BG_HOVER or UI.COLORS.BTN_BG
    local hourColor = UI.reportPanel.timeDimension == "hour" and UI.COLORS.TEXT_CYAN or UI.COLORS.TEXT
    ui_draw.drawButton(area.x + 3, toolY, btnW, "小时维度", hourColor, hourBg)

    UI.reportPanel.tabButtons.timeDay = { x=area.x + 3 + btnW + 1, y=toolY, w=btnW, h=1, action="time_day" }
    local dayBg = UI.reportPanel.timeDimension == "day" and UI.COLORS.BTN_BG_HOVER or UI.COLORS.BTN_BG
    local dayColor = UI.reportPanel.timeDimension == "day" and UI.COLORS.TEXT_CYAN or UI.COLORS.TEXT
    ui_draw.drawButton(area.x + 3 + btnW + 1, toolY, btnW, "天维度", dayColor, dayBg)

    local levelBtnStartX = area.x + 3 + btnW*2 + 3
    for level = 1, 8 do
        local lvlBtnX = levelBtnStartX + (level-1)*(btnW-2 + 1)
        UI.reportPanel.tabButtons["level_"..level] = { x=lvlBtnX, y=toolY, w=btnW-2, h=1, action="level_"..level }
        local isActive = UI.reportPanel.viewLevel == level
        local lvlBg = isActive and UI.COLORS.BTN_BG_HOVER or UI.COLORS.BTN_BG
        local lvlColor = isActive and UI.COLORS.TEXT_CYAN or UI.COLORS.TEXT
        ui_draw.drawButton(lvlBtnX, toolY, btnW-2, "T"..level, lvlColor, lvlBg)
    end

    local chartY = toolY + 2
    local chartH = area.y + area.h - chartY - 2
    local chartX = area.x + 3
    local chartW = area.w - 6
    if chartH < 4 or chartW < 20 then return end

    local dataSource = UI.reportPanel.timeDimension == "hour"
        and CONFIG.REPORT.HOUR_DATA or CONFIG.REPORT.DAY_DATA
    local level = UI.reportPanel.viewLevel
    local data, times = {}, {}
    for i = 1, #dataSource do
        table.insert(data, dataSource[i].levels[level] or 0)
        table.insert(times, dataSource[i].time)
    end
    local pointCount = #data
    if pointCount < 2 then
        local tip = UI.reportPanel.timeDimension == "hour"
            and "小时数据采集中，请运行满1小时后查看"
            or "天数据采集中，请运行满1天后查看"
        ui_draw.drawText(chartX + math.floor((chartW - unicode.wlen(tip))/2),
            chartY + math.floor(chartH/2), tip, UI.COLORS.TEXT_YELLOW)
        return
    end

    local minVal = math.min(table.unpack(data))
    local maxVal = math.max(table.unpack(data))
    if minVal == maxVal then maxVal = minVal + 1 end
    local valueRange = maxVal - minVal
    local innerH = chartH - 1
    local innerY = chartY

    local points = {}
    for i = 1, pointCount do
        local x = chartX + math.floor((i - 1) / (pointCount - 1) * (chartW - 1))
        local yRatio = (data[i] - minVal) / valueRange
        local y = innerY + innerH - 1 - math.floor(yRatio * (innerH - 1))
        table.insert(points, {x=x, y=y})
    end

    UI.gpu.setBackground(UI.COLORS.BAR_FILL)
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i+1]
        UI.gpu.fill(p1.x - 1, p1.y - 1, 2, 2, " ")
        if p2.x > p1.x then UI.gpu.fill(p1.x, p1.y, p2.x - p1.x, 1, " ") end
        if p2.y ~= p1.y then
            local yMin, yMax = math.min(p1.y, p2.y), math.max(p1.y, p2.y)
            UI.gpu.fill(p2.x, yMin, 1, yMax - yMin, " ")
        end
    end
    if #points > 0 then
        local lastP = points[#points]
        UI.gpu.fill(lastP.x - 1, lastP.y - 1, 2, 2, " ")
    end
    UI.gpu.setBackground(UI.COLORS.BG)

    ui_draw.drawText(chartX, innerY, utils.formatShortNumber(maxVal), UI.COLORS.TEXT)
    ui_draw.drawText(chartX, innerY + innerH - 1, utils.formatShortNumber(minVal), UI.COLORS.TEXT)

    local xAxisY = innerY + innerH
    UI.gpu.setForeground(UI.COLORS.TEXT)
    UI.gpu.set(chartX - 1, xAxisY - 1, "└")
    for x = chartX, chartX + chartW - 1 do UI.gpu.set(x, xAxisY - 1, "─") end

    local now = computer.uptime()
    local labelCount = math.min(pointCount, 5)
    local step = math.max(1, math.floor((pointCount - 1) / (labelCount - 1)))
    for i = 1, labelCount do
        local idx = math.min(1 + (i-1) * step, pointCount)
        local timeDiff = now - times[idx]
        local label
        if UI.reportPanel.timeDimension == "hour" then
            if idx == pointCount then label = "现在"
            elseif timeDiff < 3600 then label = string.format("-%dm", math.floor(timeDiff / 60))
            else label = string.format("-%dh", math.floor(timeDiff / 3600)) end
        else
            if timeDiff < 86400 then label = string.format("-%dh", math.floor(timeDiff / 3600))
            else label = string.format("-%dd", math.floor(timeDiff / 86400)) end
        end
        local labelX = points[idx].x - math.floor(unicode.wlen(label) / 2)
        labelX = math.max(chartX, math.min(labelX, chartX + chartW - unicode.wlen(label)))
        ui_draw.drawText(labelX, xAxisY, label, UI.COLORS.TEXT)
    end
end

return ui_chart
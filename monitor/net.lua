-- net.lua
-- 无线网卡封装：广播发送（自动分片）/ 监听接收（自动重组）

local component = require("component")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG

local net = {}

local modem = nil

function net.initialize()
    local ok_list, addr = pcall(component.list, "modem")
    if ok_list and addr then addr = addr() end
    if not addr then
        return false, "[网络] 未检测到无线网卡(modem)"
    end
    modem = component.proxy(addr)
    pcall(modem.open, CONFIG.SYNC.PORT)
    if modem.isWireless and modem.isWireless() then
        pcall(modem.setStrength, modem.maxStrength and modem.maxStrength() or 400)
    end
    return true, "[网络] 无线网卡就绪，频道 " .. tostring(CONFIG.SYNC.PORT)
end

function net.getModem() return modem end
function net.isReady() return modem ~= nil end

function net.broadcast(seq, payload)
    if not modem then return false end
    local magic = CONFIG.SYNC.PROTOCOL_MAGIC
    local ver = CONFIG.SYNC.VERSION
    local fragSize = CONFIG.SYNC.FRAG_PAYLOAD
    local total = math.max(1, math.ceil(#payload / fragSize))
    for idx = 1, total do
        local chunk = payload:sub((idx - 1) * fragSize + 1, idx * fragSize)
        pcall(modem.broadcast, CONFIG.SYNC.PORT, magic, seq, idx, total, ver, chunk)
    end
    return true
end

local reassembly = {}

function net.feedMessage(magic, seq, idx, total, ver, chunk)
    if magic ~= CONFIG.SYNC.PROTOCOL_MAGIC then return nil end
    if ver ~= CONFIG.SYNC.VERSION then return nil end
    seq = tonumber(seq); idx = tonumber(idx); total = tonumber(total)
    if not (seq and idx and total) then return nil end

    local now = computer.uptime()
    local bucket = reassembly[seq]
    if not bucket or bucket.total ~= total then
        bucket = { total = total, got = {}, lastTime = now }
        reassembly[seq] = bucket
    end
    bucket.got[idx] = chunk
    bucket.lastTime = now

    if bucket.got[total] then
        local complete = true
        for i = 1, total do
            if not bucket.got[i] then complete = false; break end
        end
        if complete then
            local parts = {}
            for i = 1, total do parts[i] = bucket.got[i] end
            reassembly[seq] = nil
            return table.concat(parts)
        end
    end
    return nil
end

function net.gcReassembly()
    local now = computer.uptime()
    local timeout = CONFIG.SYNC.FRAG_TIMEOUT
    for seq, bucket in pairs(reassembly) do
        if now - bucket.lastTime > timeout then
            reassembly[seq] = nil
        end
    end
end

return net
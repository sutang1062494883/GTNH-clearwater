-- fluid.lua
-- 流体接口：TTL 缓存 + 批量预取 + 帧边界
-- 高频 getAmount 走内存缓存；业务循环每轮 prefetch 一次组件；
-- 帧内只读缓存，帧末统一失效，保证同帧视图一致。

local component = require("component")
local computer = require("computer")
local cfgModule = require("config")
local CONFIG = cfgModule.CONFIG
local CONST = cfgModule.CONST

local fluid = {}

local fluidInterface = nil
local cache = {}        -- [cleanName] = { value, time }
local inFrame = false

local function normalize(name)
    local raw = name
    if not raw:find(":") then raw = "gregtech:" .. raw end
    local clean = raw:lower():match(":(.+)$") or raw:lower()
    return clean, raw
end

function fluid.initialize()
    local ok_list, addr = pcall(component.list, "fluid_interface")
    if ok_list and addr then addr = addr() end
    if addr then
        fluidInterface = component.proxy(addr)
        return true, "[系统] 成功连接流体接口"
    else
        fluidInterface = nil
        return false, "[警告] 未找到流体接口，流体读取功能不可用(将使用缓存值)"
    end
end

function fluid.getProxy() return fluidInterface end

function fluid.putCache(fluidName, value)
    local clean = normalize(fluidName)
    cache[clean] = { value = math.max(0, tonumber(value) or 0), time = computer.uptime() }
end

function fluid.prefetch(levels)
    if not fluidInterface then return end
    levels = levels or {1,2,3,4,5,6,7,8}
    local wanted = {}
    for _, lv in ipairs(levels) do
        local cfg = CONFIG.CACHED_CONFIG and CONFIG.CACHED_CONFIG[lv]
        local name = cfg and (cfg.fluidId or CONST.FLUID_NAMES[lv]) or CONST.FLUID_NAMES[lv]
        local _, raw = normalize(name)
        wanted[raw] = true
        wanted[name] = true
    end

    local now = computer.uptime()
    local filled = false
    local ok2, allFluids = pcall(fluidInterface.getFluidsInNetwork)
    if ok2 and type(allFluids) == "table" then
        for _, f in ipairs(allFluids) do
            local fname = f.name
            if fname and wanted[fname] then
                local clean = normalize(fname)
                cache[clean] = { value = math.max(0, tonumber(f.size or f.amount or 0) or 0), time = now }
                filled = true
            end
        end
    end

    if not filled then
        for _, lv in ipairs(levels) do
            local cfg = CONFIG.CACHED_CONFIG and CONFIG.CACHED_CONFIG[lv]
            local name = cfg and (cfg.fluidId or CONST.FLUID_NAMES[lv]) or CONST.FLUID_NAMES[lv]
            local clean, raw = normalize(name)
            local c = cache[clean]
            if not c or (now - c.time) >= (CONFIG.FLUID_CACHE.TTL or 1.0) then
                local okd, detail = pcall(fluidInterface.getFluidInNetwork, raw)
                if okd and detail and type(detail) == "table" then
                    cache[clean] = { value = math.max(0, tonumber(detail.size or detail.amount or 0) or 0), time = now }
                end
            end
        end
    end
end

function fluid.beginFrame() inFrame = true end
function fluid.endFrame()
    inFrame = false
    local now = computer.uptime()
    local ttl = (CONFIG.FLUID_CACHE and CONFIG.FLUID_CACHE.TTL) or 1.0
    for k, v in pairs(cache) do
        if now - v.time > ttl * 30 then cache[k] = nil end   -- 30 倍 TTL 才彻底丢弃
    end
end
function fluid.getAmount(fluidName)
    local clean = normalize(fluidName)
    local now = computer.uptime()
    local ttl = (CONFIG.FLUID_CACHE and CONFIG.FLUID_CACHE.TTL) or 1.0
    local c = cache[clean]

    if c and (now - c.time) < ttl then
        return c.value
    end
    -- 帧内：有旧缓存就用旧缓存；完全没缓存时允许查一次组件（避免首帧/清缓存后闪 0）
    if inFrame then
        if c then return c.value end
        -- 落到下面：无缓存则查组件（仅这一种例外）
    end
    if not fluidInterface then
        return c and c.value or 0
    end

    local _, raw = normalize(fluidName)
    local okd, detail = pcall(fluidInterface.getFluidInNetwork, raw)
    if okd and detail and type(detail) == "table" then
        local val = math.max(0, tonumber(detail.size or detail.amount or 0) or 0)
        cache[clean] = { value = val, time = now }
        return val
    end
    return c and c.value or 0
end

function fluid.dumpCache()
    local t = {}
    for k, v in pairs(cache) do t[k] = v.value end
    return t
end

return fluid
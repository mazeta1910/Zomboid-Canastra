-- Emulates Project Zomboid's require() over media/lua/{shared,client,server}.
LUA_DIRS = LUA_DIRS or { SHARED_DIR }
MOCK_MODULES = MOCK_MODULES or {}

local loaded = {}
function require(name)
    if loaded[name] ~= nil then return loaded[name] end
    if MOCK_MODULES[name] then
        loaded[name] = true
        return true
    end
    for _, dir in ipairs(LUA_DIRS) do
        local path = dir .. "/" .. name .. ".lua"
        local f = io.open(path, "r")
        if f then
            f:close()
            local chunk, err = loadfile(path)
            if not chunk then error(err) end
            loaded[name] = true
            local r = chunk()
            if r ~= nil then loaded[name] = r end
            return loaded[name]
        end
    end
    error("module not found: " .. name)
end

math.randomseed(12345)

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    io.write(table.concat(parts, "\t"), "\n")
    io.flush()
end

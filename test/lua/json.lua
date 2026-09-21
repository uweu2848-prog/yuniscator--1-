-- Minimal JSON encode/decode for the test harness (stands in for HttpService:JSONEncode/JSONDecode).
local json = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function esc(s)
    return (s:gsub('[%c"\\]', function(c) return escapes[c] or string.format('\\u%04x', c:byte()) end))
end

function json.encode(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return tostring(v)
    elseif t == "string" then return '"' .. esc(v) .. '"'
    elseif t == "table" then
        if #v > 0 or next(v) == nil then
            local out = {}
            for i, x in ipairs(v) do out[i] = json.encode(x) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local out = {}
        for k, x in pairs(v) do out[#out + 1] = '"' .. esc(tostring(k)) .. '":' .. json.encode(x) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    error("cannot encode " .. t)
end

function json.decode(s)
    local pos = 1
    local function skip() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
    local value
    local function str()
        local out, i = {}, pos + 1
        while true do
            local c = s:sub(i, i)
            if c == '"' then pos = i + 1 return table.concat(out) end
            if c == "" then error("unterminated string") end
            if c == "\\" then
                local n = s:sub(i + 1, i + 1)
                local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if n == "u" then
                    local cp = tonumber(s:sub(i + 2, i + 5), 16)
                    out[#out + 1] = utf8.char(cp)
                    i = i + 6
                else
                    out[#out + 1] = map[n] or n
                    i = i + 2
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
    end
    function value()
        skip()
        local c = s:sub(pos, pos)
        if c == "{" then
            local obj = {}
            pos = pos + 1 skip()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return obj end
            while true do
                skip()
                local k = str()
                skip() pos = pos + 1 -- ':'
                obj[k] = value()
                skip()
                local d = s:sub(pos, pos) pos = pos + 1
                if d == "}" then return obj end
            end
        elseif c == "[" then
            local arr = {}
            pos = pos + 1 skip()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = value()
                skip()
                local d = s:sub(pos, pos) pos = pos + 1
                if d == "]" then return arr end
            end
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            if not num or num == "" then error("bad json at " .. pos) end
            pos = pos + #num
            return tonumber(num)
        end
    end
    return value()
end

return json

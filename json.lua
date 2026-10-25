-- json.lua: minimal JSON decoder (objects, arrays, strings, numbers, booleans, null)
local json = {}

local escapes = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function skip(s, i)
    return s:find("[^ \t\r\n]", i) or #s + 1
end

local parseValue

local function parseString(s, i)
    local out = {}
    i = i + 1
    while true do
        local c = s:sub(i, i)
        if c == "" then error("unterminated string") end
        if c == '"' then return table.concat(out), i + 1 end
        if c == "\\" then
            local n = s:sub(i + 1, i + 1)
            if n == "u" then
                out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16))
                i = i + 6
            elseif escapes[n] then
                out[#out + 1] = escapes[n]
                i = i + 2
            else
                error("bad escape at " .. i)
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

function parseValue(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        local obj = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            i = skip(s, i)
            local key
            key, i = parseString(s, i)
            i = skip(s, i)
            if s:sub(i, i) ~= ":" then error("expected ':' at " .. i) end
            obj[key], i = parseValue(s, i + 1)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "}" then return obj, i + 1 end
            if d ~= "," then error("expected ',' or '}' at " .. i) end
            i = i + 1
        end
    elseif c == "[" then
        local arr = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            arr[#arr + 1], i = parseValue(s, i)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "]" then return arr, i + 1 end
            if d ~= "," then error("expected ',' or ']' at " .. i) end
            i = i + 1
        end
    elseif c == '"' then
        return parseString(s, i)
    elseif s:sub(i, i + 3) == "true" then return true, i + 4
    elseif s:sub(i, i + 4) == "false" then return false, i + 5
    elseif s:sub(i, i + 3) == "null" then return nil, i + 4
    end
    local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
    if not num or num == "" then error("unexpected character at " .. i) end
    return tonumber(num), i + #num
end

function json.decode(s)
    local v = parseValue(s, 1)
    return v
end

return json

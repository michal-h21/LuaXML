local M = {}
local char = unicode and unicode.utf8.char or utf8.char
local named_entities = require "luaxml-namedentities"
local hexchartable = {}
local decchartable = {}


local function get_named_entity(name)
  return named_entities[name]
end

function M.decode(s)
  return s:gsub("&([#a-zA-Z0-9]+);?", function(m)
    -- check if this is named entity first
    local named = get_named_entity(m)
    if named then return named end
    -- check if it is numeric entity
    local hex, charcode = m:match("#([xX]?)([a-fA-F0-9]+)")
    -- if the entity is not numeric
    if not charcode then return 
      "&" .. m .. ";" 
    end
    local character 
    if hex~="" then
      character = hexchartable[charcode] or char(tonumber(charcode,16))
      hexchartable[charcode] = character
    else
      character = decchartable[charcode] or char(tonumber(charcode))
      decchartable[charcode] = character
    end
    return character
  end)
end

return M



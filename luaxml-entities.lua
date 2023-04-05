local M = {}
local char = unicode and unicode.utf8.char or utf8.char
local named_entities
if kpse then
  named_entities = require "luaxml-namedentities"
else
  named_entities = require "luaxml.namedentities"
end
local hexchartable = {}
local decchartable = {}


local function get_named_entity(name)
  return named_entities[name]
end

local function test_invalid_unicode(charnumber)
  return charnumber > 127 and charnumber < 256
end

local function get_entity(charcode, chartable, base)
  local character = chartable[charcode] 
  if not character then
    local charnumber = tonumber(charcode,base)
    -- if test_invalid_unicode(charnumber) then
      -- return nil
    -- end
    character = char(charnumber)
    chartable[charcode] = character
  end
  return character
end


function M.decode(s)
  return s:gsub("&([#a-zA-Z0-9%_%:%-]-);", function(m)
    -- check if this is named entity first
    local named = get_named_entity(m)
    local original_entity = "&" .. m .. ";"
    if named then return named end
    -- check if it is numeric entity
    local hex, charcode = m:match("#([xX]?)([a-fA-F0-9]+)")
    -- if the entity is not numeric
    if not charcode then return 
      original_entity
    end
    local character 
    if hex~="" then
      character = get_entity(charcode, hexchartable, 16) or original_entity
    else
      character = get_entity(charcode, decchartable, 10)
    end
    return character
  end)
end

return M



-- convert json file with html named entities to Lua table
-- json source: https://html.spec.whatwg.org/entities.json
local json = require "dkjson"
local data = io.read("*all")

local function sorted(json_data)
  -- we need to sort entity names alphabetically to get good order each time we run this script (for git)
  local t = {}
  for k in pairs(json_data) do
    table.insert(t, k)
  end
  table.sort(t)
  return t
end

local json_data = json.decode(data)
print("return {")
for _, name in ipairs(sorted(json_data)) do
  local rec = json_data[name]
  print(string.format('["%s"]="%s",',name:gsub("[&;]", ""), rec.characters:gsub('\\', '\\\\'):gsub("\n", '\\n'):gsub('"', '\\"')))
end

print "}"

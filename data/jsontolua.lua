-- convert json file with html named entities to Lua table
-- json source: https://html.spec.whatwg.org/entities.json
local json = require "dkjson"
local data = io.read("*all")

local json_data = json.decode(data)
print("return {")
for name, rec in pairs(json_data) do
  print(string.format('["%s"]="%s",',name:gsub("[&;]", ""), rec.characters:gsub('\\', '\\\\'):gsub("\n", '\\n'):gsub('"', '\\"')))
end

print "}"

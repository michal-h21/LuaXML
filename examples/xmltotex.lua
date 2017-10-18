local cssobj = require "luaxml-cssquery"
local domobj = require "luaxml-domobject"

local xml = [[
<html>
<body>
<h1>Header</h1>
<p>First paragraph</p>
<p>Second <i>paragraph</i></p>
</body>
</html>
]]

local dom = domobj.parse(xml)
local css = cssobj()

local function applytex(obj, parameters)
  local function add_parameter(name)
    local t = obj[name] or {}
    table.insert(t, parameters[name])
    print("applying", name, parameters[name])
    obj[name] = t
  end
  add_parameter("pre")
  add_parameter("add")
end

css:add_selector("p", applytex, {pre = "", add = "\n\n"})
css:add_selector("h1", applytex, {pre = "\\section{", add = "}"})
css:add_selector("i", applytex, {pre = "\\textit{", add = "}"})

dom:traverse_elements(function(el)
  local querylist = css:match_querylist(el)
  css:apply_querylist(el,querylist)
end)

local function serialize_tex(el)
  local t = {}

  if el:is_element() then
    local pre = el.pre or {}
    for _, x in ipairs(pre) do
      table.insert(t,x)
    end
    for _, x in ipairs(el:get_children()) do
      table.insert(t, serialize_tex(x))
    end
    local add = el.add or {}
    for i= #add, 1, -1 do
      table.insert(t,add[i])
    end
  else
    table.insert(t, el:get_text())
  end
  return table.concat(t)
end

print(serialize_tex(dom:root_node()))

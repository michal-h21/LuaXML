local cssobj = require "luaxml-cssquery"
local domobj = require "luaxml-domobject"
local lpeg   = require "lpeg"

local xml = [[
<html>
<body>
<h1>Header</h1>
<p>First paragraph&amp; some\\ bad characters</p>
<p>Second <i>paragraph</i></p>
</body>
</html>
]]

local dom = domobj.parse(xml)
local css = cssobj()

-- local function applytex(obj, parameters)
--   local function add_parameter(name)
--     local t = obj[name] or {}
--     table.insert(t, parameters[name])
--     print("applying", name, parameters[name])
--     obj[name] = t
--   end
--   add_parameter("pre")
--   add_parameter("add")
-- end

local tex_escape = function(s)
  local codes = {["&"] = "\\&{}", ["\\"] = "\\textbackslash{}"}
  return s:gsub("([&\\])", function(a) return codes[a] end)
end

local identity_escape = function(s) return s end

local collapsed_ws = function(s)
  return s:gsub("(%s%s+)", function(a) return a:sub(1,1) end)
end

local function add_template(selector, template)
  css:add_selector(selector, function(obj, parameters) 
    local t = obj.template or {}
    t[#t+1] = parameters.template
    obj.template = t
  end, {template=template})
end


---
local function apply_template(template, content, element)
  return template:gsub("<.>", content)
end

add_template("p", "<.>\n\n")
add_template("h1", "\\section{<.>}")
add_template("i", "\\textit{<.>}")
-- css:add_selector("p", applytex, {pre = "", add = "\n\n"})
-- css:add_selector("h1", applytex, {pre = "\\section{", add = "}"})
-- css:add_selector("i", applytex, {pre = "\\textit{", add = "}"})

dom:traverse_elements(function(el)
  local querylist = css:match_querylist(el)
  css:apply_querylist(el,querylist)
end)

local function serialize_tex(el)
  local t = {}

  print(el:is_element(), el:is_element(el), el:get_node_type())
  if el:is_text() then
    local text = tex_escape(el._text)
    table.insert(t, text)
  else
    -- print(el.pre)
    -- local pre = el.pre or {}
    -- for _, x in ipairs(pre) do
      -- table.insert(t,x)
    -- end
    local current_nodes = {}
    for _, x in ipairs(el:get_children()) do
      -- we need to give special handling to text nodes, because we may want
      -- them escaped, verbatim, or with preserved whitespace
      local current = {}
      if x:is_text() then
        current.type = "text"
        local text = x._text
        local escaped = tex_escape(text)
        current.verbatim = text
        current.collapsed = collapsed_ws(escaped) -- this is used by default,
        -- with escaped special sequences and collapsed whitescpace
        current.escaped = escaped
      else
        current.type = "node"
        current.content = serialize_tex(x)
      end
      table.insert(current_nodes, current)
    end
    local escapes = {default = tex_escape, identity = identity_escape}
    -- local content = table.concat(h)
    local templates = el.template or {}
    local content = {}
    for _, v in ipairs(current_nodes) do
      local text = v.content or v.collapsed
      content[#content+1] = text
    end
    content = table.concat(content)

    for _, template in ipairs(templates) do
      content = apply_template(template, content, el )
    end
    table.insert(t, content)
    -- local add = el.add or {}
    -- for i= #add, 1, -1 do
      -- table.insert(t,add[i])
  end
  return table.concat(t)
end

print(serialize_tex(dom:root_node()))

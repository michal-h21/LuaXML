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

-- escape special LaTeX characters. More should be added
local tex_escape = function(s)
  local codes = {["&"] = "\\&{}", ["\\"] = "\\textbackslash{}"}
  return s:gsub("([&\\])", function(a) return codes[a] end)
end

local identity_escape = function(s) return s end

local collapsed_ws = function(s)
  return s:gsub("(%s%s+)", function(a) return a:sub(1,1) end)
end

--- Declare new template. 
-- template should contain <.> placeholder, which will be replaced
-- by content of the matched element
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

-- we must escape \ characters in macro names
add_template("p", "<.>\n\n")
add_template("h1", "\\section{<.>}")
add_template("i", "\\textit{<.>}")
-- css:add_selector("p", applytex, {pre = "", add = "\n\n"})
-- css:add_selector("h1", applytex, {pre = "\\section{", add = "}"})
-- css:add_selector("i", applytex, {pre = "\\textit{", add = "}"})

-- traverse all elements and add templates to them
dom:traverse_elements(function(el)
  -- find selectors that match the current element
  local querylist = css:match_querylist(el)
  -- add templates to the element
  css:apply_querylist(el,querylist)
end)

local function serialize_tex(el)
  local t = {}

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
    -- local content = table.concat(h)
    local templates = el.template or {}
    local content = {}
    -- only escaped and collapsed text is added at the moment.
    -- it would be nice to add support for verbatim elements, where 
    -- unescaped text could be added, but it is not here yet
    for _, v in ipairs(current_nodes) do
      -- content comes from elements, collapsed is escaped text content
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

-- process the document from the root node, get TeX code from 
-- the templates
print(serialize_tex(dom:root_node()))

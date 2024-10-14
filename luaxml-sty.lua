-- provide global object with all variables we will use
luaxml_sty = {
  current = {
    transformation = "default",
  },
  packages = {},
  -- we want to support multiple transformation objects, they will be stored here
  transformations = {},
}
luaxml_sty.packages.transform = require "luaxml-transform"
luaxml_sty.packages.domobject = require "luaxml-domobject"

-- declare default transformer, used if no explicit transformer is used in LuaXML LaTeX commands
luaxml_sty.transformations.default = luaxml_sty.packages.transform.new()

-- debuggind functions
function luaxml_sty.error(...)
  local arg = {...}
  print("LuaXML error: " .. table.concat(arg, " "))
end

function luaxml_sty.debug(...)
  local arg = {...}
  print("LuaXML: " .. table.concat(arg, " "))
end

-- add luaxml-transform rule
function luaxml_sty.add_rule(current, selector, rule)
  if current == "" then
   current = luaxml_sty.current.transformation
  end
  -- the +v parameter type in LaTeX replaces newlines with \obeyedline. we need to replace it back to newlines
  rule = rule:gsub("\\obeyedline", "\n")
  luaxml_sty.debug("************* luaxml_sty rule: " .. selector, rule, current)
  local transform = luaxml_sty.transformations[current]
  if not transform then
    luaxml_sty.error("Cannot find LuaXML transform object: " .. (current or ""))
    return nil, "Cannot find LuaXML transform object: " .. (current or "")
  end
  transform:add_action(selector, rule)
end

-- by default, we will use XML parser, so use_xml is set to true
luaxml_sty.use_xml = true

function luaxml_sty.use_xml()
  luaxml_sty.use_xml = true
end


function luaxml_sty.use_html()
  luaxml_sty.use_xml = false
end

--- transform XML string
function luaxml_sty.parse_snippet(current, xml_string)
  local domobject = luaxml_sty.packages.domobject
  if current == "" then
    current = luaxml_sty.current.transformation
  end
  local transform = luaxml_sty.transformations[current]
  local dom
  if luaxml_sty.use_xml then
    dom = domobject.parse(xml_string)
  else
    dom = domobject.html_parse(xml_string)
  end
  print(dom:serialize())
  local result = transform:process_dom(dom)
  luaxml_sty.packages.transform.print_tex(result)
end

function luaxml_sty.parse_file(current, filename)
  local f = io.open(filename, "r")
  if not f then
    luaxml_sty.packages.transform.print_tex("\\textbf{LuaXML error}: cannot find file " .. filename)
    return nil, "Cannot find file " .. filename
  end
  local content = f:read("*a")
  f:close()
  luaxml_sty.parse_snippet(current, content)
end

return luaxml_sty

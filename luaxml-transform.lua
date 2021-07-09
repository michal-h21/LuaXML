--- XML transformation module for LuaXML
-- @module luaxml-tranform
-- @author Michal Hoftich <michal.h21@gmail.com

-- code originaly comes from from https://github.com/michal-h21/luaxml-mathml
--
local domobject = require "luaxml-domobject"
local cssquery = require "luaxml-cssquery"
-- initialize CSS selector object
local css = cssquery()


-- convert Unicode characters to TeX sequences
local unicodes = {
  [35] = "\\#",
  [36] = "\\$",
  [37] = "\\%",
  [38] = "\\&",
  [60] = "\\textless{}",
  [62] = "\\textgreater{}",
  [92] = "\\textbackslash{}",
  [94] = "\\^",
  [95] = "\\_",
  [123] = "\\{",
  [125] = "\\}"
}

local function match_css(element,csspar)
  local css = csspar or css
  local selectors = css:match_querylist(element)
  if #selectors == 0 then return nil end
  -- return function with the highest specificity
  return selectors[1].func
end


local function process_text(text, parameters)
  local parameters = parameters or {}
  -- spaces are collapsed by default. set verbatim=true to disable it.
  local verbatim = parameters.verbatim
  local t = {}
  -- process all Unicode characters and find if they should be replaced
  for _, char in utf8.codes(text) do
    -- construct new string with replacements or original char
    t[#t+1] = unicodes[char] or utf8.char(char)
  end
  local text = table.concat(t)
  if not verbatim then
    text = text:gsub("(%s%s+)", function(a) return a:sub(1,1) end)
  end
  return text
end

-- this function is initialized later, I need the declaration here
-- to prevent Lua run-time error
local process_tree


local function process_children(element, parameters)
  -- accumulate text from children elements
  local t = {}
  -- sometimes we may get text node
  if type(element) ~= "table" then return element end
  for i, elem in ipairs(element:get_children()) do
    if elem:is_text() then
      -- concat text
      t[#t+1] = process_text(elem:get_text(), parameters)
    elseif elem:is_element() then
      -- recursivelly process child elements
      t[#t+1] = process_tree(elem)
    end
  end
  return table.concat(t)
end

-- we need to define different actions for XML elements. The default action is
-- to just process child elements and return the result
local function default_action(element)
  return process_children(element)
end

function process_tree(element)
  -- find specific action for the element, or use the default action
  local element_name = element:get_element_name()
  local action = match_css(element) or default_action
  return action(element)
end


-- use template string to place the processed children
local function simple_content(s,parameters)
  return function(element)
    local content = process_children(element,parameters)
    -- process attrubutes
    -- attribute should be marked as @{name}
    local expanded = s:gsub("@{(.-)}", function(name)
      return process_text(element:get_attribute(name) or "")
    end)
    -- 
    return expanded:gsub("%%s", function(a) return content end)
  end
end



local function get_child_element(element, count)
  -- return specified child element 
  local i = 0
  for _, el in ipairs(element:get_children()) do
    -- count elements 
    if el:is_element() then
      -- return the desired numbered element
      i = i + 1
      if i == count then return el end
    end
  end
end

-- actions for particular elements
local actions = {
  
}

--- Use function to transform selected element
-- @param selector CSS selector for the matching element
-- @param fn Function that transforms the selected DOM element.
-- @param csspar cssquery object. Default is set by the library, so it is not necessary to use.
local function add_custom_action(selector, fn, csspar)
  local css = csspar or css
  css:add_selector(selector,fn)
end

--- Use template to transform selected template
-- @param selector CSS selector for the matching element
-- @param template String template
-- @param parameters Table with extra parameters. Use "verbatim=true" to keep spacing in the processed text.
-- @param csspar cssquery object. Default is set by the library, so it is not necessary to use.
local function add_action(selector, template, parameters, csspar)
  local css = csspar or css
  css:add_selector(selector, simple_content(template, parameters))
end




--- Transform XML string
-- @param content String with XML content
-- @return transformed string
local function parse_xml(content)
  -- parse XML string and process it
  local dom = domobject.parse(content)
  -- start processing of DOM from the root element
  -- return string with TeX content
  return process_tree(dom:root_node())
end


--- Transform XML file
-- @param filename XML file name
-- @return transformed string
local function load_file(filename)
  local f = io.open(filename, "r")
  local content = f:read("*all")
  f:close()
  return parse_xml(content)
end

--- Transform XML DOM object 
-- @param dom DOM object
-- @return transformed string
local function process_dom(dom)
  return process_tree(dom:root_node())
end

--- print transformed file to PDF using LuaTeX functions
-- @param content String to be printed 
local function print_tex(content)
  -- we need to replace "\n" characters with calls to tex.sprint
  for s in content:gmatch("([^\n]*)") do
    tex.sprint(s)
  end
end

--- return nth child element
-- @param element DOM element to be processed
-- @param count Number of child element that should be returned
-- @return DOM object, or nil if it cannot be found
local function get_child_element(element, count)
  -- return specified child element 
  local i = 0
  for _, el in ipairs(element:get_children()) do
    -- count elements 
    if el:is_element() then
      -- return the desired numbered element
      i = i + 1
      if i == count then return el end
    end
  end
end

-- make Transformer objec
local Transformer 

--- Make new Transformer object
-- @return Tranformer object
local function new()
  local self = setmetatable({}, Transformer)
  self.css = cssquery()
  -- use the default unicodes table that escapes special LaTeX characters
  self.unicodes = unicodes
  return self
end

---  @type Transformer
Transformer = {}
Transformer.__index = Transformer
-- the library uses shared css variable. in order to support multiple transformers,
-- we need to save the original state, set the self.css variable as the global variable
-- execute library function and then set the original function back
--
function Transformer:save_css()
  self.old_css = css
  css = self.css
  --  we must also save unicodes table
  self.old_unicodes = unicodes
  unicodes = self.unicodes
end

function Transformer:restore_css()
  css = self.old_css
  unicodes = self.old_unicodes
end

--- add a new template
-- @param selector CSS selector that should be matched
-- @param template use %s for element's text, and @name to access attribute "name"
-- @param parameters table with extra parameters
function Transformer:add_action(selector, template, parameters )
  add_action(selector, template, parameters, self.css)
end

function Transformer:add_custom_action(selector, fn )
  add_custom_action(selector, fn, self.css)
end

-- all methods that use transformation functions must 
-- correctly handle the cssquery object that this library uses
function Transformer:parse_xml(content)
  self:save_css()
  local result = parse_xml(content)
  self:restore_css()
  return result
end

-- make method for load_file function
function Transformer:load_file(filename)
  self:save_css()
  local result = load_file(filename)
  self:restore_css()
  return result
end

-- make method for process_dom function
function Transformer:process_dom(dom)
  self:save_css()
  local result = process_dom(dom)
  self:restore_css()
  return result
end
  

--- @export
local M = {
  parse_xml = parse_xml,
  process_children = process_children,
  get_child_element= get_child_element,
  print_tex = print_tex,
  add_action = add_action,
  add_custom_action = add_custom_action,
  simple_content = simple_content,
  load_file = load_file,
  process_dom = process_dom,
  new = new
}


return M

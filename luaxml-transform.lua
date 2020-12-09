-- adapted code from https://github.com/michal-h21/luaxml-mathml
--
local domobject = require "luaxml-domobject"
local cssquery = require "luaxml-cssquery"
-- initialize CSS selector object
local css = cssquery()

-- we need to define different actions for XML elements. The default action is
-- to just process child elements and return the result
local function default_action(element)
  return process_children(element)
end

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

-- add more complicated action
local function add_custom_action(selector, fn)
  css:add_selector(selector,fn)
end

-- normal actions
local function add_action(selector, template, parameters)
  css:add_selector(selector, simple_content(template, parameters))
end


function process_children(element, parameters)
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

local function match_css(element)
  local selectors = css:match_querylist(element)
  if #selectors == 0 then return nil end
  -- return function with the highest specificity
  return selectors[1].func
end

function process_tree(element)
  -- find specific action for the element, or use the default action
  local element_name = element:get_element_name()
  local action = match_css(element) or default_action
  return action(element)
end

function parse_xml(content)
  -- parse XML string and process it
  local dom = domobject.parse(content)
  -- start processing of DOM from the root element
  -- return string with TeX content
  return process_tree(dom:root_node())
end


local function load_file(filename)
  local f = io.open(filename, "r")
  local content = f:read("*all")
  f:close()
  return parse_xml(content)
end

function process_dom(dom)
  return process_tree(dom:root_node())
end


function print_tex(content)
  -- we need to replace "\n" characters with calls to tex.sprint
  for s in content:gmatch("([^\n]*)") do
    tex.sprint(s)
  end
end


local M = {
  parse_xml = parse_xml,
  process_children = process_children,
  print_tex = print_tex,
  add_action = add_action,
  add_custom_action = add_custom_action,
  simple_content = simple_content,
  load_file = load_file,
  process_dom = process_dom
}


return M

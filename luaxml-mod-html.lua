-- HTML parser
-- inspired by https://browser.engineering/html.html
local M = {}

-- declare  basic node types

local Root = {
  _type = "root"
}

function Root:init()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.__tostring = function (x) return "_ROOT" end
  o.children = {}
  return o
end

function Root:add_child(node)
  table.insert(self.children, node)
end

local Doctype = {
  _type = "doctype"
}
function Doctype:init(text, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.__tostring = function (x) return "<" .. x.text .. ">" end
  self.add_child = Root.add_child
  o.parent = parent
  o.text = table.concat(text)
  o.children = {}
  return o
end


local Text = {
  _type = "text"
}

function Text:init(text, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.text = text
  self.__tostring = function (x) return "'" ..  x.text .. "'" end
  self.add_child = Root.add_child
  o.parent = parent
  o.children = {}
  return o
end



local Element = {
  _type = "element"
}

function Element:init(tag, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  -- tag can be table with unicode characters
  if type(tag) == "table" then
    o.tag = table.concat(tag)
  else
    o.tag = tag
  end
  self.__tostring = function(x) return  "<" .. x.tag .. ">" end
  self.add_child = Root.add_child
  o.children = {}
  o.parent = parent
  return o
end



local HtmlParser = {}

function HtmlParser:init(body)
  local o ={}
  setmetatable(o, self)
  self.__index = self
  o.body = self:normalize_newlines(body) -- HTML string
  o.position = 0 -- position in the parsed string
  -- self.root = Element:init("", {})
  o.unfinished = {Root:init()}
  return o
end

function HtmlParser:normalize_newlines(body)
  -- we must normalize newlines
  return body:gsub("\r\n", "\n"):gsub("\r", "\n")
end

-- use local copies of utf8 functions
local ucodepoint = utf8.codepoint
local uchar      = utf8.char

-- declare void elements
local self_closing_tags_list = {"area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"}
 
local self_closing_tags = {}
for _,v in ipairs(self_closing_tags_list) do self_closing_tags[v] = true end


function HtmlParser:parse()
  -- 
  local out = {}
  local text = {}
  local in_tag = false
  local start_tag = ucodepoint("<")
  local end_tag   = ucodepoint(">")
  for pos, ucode in utf8.codes(self.body) do
    self.position = pos
    if ucode == start_tag then
      in_tag = true
      if #text > 0 then self:add_text(text) end
      text = {}
    elseif ucode == end_tag then
      in_tag = false
      self:add_tag(text)
      text = {}
    else
      text[#text+1] = uchar(ucode)
    end
  end
  if not in_tag and #text > 0 then self:add_text(text) end
  return self:finish()
end

function HtmlParser:get_parent()
  -- return parent element
  return self.unfinished[#self.unfinished]
end

function HtmlParser:close_element()
  -- return parent element and remove it from the unfinished list
  return table.remove(self.unfinished)
end

function HtmlParser:add_text(text)
  local text = table.concat(text)
  local parent = self:get_parent()
  local node = Text:init(text, parent)
  parent:add_child(node)
end

function HtmlParser:get_tag(text)
  local tag = {}
  for _, x in ipairs(text) do 
    if x~=" " then
      tag[#tag+1] = x
    else
      break
    end
  end
  return table.concat(tag)
end

function HtmlParser:add_tag(text)
  -- main function for handling various tag types
  local tag = self:get_tag(text)
  local first_char = text[1] 
  if first_char == "/" then
    if #self.unfinished==1 then return nil end
    local node = self:close_element()
    local parent = self:get_parent()
    parent:add_child(node)
  elseif first_char == "!" then
    local parent = self:get_parent()
    local node = Doctype:init(text)
    parent:add_child(node)
  elseif text[#text] == "/" then
    -- self closing tag
    local parent = self:get_parent()
    local node = Element:init(text, parent)
    parent:add_child(node)
  elseif self_closing_tags[tag] then
    -- self closing tag
    local parent = self:get_parent()
    local node = Element:init(text, parent)
    parent:add_child(node)
  else
    local parent = self:get_parent()
    local node = Element:init(text, parent)
    table.insert(self.unfinished, node)
  end
end

function HtmlParser:finish()
  -- close all unclosed elements
  if #self.unfinished == 0 then
    -- add implicit html tag
    self:add_tag("html")
  end
  while #self.unfinished > 1 do
    local node = self:close_element()
    local parent = self:get_parent()
    parent:add_child(node)
  end
  -- return root element
  return self:close_element()
end

-- debugging function
local function print_tree(node, indent)
  local indent = indent or 0
  print(string.rep(" ",indent*2) .. tostring(node))
  for _, child in ipairs(node.children) do
    print_tree(child, indent + 1)
  end
end



local p = HtmlParser:init("  <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage</h1><img src='hello' />")
local dom = p:parse()
print_tree(dom)



-- 
M.Text       = Text
M.Element    = Element
M.HtmlParser = HtmlParser
M.self_closing_tags = self_closing_tags
return M 

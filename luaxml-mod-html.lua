-- HTML parser
-- inspired by https://browser.engineering/html.html
local M = {}

local Text = {}

function Text:init(text, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.text = text
  o.parent = parent
  o.children = {}
  return o
end

local Element = {}

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
  o.children = {}
  o.parent = parent
  return o
end


local HtmlParser = {}

function HtmlParser:init(body)
  local o ={}
  setmetatable(o, self)
  self.__index = self
  o.body = body
  -- self.root = Element:init("", {})
  o.unfinished = {}
  return o
end

-- use local copies of utf8 functions
local ucodepoint = utf8.codepoint
local uchar      = utf8.char

function HtmlParser:parse()
  -- 
  local out = {}
  local text = {}
  local in_tag = false
  local start_tag = ucodepoint("<")
  local end_tag   = ucodepoint(">")
  for pos, ucode in utf8.codes(self.body) do
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

function HtmlParser:add_text(text)
  local text = table.concat(text)
  local parent = self.unfinished[#self.unfinished]
  local node = Text:init(text, parent)
  table.insert(parent.children, node)
  print("text", text)
end

function HtmlParser:add_tag(text)
  if text[1] == "/" then
    if #self.unfinished==1 then return nil end
    local node = table.remove(self.unfinished)
    print("finishing", node.tag)
    local parent = self.unfinished[#self.unfinished]
    table.insert(parent.children, node)
  else
    local parent = self.unfinished[#self.unfinished] 
    -- local text = table.concat(text)
    local node = Element:init(text, parent)
    print("opening", node.tag)
    table.insert(self.unfinished, node)
  end
end

function HtmlParser:finish()
  if #self.unfinished == 0 then
    self:add_tag("html")
  end
  while #self.unfinished > 1 do
    local node = table.remove(self.unfinished)
    local parent = self.unfinished[#self.unfinished]
    print("finishing", node.tag, parent.tag)
    table.insert(parent.children, node)
  end
  print("root", self.unfinished[1].tag)
  return table.remove(self.unfinished)
end


function dump(o, count)
  local count = count or 0
  if type(o) == 'table' then
    local s = "\n" .. string.rep("  ", count) .. "{\n"
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. string.rep("  ", count) .. '['..k..'] = ' .. dump(v, count + 1) .. ',\n'
    end
    return s .. "\n" .. string.rep("  ", count) .. "}"
  else
    return tostring(o)
  end
end


local p = HtmlParser:init("<html><head></head><body><h1>This is my webpage")
local dom = p:parse()
-- print(dump(dom))



-- 
M.Text       = Text
M.Element    = Element
M.HtmlParser = HtmlParser
return M

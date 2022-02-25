-- HTML parser
-- inspired by https://browser.engineering/html.html
local M = {}

-- use local copies of utf8 functions
local ucodepoint = utf8.codepoint
local uchar      = utf8.char

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



-- state machine functions

-- each function takes HtmlParser as an argument
local HtmlStates = {}

-- declare codepoints for more efficient processing
local less_than      = ucodepoint("<")
local greater_than   = ucodepoint(">")
local amperesand     = ucodepoint("&")
local exclam         = ucodepoint("!")
local question       = ucodepoint("?")
local solidus        = ucodepoint("/")
local equals         = ucodepoint("=")
local quoting        = ucodepoint('"')
local apostrophe     = ucodepoint("'")

local function is_upper_alpha(codepoint)
  if (64 < codepoint and codepoint < 91) then
    return true
  end
end
local function is_lower_alpha(codepoint)
  if (96 < codepoint and codepoint < 123) then 
    return true
  end
end

local function is_alpha(codepoint)
  -- detect if codepoint is alphanumeric
  if is_upper_alpha(codepoint) or
     is_lower_alpha(codepoint) then
       return true
  end
  return false
end

local function is_space(codepoint) 
  -- detect space characters
  if codepoint==0x0009 or codepoint==0x000A or codepoint==0x000C or codepoint==0x0020 then
    return true
  end
  return false
end

HtmlStates.data = function(parser) 
  -- this is the default state
  local codepoint = parser.codepoint
  print("codepoint", parser.codepoint)
  if codepoint == less_than then
    -- start of tag
    return "tag_open"
  elseif codepoint  == amperesand then
    -- we must save the current state 
    -- what we will return to after entity
    parser.return_state = "data"
    return "character_reference" 
  else
    local data = {char = uchar(codepoint)}
    parser:start_token("character", data)
    parser:emit()
  end
  return "data"
end

HtmlStates.tag_open = function(parser)
  -- parse tag contents
  local codepoint = parser.codepoint
  if codepoint == exclam then
    return "markup_declaration_open"
  elseif codepoint == solidus then
    return "end_tag_open"
  elseif codepoint == question then
    return "bogus_comment"
  elseif is_alpha(codepoint) then
    local data = {
      name = {},
      attr = {},
      current_attr_name = {},
      current_attr_value = {},
      self_closing = false
    }
    parser:start_token("start_tag", data)
    return parser:tokenize("tag_name")
  else
    -- emit < and reconsume current character as data
    local data = {char="<"}
    parser:start_token("character", data)
    -- parser:emit()
    return parser:tokenize("data")
  end
end

HtmlStates.character_reference = function(parser)
  -- parse HTML entities
end

HtmlStates.markup_declaration_open = function(parser)
  -- started by <!
end

HtmlStates.end_tag_open = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) then
    local data = {
      name = {}
    }
    parser:start_token("end_tag", data)
    return parser:tokenize("tag_name")
  elseif codepoint == greater_than then
    return "data"
  else
    data = {
      data = {}
    }
    parser:start_token("comment", data)
    return parser:tokenize("bogus_comment")
  end
end

HtmlStates.bogus_comment = function(parser)
  -- started by <?
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser:emit()
    return "data"
  else
    parser:append_token_data("data", uchar(codepoint))
    return "bogus_comment"
  end
end

HtmlStates.tag_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then 
    return "before_attribute_name"
  elseif codepoint == solidus then
    return "self_closing_tag"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif is_upper_alpha(codepoint) then
    local lower = string.lower(uchar(codepoint))
    parser:append_token_data("name", lower)
  else
    local char = uchar(codepoint)
    parser:append_token_data("name", char)
  end
  return "tag_name"

end

HtmlStates.self_closing_tag = function(parser)
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser.current_token.self_closing = true
    parser:emit()
    return "data"
  else
    return parser:tokenize("before_attribute_name")
  end
end


HtmlStates.before_attribute_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    -- ignore spacing
    return "before_attribute_name"
  elseif codepoint == solidus or codepoint == greater_than then
    -- reconsume in after_attribute_name
    return parser:tokenize("after_attribute_name")
  elseif codepoint == equals then
    -- ToDo: handle https://html.spec.whatwg.org/multipage/parsing.html#parse-error-unexpected-equals-sign-before-attribute-name
  else
    -- start new attribute
    parser:start_attribute()
    return parser:tokenize("attribute_name")
  end
end

HtmlStates.attribute_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) 
     or codepoint == solidus
     or codepoint == greater_than 
  then
    return parser:tokenize("after_attribute_name")
  elseif codepoint == equals then
    return "before_attribute_value"
  elseif is_upper_alpha(codepoint) then
    -- lowercase attribute names
    local lower = string.lower(uchar(codepoint))
    parser:append_token_data("current_attr_name", lower)
    return "attribute_name"
  else
    parser:append_token_data("current_attr_name", uchar(codepoint))
    return "attribute_name"
  end
end

HtmlStates.after_attribute_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "after_attribute_name"
  elseif codepoint == equals then
    return "before_attribute_value"
  elseif codepoint == solidus then
    return "self_closing_tag"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    parser:start_attribute()
    return parser:tokenize("attribute_name")
  end
end

HtmlStates.before_attribute_value = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_attribute_value" 
  elseif codepoint == quoting then
    return "attribute_value_quoting"
  elseif codepoint == apostrophe then
    return "attribute_value_apostrophe"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    return  parser:tokenize("attribute_value_unquoted")
  end
end

HtmlStates.attribute_value_quoting = function(parser)
  local codepoint = parser.codepoint
  if codepoint == quoting then
    return "after_attribute_value_quoting"
  elseif codepoint == amperesand then
    parser.return_state = "attribute_value_quoting"
    return "character_reference"
  else
    parser:append_token_data("current_attr_value", uchar(codepoint))
    return "attribute_value_quoting"
  end
end

HtmlStates.attribute_value_apostrophe = function(parser)
  local codepoint = parser.codepoint
  if codepoint == apostrophe then
    return "after_attribute_value_quoting"
  elseif codepoint == amperesand then
    parser.return_state = "attribute_value_apostrophe"
    return "character_reference"
  else
    parser:append_token_data("current_attr_value", uchar(codepoint))
    return "attribute_value_apostrophe"
  end
end

HtmlStates.attribute_value_unquoted = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_attribute_name"
  elseif codepoint == amperesand then
    parser.return_state = "attribute_value_unquoted"
    return "character_reference"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    parser:append_token_data("current_attr_value", uchar(codepoint))
    return "attribute_value_unquoted"
  end
end

HtmlStates.after_attribute_value_quoting = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_attribute_name"
  elseif codepoint == solidus then
    return "self_closing_tag"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else 
    return parser:tokenize("before_attribute_name")
  end
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
  o.default_state = "data"
  o.state = o.default_state
  o.return_state = o.default_state
  o.current_token = {type="start"}
  return o
end

function HtmlParser:normalize_newlines(body)
  -- we must normalize newlines
  return body:gsub("\r\n", "\n"):gsub("\r", "\n")
end

-- declare void elements
local self_closing_tags_list = {"area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"}
 
local self_closing_tags = {}
for _,v in ipairs(self_closing_tags_list) do self_closing_tags[v] = true end




function HtmlParser:parse()
  -- we assume utf8 input, you must convert it yourself if the source is 
  -- in a different encoding
  self.text = {}
  self.state = self.default_state
  for pos, ucode in utf8.codes(self.body) do
    -- save buffer info and require the tokenize function
    self.position = pos
    self.codepoint = ucode
    self.character = uchar(ucode)
    self.state = self:tokenize(state) or self.state -- if tokenizer don't return new state, assume that it continues in the current state
  end
  self:add_text()
  return self:finish()
end

function HtmlParser:tokenize(state)
  local state = state or self.state
  local ucode = self.codepoint
  local text = self.text

  if ucode == less_than then
    -- state = "in_tag"
     self:add_text(text) 
  elseif ucode == greater_than then
    -- state = "data"
    self:add_tag(text)
  elseif self.position ~= self.last_position then
    -- self.text[#text+1] = uchar(ucode)
  end
  self.last_position = self.position
  -- execute state machine object and return new state
  local fn = HtmlStates[state] or function(parser) return self.default_state end
  local newstate =  fn(self)
  print("newstate", newstate, state, uchar(ucode))
  return newstate
end

function HtmlParser:start_token(typ, data)
  -- emit the previous token
  self:emit()
  data.type = typ
  self.current_token = data
end



function HtmlParser:append_token_data(name, data)
  -- append data to the current token
  local token = self.current_token or {}
  if token[name] and type(token[name]) == "table" then
    table.insert(token[name], data)
  end
end

function HtmlParser:set_token_data(name, data)
  local token = self.current_token or {}
  token[name] = data
end

function HtmlParser:start_attribute()
  local token = self.current_token or {}
  if token.type == "start_tag" then
    local attr_name = table.concat(token.current_attr_name)
    local attr_value = table.concat(token.current_attr_value) or ""
    if attr_name ~= "" then
      token.attr[attr_name] = attr_value
      print("saving attribute", attr_name, attr_value)
    end
    self:set_token_data("current_attr_name", {})
    self:set_token_data("current_attr_value", {})
  end
end


function HtmlParser:emit(token)
  -- state machine functions should use this function to emit tokens
  local token = token or self.current_token
  print("Emit", token.type)
  local token_type = token.type
  if token_type     == "character" then
    table.insert(self.text, token.char)
  elseif token_type == "doctype" then
  elseif token_type == "start_tag" then
    self:start_attribute()
    print("Emit start tag", table.concat(token.name))
    -- save last attribute
  elseif token_type == "end_tag" then
    print("Emit end tag", table.concat(token.name))
  elseif token_type == "comment" then
  elseif token_type == "empty" then

  end
  self.current_token = {type="empty"}
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
  local text = text
  if not text then
    text = self.text
  end
  if type(text) == "table" then
    if #text > 0 then
      text = table.concat(text)
    end
  end
  if type(text) == "string" and text~="" then
    local parent = self:get_parent()
    local node = Text:init(text, parent)
    parent:add_child(node)
  end
  self.text = {}
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
  self.text = {}
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



-- local p = HtmlParser:init("  <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
-- local p = HtmlParser:init("<html><HEAD><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
-- local p = HtmlParser:init("Hello <čau> text, hello <img src='hello' alt=\"sample <worldik> hello\" id=image title=<!this-comment /> image")
local p = HtmlParser:init("Hello <čau> text")
local dom = p:parse()
print_tree(dom)



-- 
M.Text       = Text
M.Element    = Element
M.HtmlParser = HtmlParser
M.self_closing_tags = self_closing_tags
return M 

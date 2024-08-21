--- HTML parsing module for LuaXML
-- @module luaxml-mod-html
-- @author Michal Hoftich <michal.h21@gmail.com
-- Copyright Michal Hoftich, 2022
-- HTML parser inspired by https://browser.engineering/html.html
-- but then redone using https://html.spec.whatwg.org/multipage/parsing.html
--
-- There main purpose of this module is to create an useful DOM for later processing
-- using LuaXML functions. Either for cleanup, or for translation to output formats, 
-- for example LaTeX. 
--
-- It should be possible to serialize DOM back to the original HTML code. 
--
-- We attempt to do some basic fixes, like to close paragraphs or list items that 
-- aren't closed correctly in the original code. We don't fix tables or 
-- formatting elements (see https://html.spec.whatwg.org/multipage/parsing.html#the-list-of-active-formatting-elements)
-- as these features don't seem necessary for the purpose of this module. We may change
-- this policy in the future, if it turns out that they are necessary. 
--
--
local M = {}

-- use local copies of utf8 functions
local ucodepoint = utf8.codepoint
local utfchar      = utf8.char
local function uchar(codepoint)
  if codepoint and codepoint > -1 then
    return utfchar(codepoint)
  end
  return ""
end

-- declare namespaces
local xmlns = {
  HTML = "http://www.w3.org/1999/xhtml",
  MathML = "http://www.w3.org/1998/Math/MathML",
  SVG = "http://www.w3.org/2000/svg",
  XLink = "http://www.w3.org/1999/xlink",
  XML = "http://www.w3.org/XML/1998/namespace",
  XMLNS = "http://www.w3.org/2000/xmlns/", 
}

-- we must make search tree for named entities, as their support 
-- is quite messy
local named_entities
if kpse then
  named_entities = require "luaxml-namedentities"
else
  named_entities = require "luaxml.namedentities"
end

local entity_tree = {children = {}}

local function update_tree(tree, char)
  local children = tree.children or {}
  local current = children[char] or {}
  children[char] = current
  tree.children = children
  return current
end

-- loop over named entities and update tree
for entity, char in pairs(named_entities) do
  local tree = entity_tree
  for char in entity:gmatch(".") do
    tree = update_tree(tree,char)
  end
  tree.entity = entity
  tree.char   = char
end

local function search_entity_tree(tbl) 
  -- get named entity for the list of characters
  local tree = entity_tree
  for _,char in ipairs(tbl) do 
    if tree.children then
      tree = tree.children[char]
      if not tree then return nil end
    else
      return nil
    end
  end
  -- print("tree", tree.char)
  return tree
end


-- declare  basic node types

local Root = {
  _type = "root",
  xmlns = xmlns.HTML
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
function Doctype:init(name, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.__tostring = function (x) 
    if x.data then
      return "<!DOCTYPE " .. x.name .. " " .. x.data ..  ">" 
    else
      return "<!DOCTYPE " .. x.name .. ">" 
    end
  end
  self.add_child = Root.add_child
  o.parent = parent
  o.name = name
  o.children = {}
  return o
end

function Doctype:add_data(data)
  self.data = data
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

local Comment = {
  _type = "comment"
}

function Comment:init(text, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.text = text
  self.__tostring = function (x) return "<!--" ..  x.text .. "-->" end
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
  self.__tostring = function(x) 
    local attr = {}
    for _, el in ipairs(x.attr) do 
      -- handle attributes
      local value
      if el.value:match('"') then
        value = "'" .. el.value .. "'"
      else
        value = '"' .. el.value .. '"'
      end
      attr[#attr+1] =  el.name .. "=" .. value
    end
    local closing = ">"
    if x.self_closing then
      closing = " />"
    end
    if #attr > 0 then
      return "<" .. x.tag .. " " .. table.concat(attr, " ") .. closing 
    else
      return "<" .. x.tag .. closing
    end
  end
  self.add_child = Root.add_child
  o.children = {}
  o.attr     = {}
  o.parent = parent
  -- default xmlns
  o.xmlns  = xmlns.HTML
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
local semicolon      = ucodepoint(";")
local hyphen         = ucodepoint("-")
local dash           = ucodepoint("-")
local numbersign     = ucodepoint("#")
local smallx         = ucodepoint("x")
local bigx           = ucodepoint("X")
local right_square   = ucodepoint("]")
local EOF            = -1 -- special character, meaning end of stream
local null           = 0

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


local function is_numeric(codepoint)
  if 47 < codepoint and codepoint < 58 then
    return true
  end
end

local function is_upper_hex(codepoint)
  if 64 < codepoint and codepoint < 71 then
    return true
  end
end

local function is_lower_hex(codepoint)
  if 96 < codepoint and codepoint < 103 then
    return true
  end
end

local function is_hexadecimal(codepoint) 
  if is_numeric(codepoint) or
     is_lower_hex(codepoint) or
     is_upper_hex(codepoint)
  then 
    return true
  end
end


local function is_alphanumeric(codepoint)
  return is_alpha(codepoint) or is_numeric(codepoint)
end

local function is_space(codepoint) 
  -- detect space characters
  if codepoint==0x0009 or codepoint==0x000A or codepoint==0x000C or codepoint==0x0020 then
    return true
  end
  return false
end

local function is_surrogate(codepoint)
  return  0xD800 <= codepoint and codepoint <= 0xDFFF
end


character_entity_replace_table = {
[0x80] =  0x20AC,  
[0x82] =  0x201A,  
[0x83] =  0x0192,  
[0x84] =  0x201E,  
[0x85] =  0x2026,  
[0x86] =  0x2020,  
[0x87] =  0x2021,  
[0x88] =  0x02C6,  
[0x89] =  0x2030,  
[0x8A] =  0x0160,  
[0x8B] =  0x2039,  
[0x8C] =  0x0152,  
[0x8E] =  0x017D,  
[0x91] =  0x2018,  
[0x92] =  0x2019,  
[0x93] =  0x201C,  
[0x94] =  0x201D,  
[0x95] =  0x2022,  
[0x96] =  0x2013,  
[0x97] =  0x2014,  
[0x98] =  0x02DC,  
[0x99] =  0x2122,  
[0x9A] =  0x0161,  
[0x9B] =  0x203A,  
[0x9C] =  0x0153,  
[0x9E] =  0x017E,  
[0x9F] =  0x0178  
}

local function fix_null(codepoint)
  if codepoint == null then
    return 0xFFFD
  else
    return codepoint
  end
end

HtmlStates.data = function(parser) 
  -- this is the default state
  local codepoint = parser.codepoint
  -- print("codepoint", parser.codepoint)
  if codepoint == less_than then
    -- start of tag
    return "tag_open"
  elseif codepoint  == amperesand then
    -- we must save the current state 
    -- what we will return to after entity
    parser.return_state = "data"
    return "character_reference" 
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
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
    parser:start_token("comment",{data={}})
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
  elseif codepoint == EOF then
    parser:emit_character(">")
    parser:emit_eof()
  else
    -- invalid tag
    -- emit "<" and reconsume current character as data
    parser:emit_character("<")
    return parser:tokenize("data")
  end
end

HtmlStates.character_reference = function(parser)
  -- parse HTML entities
  -- initialize temp buffer
  parser.temp_buffer = {"&"}
  local codepoint = parser.codepoint
  if is_alphanumeric(codepoint) then
    return parser:tokenize("named_character_reference")
  elseif codepoint == numbersign then
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "numeric_character_reference"
  else
    parser:flush_temp_buffer()
    return parser:tokenize(parser.return_state)
  end

end

HtmlStates.named_character_reference = function(parser)
  -- named entity parsing is pretty complicated 
  -- https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
  local codepoint = parser.codepoint
  -- test if the current entity name is included in the named entity list
  local search_table = {}
  -- first char in temp buffer is &, which we don't want to lookup in the search tree
  for i=2, #parser.temp_buffer do search_table[#search_table+1] = parser.temp_buffer[i] end
  if codepoint == semicolon then
    -- close named entity
    local entity = search_entity_tree(search_table) 
    if entity and entity.char then
      parser:add_entity(entity.char)
    else
      -- if the current name doesn't correspond to any named entity, flush everything into text
      parser:flush_temp_buffer()
      return parser:tokenize(parser.return_state)
    end
    return parser.return_state
  else
    local char = uchar(codepoint)
    -- try if the current entity name is in the named entity search tree
    table.insert(search_table, char)
    local entity = search_entity_tree(search_table)
    if entity then
      -- keep parsing name entity while we match a name
      table.insert(parser.temp_buffer, char)
      return "named_character_reference"
    else
      -- here this will be more complicated
      if #search_table > 1 then
        local token = parser.current_token
        if token.type == "start_tag" and (codepoint == equals or is_alphanumeric(codepoint)) then
          -- in attribute value, flush characters and retokenize  
          parser:flush_temp_buffer()
          return parser:tokenize(parser.return_state)
        else
          -- try to get entity for characters preceding the current character
          table.remove(search_table)
          local newentity = search_entity_tree(search_table)
          if newentity and newentity.char then
            parser:add_entity(newentity.char)
          else
            -- we need to find if parts of the current substring match a named entity
            -- for example &notit; -> ¬it; but &notin; -> ∉
            local rest = {}
            -- loop over the table with characters, and try to find if it matches entity
            for i = #search_table, 1,-1 do
              local removed_char = table.remove(search_table)
              -- 
              table.insert(rest, 1, removed_char)
              newentity = search_entity_tree(search_table)
              if newentity and newentity.char then
                parser:add_entity(newentity.char)
                parser.temp_buffer = rest
                break
              end
            end
            -- replace temporary buffer witch characters that followed the matched entity
            parser:flush_temp_buffer()
          end
          return parser:tokenize(parser.return_state)
        end
      else
        -- search table contains only the current character
        parser:flush_temp_buffer()
        return parser:tokenize(parser.return_state)
      end
    end
  end

end

HtmlStates.numeric_character_reference = function(parser)
  -- this variable will hold the number
  local codepoint = parser.codepoint
  parser.character_reference_code = 0
  if codepoint == smallx or codepoint == bigx then
    -- hexadecimal entity
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "hexadecimal_character_reference_start"
  else
    -- try decimal entity
    return parser:tokenize("decimal_character_reference_start")
  end

end

HtmlStates.hexadecimal_character_reference_start = function(parser)
  local codepoint = parser.codepoint
  if is_hexadecimal(codepoint) then
    return parser:tokenize("hexadecimal_character_reference")
  else
    parser:flush_temp_buffer()
    return parser:tokenize(parser.return_state)
  end
end

HtmlStates.decimal_character_reference_start = function(parser)
  local codepoint = parser.codepoint
  if is_numeric(codepoint) then
    return parser:tokenize("decimal_character_reference")
  else
    parser:flush_temp_buffer()
    return parser:tokenize(parser.return_state)
  end
end


HtmlStates.decimal_character_reference = function(parser)
  local codepoint = parser.codepoint
  -- helper functions for easier working with the character_reference_code
  local function multiply(number)
    parser.character_reference_code = parser.character_reference_code * number
  end
  local function add(number)
    parser.character_reference_code = parser.character_reference_code + number
  end
  if is_numeric(codepoint) then
    multiply(10)
    add(codepoint - 0x30)
  elseif codepoint == semicolon then
    return "numeric_reference_end_state"
  else
    -- this adds current entity
    parser:tokenize("numeric_reference_end_state")
    -- now tokenize the current character
    return parser:tokenize(parser.return_state)
  end
  return "decimal_character_reference"
end

HtmlStates.hexadecimal_character_reference = function(parser)
  local codepoint = parser.codepoint
  -- helper functions for easier working with the character_reference_code
  local function multiply(number)
    parser.character_reference_code = parser.character_reference_code * number
  end
  local function add(number)
    parser.character_reference_code = parser.character_reference_code + number
  end
  if is_numeric(codepoint) then
    multiply(16)
    add(codepoint - 0x30)
  elseif is_upper_hex(codepoint) then
    multiply(16)
    add(codepoint - 0x37)
  elseif is_lower_hex(codepoint) then
    multiply(16)
    add(codepoint - 0x57)
  elseif codepoint == semicolon then
    return "numeric_reference_end_state"
  else
    -- this adds current entity
    parser:tokenize("numeric_reference_end_state")
    -- now tokenize the current character
    return parser:tokenize(parser.return_state)
  end
  return "hexadecimal_character_reference"
end

HtmlStates.numeric_reference_end_state = function(parser)
  -- in this state, we don't need to 
  local character = parser.character_reference_code
  -- we need to clean invalid character codes
  if character == 0x00 or 
     character >  0x10FFFF or
     is_surrogate(character) 
  then
    character = 0xFFFD
  -- should we add special support for "noncharacter"? I think we can pass them to the output anyway
  elseif character_entity_replace_table[character] then 
    character = character_entity_replace_table[character]
  end
  parser:add_entity(uchar(character))
  return parser.return_state
end


HtmlStates.markup_declaration_open = function(parser)
  -- started by <!
  -- we now need to find the following text, to find if we started comment, doctype, or cdata
  local comment_pattern = "^%-%-"
  local doctype_pattern = "^[Dd][Oo][Cc][Tt][Yy][Pp][Ee]"
  local cdata_pattern   = "^%[CDATA%["
  local start_pos = parser.position
  local text = parser.body
  if text:match(comment_pattern, start_pos) then
    -- local _, newpos = text:find(comment_pattern, start_pos)
    -- we need to ignore next few characters
    parser.ignored_pos = start_pos + 1
    parser:start_token("comment", {data = {}})
    return "comment_start"
  elseif text:match(doctype_pattern, start_pos) then
    parser.ignored_pos = start_pos + 6
    parser:start_token("doctype", {name = {}, data = {}, force_quirks = false})
    return "doctype"
  elseif text:match(cdata_pattern, start_pos) then
    parser.ignored_pos = start_pos + 6
    local current_element = parser:current_node()
    if current_element.xmlns == xmlns.HTML or not current_element.xmlns then
      -- we change CDATA simply to comments
      parser:start_token("comment", {data = {"[CDATA["}})
      return "bogus_comment"
    else
      -- we are in XML mode, this happens for included SVG or MathML
      return "cdata_section"
    end
  else
    parser:start_token("comment", {data = {}})
    return "bogus_comment"
  end
  -- local start, stop = string.find(parser.body, comment_pattern, parser.position)
end


HtmlStates.cdata_section = function(parser)
  local codepoint = parser.codepoint
  if codepoint == right_square then
    return "cdata_section_bracket"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "cdata_section"
  end
end

HtmlStates.cdata_section_bracket = function(parser)
  local codepoint = parser.codepoint
  if codepoint == right_square then
    return "cdata_section_end"
  else
    parser:emit_character("]")
    return parser:tokenize("cdata_section")
  end
end

HtmlStates.cdata_section_end = function(parser)
  local codepoint = parser.codepoint
  if codepoint == right_square then
    parser:emit_character("]")
    return "cdata_section_end"
  elseif codepoint == greater_than then
    return "data"
  else
    parser:emit_character("]")
    return parser:tokenize("cdata_section")
  end
end


HtmlStates.comment_start = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_start_dash"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_start_dash = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_end"
  elseif codepoint == greater_than then
    parser:emit()
    return data
  elseif codepoint == EOF then
    parser:emit()
    parser:emit_eof()
  else
    parser:append_token_data("data", "-")
    return parser:tokenize("comment")
  end
end

HtmlStates.comment = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == less_than then
    parser:append_token_data("data", uchar(codepoint))
    return "comment_less_than"
  elseif codepoint == hyphen then
    return "comment_end_dash"
  elseif codepoint == EOF then
    parser:emit()
    parser:emit_eof()
  else
    parser:append_token_data("data", uchar(codepoint))
  end
  return "comment"
end

HtmlStates.comment_less_than = function(parser)
  local codepoint = parser.codepoint
  if codepoint == exclam then
    parser:append_token_data("data", uchar(codepoint))
    return "comment_less_than_bang"
  elseif codepoint == less_than then
    parser:append_token_data("data", uchar(codepoint))
    return "comment_less_than"
  else
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_less_than_bang = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_less_than_bang_dash"
  else
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_less_than_bang_dash = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_less_than_bang_dash_dash"
  else
    return parser:tokenize("comment_end_dash")
  end

end

HtmlStates.comment_less_than_bang_dash_dash = function(parser)
  -- these comment states start to be ridiculous
  local codepoint = parser.codepoint
  if codepoint == greater_than or codepoint == EOF then
    return parser:tokenize("comment_end")
  else
    return parser:tokenize("comment_end")
  end
end

HtmlStates.comment_end_dash = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_end"
  elseif codepoint == EOF then
    parser:emit()
    parser:emit_eof()
  else
    parser:append_token_data("data", uchar(codepoint))
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_end = function(parser)
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == exclam then
    return "comment_end_bang"
  elseif codepoint == hyphen then
    parser:append_token_data("data", "-")
    return "comment_end"
  elseif codepoint == EOF then
    parser:emit()
    parser:emit_eof()
  else
    parser:append_token_data("data", "--")
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_end_bang = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    parser:append_token_data("data", "--!")
    return "comment_end_dash"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    parser:emit()
    parser:emit_eof()
  else
    parser:append_token_data("data", "--!")
    return parser:tokenize("comment")
  end
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
  elseif codepoint == EOF then
    parser:discard_token()
    parser:emit_character("</")
    parser:emit_eof()
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
  codepoint = fix_null(codepoint)
  if codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    parser:emit()
    parser:emit_eof()
  else
    parser:append_token_data("data", uchar(codepoint))
    return "bogus_comment"
  end
end

local function doctype_eof(parser)
    parser:set_token_data("force_quirks", true)
    parser:emit()
    parser:emit_eof()
end

HtmlStates.doctype = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_doctype_name"
  elseif codepoint == greater_than then
    return parser:tokenize("before_doctype_name")
  elseif codepoint == EOF then
    doctype_eof(parser)
  else
    return parser:tokenize("before_doctype_name")
  end
end

HtmlStates.before_doctype_name = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if is_space(codepoint) then
    return "before_doctype_name"
  elseif codepoint == greater_than then
    parser:set_token_data("force_quirks", true)
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    doctype_eof(parser)
  elseif is_upper_alpha(codepoint) then
    -- add lowercase name
    parser:append_token_data("name", uchar(codepoint + 0x20))
    return "doctype_name"
  else
    parser:append_token_data("name", uchar(codepoint))
    return "doctype_name"
  end
end

HtmlStates.doctype_name = function(parser)

  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if is_space(codepoint) then
    return "after_doctype_name"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    doctype_eof(parser)
  elseif is_upper_alpha(codepoint) then
    -- add lowercase name
    parser:append_token_data("name", uchar(codepoint + 0x20))
    return "doctype_name"
  else
    parser:append_token_data("name", uchar(codepoint))
    return "doctype_name"
  end
end

HtmlStates.after_doctype_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "after_doctype_name"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    doctype_eof(parser)
  else
    parser:append_token_data("data", uchar(codepoint))
    -- there are lot of complicated rules how to consume doctype, 
    -- but I think that for our purpose they aren't interesting.
    -- so everything until EOF or > is consumed as token.data
    return "consume_doctype_data"
  end
end

HtmlStates.consume_doctype_data = function(parser)
  -- this state just reads everything inside doctype as data
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    doctype_eof(parser)
  else
    parser:append_token_data("data", uchar(codepoint))
    return "consume_doctype_data"
  end
end

HtmlStates.tag_name = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
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
  elseif codepoint==EOF then
    parser:emit()
    parser:emit_eof()
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

HtmlStates.rcdata = function(parser)
  -- this is the default state
  local codepoint = parser.codepoint
  -- print("codepoint", parser.codepoint)
  codepoint = fix_null(codepoint)
  if codepoint == less_than then
    -- start of tag
    return "rcdata_less_than"
  elseif codepoint  == amperesand then
    -- we must save the current state 
    -- what we will return to after entity
    parser.return_state = "rcdata"
    return "character_reference" 
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
  end
  return "rcdata"
end

local function discard_rcdata_end_tag(parser, text)
    parser:discard_token()
    parser:emit_character(text)
end

HtmlStates.rcdata_less_than = function(parser)
  local codepoint = parser.codepoint
  if codepoint == solidus then
    return "rcdata_end_tag_open"
  else
    discard_rcdata_end_tag(parser, "<")
    return parser:tokenize("rcdata")
  end
end

HtmlStates.rcdata_end_tag_open = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) then
    parser:start_token("end_tag", {name={}})
    parser.temp_buffer = {}
    return parser:tokenize("rcdata_end_tag_name")
  else
    discard_rcdata_end_tag(parser, "</")
    return parser:tokenize("rcdata")
  end
end



HtmlStates.rcdata_end_tag_name = function(parser)
  -- we need to find name of the currently opened tag
  local parent = parser:get_parent() or {}
  local opened_tag = parent.tag 
  local current_tag = table.concat(parser.current_token.name or {})
  local codepoint = parser.codepoint
  if is_upper_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint + 0x20))
    -- insert current char to temp buffer
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "rcdata_end_tag_name"
  elseif is_lower_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "rcdata_end_tag_name"
  elseif opened_tag == current_tag then
    if is_space(codepoint) then
      return "before_attribute_name"
    elseif codepoint == solidus then
      return "self_closing_tag"
    elseif codepoint == greater_than then
      parser:emit()
      return "data"
    end
  else
    discard_rcdata_end_tag(parser, "</" .. table.concat(parser.temp_buffer))
    parser.temp_buffer = {}
    return parser:tokenize("rcdata")
  end
end

HtmlStates.rawtext = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == less_than then
    return "rawtext_less_than"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "rawtext"
  end
end

HtmlStates.rawtext_less_than = function(parser)
  local codepoint = parser.codepoint
  if codepoint == solidus then
    return "rawtext_end_tag_open"
  else
    parser:emit_character("<")
    return parser:tokenize("rawtext")
  end
end

HtmlStates.rawtext_end_tag_open = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) then
    parser:start_token("end_tag", {name={}})
    parser.temp_buffer = {}
    return parser:tokenize("rawtext_end_tag_name")
  else
    parser:emit_character("</")
    return parser:tokenize("rawtext")
  end
end

HtmlStates.rawtext_end_tag_name = function(parser)
  -- we need to find name of the currently opened tag
  local parent = parser:get_parent() or {}
  local opened_tag = parent.tag 
  local current_tag = table.concat(parser.current_token.name or {})
  local codepoint = parser.codepoint
  if is_upper_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint + 0x20))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "rawtext_end_tag_name"
  elseif is_lower_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "rawtext_end_tag_name"
  elseif opened_tag == current_tag then
    if is_space(codepoint) then
      return "before_attribute_name"
    elseif codepoint == solidus then
      return "self_closing_tag"
    elseif codepoint == greater_than then
      parser:emit()
      return "data"
    end
  else
    discard_rcdata_end_tag(parser, "</" .. table.concat(parser.temp_buffer))
    parser.temp_buffer = {}
    return parser:tokenize("rawtext")
  end
end

HtmlStates.script_data = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == less_than then
    return "script_data_less_than"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "script_data"
  end
end

HtmlStates.script_data_less_than = function(parser)
  local codepoint = parser.codepoint
  if codepoint == solidus then
    parser.temp_buffer = {}
    return "script_data_end_tag_open"
  elseif codepoint == exclam then
    parser:emit_character("<!")
    return "script_data_escape_start"
  else
    parser:emit_character("<")
    return parser:tokenize("script_data")
  end
end

HtmlStates.script_data_end_tag_open = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) then
    parser:start_token("end_tag", {name={}})
    return parser:tokenize("script_data_end_tag_name")
  else
    parser:emit_character("</")
    return parser:tokenize("script_data")
  end
end

HtmlStates.script_data_end_tag_name = function(parser)
  -- we need to find name of the currently opened tag
  local parent = parser:get_parent() or {}
  local opened_tag = parent.tag 
  local current_tag = table.concat(parser.current_token.name or {})
  local codepoint = parser.codepoint
  if is_upper_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint + 0x20))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "script_data_end_tag_name"
  elseif is_lower_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "script_data_end_tag_name"
  elseif opened_tag == current_tag then
    if is_space(codepoint) then
      return "before_attribute_name"
    elseif codepoint == solidus then
      return "self_closing_tag"
    elseif codepoint == greater_than then
      parser:emit()
      return "data"
    end
  else
    discard_rcdata_end_tag(parser, "</" .. table.concat(parser.temp_buffer))
    parser.temp_buffer = {}
    return parser:tokenize("script_data")
  end

end

HtmlStates.script_data_escape_start = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    parser:emit_character("-")
    return "script_data_escape_start_dash"
  else
    parser:tokenize("script_data")
  end
end

HtmlStates.script_data_escape_start_dash = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    parser:emit_character("-")
    return "script_data_escaped_dash_dash"
  else
    parser:tokenize("script_data")
  end

end


HtmlStates.script_data_escaped = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == hyphen then
    parser:emit_character("-")
    return "script_data_escaped_dash"
  elseif codepoint == less_than then
    return "script_data_escaped_less_than_sign"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "script_data_escaped"
  end
end

HtmlStates.script_data_escaped_dash = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == hyphen then
    parser:emit_character("-")
    return "script_data_escaped_dash_dash"
  elseif codepoint == less_than then
    return "script_data_escaped_less_than_sign"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "script_data_escaped"
  end

end

HtmlStates.script_data_escaped_dash_dash = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == hyphen then
    parser:emit_character("-")
    return "script_data_escaped_dash_dash"
  elseif codepoint == less_than then
    return "script_data_escaped_less_than_sign"
  elseif codepoint == greater_than then
    parser:emit_character(">")
    return "script_data"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "script_data_escaped"
  end

end

HtmlStates.script_data_escaped_less_than_sign = function(parser)
  local codepoint = parser.codepoint
  if codepoint == solidus then
    parser.temp_buffer = {}
    return "script_data_escaped_end_tag_open"
  elseif is_alpha(codepoint) then
    parser.temp_buffer = {}
    parser:emit_character("<")
    return parser:tokenize("script_data_double_escape_start")
  else
    parser:emit_character("<")
    return parser:tokenize("script_data_escaped")
  end
end

HtmlStates.script_data_escaped_end_tag_open = function(parser) 
  local codepoint = parser.codepoint
  if is_alpha(codepoint) then
    parser:start_token("end_tag", {name={}})
    return parser:tokenize("script_data_escaped_end_tag_name")
  else
    parser:emit_character("</")
    return parser:tokenize("script_data_escaped")
  end
end

HtmlStates.script_data_escaped_end_tag_name = function(parser)
  -- we need to find name of the currently opened tag
  local parent = parser:get_parent() or {}
  local opened_tag = parent.tag 
  local current_tag = table.concat(parser.current_token.name or {})
  local codepoint = parser.codepoint
  if is_upper_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint + 0x20))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "script_data_escaped_end_tag_name"
  elseif is_lower_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "script_data_escaped_end_tag_name"
  elseif opened_tag == current_tag then
    if is_space(codepoint) then
      return "before_attribute_name"
    elseif codepoint == solidus then
      return "self_closing_tag"
    elseif codepoint == greater_than then
      parser:emit()
      return "data"
    end
  else
    discard_rcdata_end_tag(parser, "</" .. table.concat(parser.temp_buffer))
    parser.temp_buffer = {}
    return parser:tokenize("script_data_escaped")
  end
end

HtmlStates.script_data_double_escape_start = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) or
     codepoint == solidus or 
     codepoint == greater_than 
  then
    local current_tag = table.concat(parser.current_token.name or {})
    parser:emit_character(uchar(codepoint))
    if current_tag == "script" then
      return "script_data_double_escaped"
    else
      return "script_data_escaped"
    end
  elseif is_upper_alpha(codepoint) then
    parser:emit_character(uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint) + 0x20)
    return "script_data_double_escape_start"
  elseif is_lower_alpha(codepoint) then
    parser:emit_character(uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "script_data_double_escape_start"
  else
    return parser:tokenize("script_data_escaped")
  end
end

HtmlStates.script_data_double_escaped = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == hyphen then
    parser:emit_character("-")
    return "script_data_double_escaped_dash"
  elseif codepoint == less_than then
    parser:emit_character("<")
    return "script_data_double_escaped_less_than_sign"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "script_data_double_escaped"
  end
end

HtmlStates.script_data_double_escaped_dash = function(parser)
  local codepoint = parser.codepoint
  codepoint = fix_null(codepoint)
  if codepoint == hyphen then
    parser:emit_character("-")
    return "script_data_double_escaped_dash"
  elseif codepoint == less_than then
    parser:emit_character("<")
    return "script_data_double_escaped_less_than_sign"
  elseif codepoint == greater_than then
    parser:emit_character(">")
    return "script_data"
  elseif codepoint == EOF then
    parser:emit_eof()
  else
    parser:emit_character(uchar(codepoint))
    return "script_data_double_escaped"
  end
end

HtmlStates.script_data_double_escaped_less_than_sign = function(parser)
  local codepoint = parser.codepoint
  if codepoint == solidus then
    parser:emit("/")
    return "script_data_double_escape_end"
  else
    return parser:tokenize("script_data_double_escaped")
  end
end

HtmlStates.script_data_double_escape_end = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) or
     codepoint == solidus or 
     codepoint == greater_than 
  then
    local current_tag = table.concat(parser.current_token.name or {})
    parser:emit_character(uchar(codepoint))
    if current_tag == "script" then
      return "script_data_escaped"
    else
      return "script_data_double_escaped"
    end
  elseif is_upper_alpha(codepoint) then
    parser:emit_character(uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint) + 0x20)
    return "script_data_double_escape_start"
  elseif is_lower_alpha(codepoint) then
    parser:emit_character(uchar(codepoint))
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "script_data_double_escape_start"
  else
    return parser:tokenize("script_data_double_escaped")
  end

end

-- formatting elements needs special treatment
local formatting_element_names ={
   a = true, b = true, big = true, code = true, em = true, font = true, i = true, nobr = true, s = true, small = true, strike = true, strong = true, tt = true, u = true
}
local function is_formatting_element(name)
  return formatting_element_names[name]
end

local function hash_from_array(tbl)
  local t = {}
  for _, v in ipairs(tbl) do t[v] = true end
  return t
end


local special_elements_list = hash_from_array {"address", "applet", "area", "article", "aside",
"base", "basefont", "bgsound", "blockquote", "body", "br", "button", "caption",
"center", "col", "colgroup", "dd", "details", "dir", "div", "dl", "dt",
"embed", "fieldset", "figcaption", "figure", "footer", "form", "frame",
"frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup",
"hr", "html", "iframe", "img", "input", "keygen", "li", "link", "listing",
"main", "marquee", "menu", "meta", "nav", "noembed", "noframes", "noscript",
"object", "ol", "p", "param", "plaintext", "pre", "script", "section",
"select", "source", "style", "summary", "table", "tbody", "td", "template",
"textarea", "tfoot", "th", "thead", "title", "tr", "track", "ul", "wbr", "xmp",
"mi","mo","mn","ms","mtext", "annotation-xml","foreignObject","desc", "title"
}


local function is_special(name)
  return special_elements_list[name]
end

-- these lists are used in HtmlParser:generate_implied_endtags()
local implied_endtags = {dd=true, dt=true, li = true, optgroup = true, option = true, p = true, rb = true, rp = true, rd = true, trc = true}
local implied_endtags_thoroughly = {dd=true, dt=true, li = true, optgroup = true, option = true, p = true, 
      rb = true, rp = true, rd = true, trc = true, caption = true, colgroup = true, tbody = true, td = true, 
      tfoot = true, th = true, thead = true, tr = true
}

-- find if unfinished tags list contain a tag
-- it fails if any element from element_list is matched before that tag
local function is_in_scope(parser, target, element_list)
  for i = #parser.unfinished, 1, -1 do
    local node = parser.unfinished[i] 
    local tag = node.tag
    if tag == target then 
      return true
    elseif element_list[tag] then
      return false
    end
  end
  return false
end

local particular_scope_elements = { applet = true, caption = true, html = true, table = true, td = true,
      th = true, marquee = true, object = true, template = true, mi = true, mo = true, mn = true,
      ms = true, mtext = true, ["annotation-xml"] = true, foreignObject = true, desc = true, title = true,
}

local function is_in_particular_scope(parser, target)
  return is_in_scope(parser, target, particular_scope_elements)
end

-- derived scope lists
--
-- list_item scope
local list_item_scope_elements = {ol = true, ul = true}
for k,v in pairs(particular_scope_elements) do list_item_scope_elements[k] = v end

local function is_in_list_item_scope(parser, target)
  return is_in_scope(parser, target, list_item_scope_elements)
end

-- button scope
local button_scope_elements = {button = true}
for k,v in pairs(particular_scope_elements) do button_scope_elements[k] = v end

local function is_in_button_scope(parser, target)
  return is_in_scope(parser, target, button_scope_elements)
end

-- table scope
local table_scope_elements = {html = true, table = true, template = true}

local function is_in_table_scope(parser, target)
  return is_in_scope(parser, target, table_scope_elements)
end

-- select scope
local function is_in_select_scope(parser, target)
  -- this scope is specific, because it supports all tags except two
  for i = #parser.unfinished, 1, -1 do
    local node = parser.unfinished[i] 
    local tag = node.tag
    if tag == target then 
      return true
    elseif tag == "optgroup" or tag == "option" then
      -- only these two tags are supported
    else
      return false
    end
  end
  return false
end

-- List of active formatting elements
-- https://html.spec.whatwg.org/multipage/parsing.html#the-list-of-active-formatting-elements
-- we don't implement it yet, but maybe in the future. 


local HtmlTreeStates = {}






---  @type HtmlParser
local HtmlParser = {}

--- Initialize the HTML Object
---@param body string HTML to be parsed
---@return table initialized object
function HtmlParser:init(body)
  local o ={}
  setmetatable(o, self)
  self.__index        = self
  o.body              = self:normalize_newlines(body) -- HTML string
  o.position          = 0                -- position in the parsed string
  o.unfinished        = {}    -- insert Root node into the list of opened elements
  o.Document          = Root:init()
  o.default_state     = "data"           -- default state machine state
  o.state             = o.default_state  -- working state of the machine
  o.return_state      = o.default_state  -- special state set by entities parsing
  o.temp_buffer       = {}               -- keep temporary data
  o.current_token     = {type="start"}   -- currently processed token
  o.insertion_mode    = "initial"        -- tree construction state
  o.head_pointer      = nil              -- pointer to the Head element
  o.form_pointer      = nil
  o.active_formatting = {}               -- list of active formatting elements
  o.scripting_flag    = false            -- we will not support scripting
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



--- Execute the HTML parser
--- @return table Root node of the HTML DOM
function HtmlParser:parse()
  -- we assume utf8 input, you must convert it yourself if the source is 
  -- in a different encoding. for example using luaxml-encodings library
  self.text = {}
  self.state = self.default_state
  -- this should enable us to pass over some characters that we want to ignore
  -- for example scripts, css, etc.
  self.ignored_pos = -1
  for pos, ucode in utf8.codes(self.body) do
    -- save buffer info and require the tokenize function
    if pos > self.ignored_pos then
      self.position = pos
      self.codepoint = ucode
      self.character = uchar(ucode)
      self.state = self:tokenize(self.state) or self.state -- if tokenizer don't return new state, assume that it continues in the current state
    end
  end
  return self:finish()
end

function HtmlParser:tokenize(state)
  local state = state or self.state
  local ucode = self.codepoint
  local text = self.text

  self.last_position = self.position
  self.element_state = false
  -- execute state machine object and return new state
  local fn = HtmlStates[state] or function(parser) return self.default_state end
  local newstate =  fn(self)
  -- this should enable changing state from elements that needs special treatment, like <script> or <style>
  if self.element_state then return self.element_state end
  -- print("newstate", newstate, state, uchar(ucode or 32))
  return newstate
end

function HtmlParser:start_token(typ, data)
  -- emit the previous token
  -- self:emit()
  data.type = typ
  self.current_token = data
end

function HtmlParser:discard_token()
  self.current_token = {type="empty"}
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

function HtmlParser:flush_temp_buffer()
  -- write stuff from the temp buffer back to the document
  local token = self.current_token
  if token.type == "start_tag" then
    -- in start tag, entities can be only in attribute value
    for _, char in ipairs(self.temp_buffer) do
      table.insert(token.current_attr_value, char)
    end
  elseif self.return_state == "data" then
    -- handle entities in text
    for _, char in ipairs(self.temp_buffer) do
      self:start_token("character", {char=char})
      self:emit()
    end
  end
  self.temp_buffer = {}
end

function HtmlParser:add_entity(char)
  local token = self.current_token
  if token.type == "start_tag" then
    table.insert(token.current_attr_value, char)
  else
    self:start_token("character", {char=char})
    self:emit()
  end
  self.temp_buffer = {}
end

function HtmlParser:emit(token)
  -- state machine functions should use this function to emit tokens
  local token = token or self.current_token
  -- print("Emit", token.type)
  local token_type = token.type
  if token_type     == "character" then
    table.insert(self.text, token.char)
  elseif token_type == "doctype" then
    self:add_text()
    self:add_doctype()
  elseif token_type == "start_tag" then
    self:add_text()
    -- self:start_attribute()
    self:reset_insertion_mode()
    self:start_tag()
    -- print("Emit start tag", table.concat(token.name))
    -- save last attribute
  elseif token_type == "end_tag" then
    self:add_text()
    self:end_tag()
    -- print("Emit end tag", table.concat(token.name))
  elseif token_type == "comment" then
    self:add_text()
    self:add_comment()
    -- self:start_attribute()
  elseif token_type == "empty" then

  end
  -- self.current_token = {type="empty"}
end

function HtmlParser:emit_character(text)
  self:start_token("character", {char=text})
  self:emit()
end

function HtmlParser:emit_eof()
  self:start_token("end_of_file", {})
  self:emit()
end

function HtmlParser:get_parent()
  -- return parent element
  return self.unfinished[#self.unfinished] or self.Document
end

function HtmlParser:close_element()
  -- return parent element and remove it from the unfinished list
  return table.remove(self.unfinished)
end

function HtmlParser:add_text(text)
  -- process current text node
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


function HtmlParser:start_attribute()
  local token = self.current_token or {}
  if token.type == "start_tag" then
    local attr_name = table.concat(token.current_attr_name)
    local attr_value = table.concat(token.current_attr_value) or ""
    if attr_name ~= "" then
      -- token.attr[attr_name] = attr_value
      table.insert(token.attr, {name = attr_name, value = attr_value})
      -- print("saving attribute", attr_name, attr_value)
    end
    self:set_token_data("current_attr_name", {})
    self:set_token_data("current_attr_value", {})
  end
end

function HtmlParser:set_xmlns(node, parent)
  -- handle xmlns
  local in_attr = false
  -- try to find xmlns in node's attributes first
  for _, attr in ipairs(node.attr) do
    if attr.name == "xmlns" then
      node.xmlns = attr.value
      in_attr = true
      break
    end
  end
  if not in_attr then
    -- if we cannot find xmlns attribute, then use 
    --  xmlns from the parent element, or the default xmlns 
    local parent = self:get_parent()
    node.xmlns = parent.xmlns or xmlns.HTML
  end
end

function HtmlParser:pop_element()
  -- close the current element and add it to the DOM
  local el = self:close_element()
  local parent = self:get_parent()
  parent:add_child(el)
  return el
end

local close_p_at_start = hash_from_array {"address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "main", "menu", "nav", "ol", "p", "search", "section", "summary", "ul", "pre", "listing", "form", "table", "xmp", "hr"}

local close_headers = hash_from_array {"h1", "h2", "h3", "h4", "h5", "h6"}

local body_modes = hash_from_array {"in_body", "in_cell", "in_row", "in_select", "in_table", "in_table_body", "in_frameset"}

local list_items = hash_from_array {"li", "dt", "dd"}

local close_address_at_end = hash_from_array{"address", "article", "aside", "blockquote", "button", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "listing", "main", "menu", "nav", "ol", "pre", "search", "section", "summary", "ul", "form"}


function HtmlParser:close_unfinished(name)
  -- close all unfinished elements until the element with the given name is found
  for i = #self.unfinished, 1, -1 do
    local el = self:pop_element()
    if el.tag == name then
      break
    end
  end
end


function HtmlParser:close_paragraph()
  -- close currently open <p> elements
  self:close_unfinished("p")
end

function HtmlParser:current_element_name()
  -- return name of the current element
  return self:get_parent().tag
end

local not_specials = hash_from_array { "address", "div", "p"}

local function handle_list_item(self, name)
  -- we handle li, dt and dd. dt and dd should close each other, li closes only itself
  local names = {dt = true, dd = true}
  if name == "li" then names = {li=true} end
  for i = #self.unfinished, 1, -1 do
    local current = self.unfinished[i]
    local current_tag = current.tag
    if names[current_tag] then
      self:generate_implied_endtags(nil, {current.tag})
      for j = #self.unfinished, i, -1 do
        self:pop_element()
      end
      break
    elseif is_special(current_tag) and not not_specials[name] then
      break
    end
  end
end

local close_paragraph = function(self)
  if is_in_button_scope(self, "p") then
    self:close_paragraph()
  end
end

function HtmlParser:handle_insertion_mode(token)
  -- simple handling of https://html.spec.whatwg.org/multipage/parsing.html#tree-construction
  -- we don't support most rules, just the most important for avoiding mismatched tags

  if body_modes[self.insertion_mode] then
    if token.type == "start_tag" then
      local name = table.concat(token.name)
      if close_p_at_start[name] then close_paragraph(self) end
      if close_headers[name] then
        close_paragraph(self)
        -- close current element if it is already header 
        if close_headers[self:current_element_name()] then
          self:pop_element()
        end
      elseif name == "pre" or name == "listing" then
        -- we should ignore next "\n" char token
      elseif name == "image" then
        -- image tag is an error, change to <img>
        token.name = {"img"}
      elseif list_items[name] then
        handle_list_item(self, name)
        close_paragraph(self)
      end
    elseif token.type == "end_tag" then
      local name = table.concat(token.name)
      if close_address_at_end[name]  then
        if is_in_scope(self, name, {}) then
          self:generate_implied_endtags()
          self:close_unfinished(name)
          return false
        else
          token.type = "ignore"
        end
      elseif name == "p" then
        if not is_in_button_scope(self, "p") then
          local parent = self:get_parent()
          local node = Element:init("p", parent)
          table.insert(self.unfinished, node)
        end
        -- use self:close_paragraph() instead of close_paragraph() because we don't need to check scope at this point
        self:close_paragraph()
      elseif name == "br" then
        token.type = "start_tag"
      elseif close_headers[name] then
        local header_in_scope = false
        -- detect, if there are any open h1-h6 tag and close it
        for el, _ in pairs(close_headers) do 
          if is_in_scope(self, el, {}) then
            header_in_scope = el 
            break
          end
        end
        if not header_in_scope then
          token.type = "ignore"
        else
          self:close_unfinished(header_in_scope)
        end
      end
    end
  end
  return true
end

local rawtext_elements = hash_from_array {"style", "textarea", "xmp"}


function HtmlParser:start_tag()
  local token = self.current_token
  self:handle_insertion_mode(token)
  if token.type == "start_tag" then
    -- close all currently opened attributes
    self:start_attribute()
    -- initiate Element object, pass attributes and info about self_closing
    local name = table.concat(token.name)
    local parent = self:get_parent()
    local node = Element:init(name, parent)
    node.attr = token.attr
    node.self_closing = token.self_closing
    self:set_xmlns(node)
    -- in this handler we should close <p> or <li> elements without explicit closing tags
    if token.self_closing        -- <img />
      or self_closing_tags[name] -- void elements
    then
      parent:add_child(node, node.tag)
    else
      -- add to the unfinished list
      table.insert(self.unfinished, node)
    end
    if name == "title" then 
      self.element_state = "rcdata" 
    elseif rawtext_elements[name] then
      self.element_state = "rawtext" 
    elseif name == "script" then
      self.element_state = "script_data"
    end
  end
end

function HtmlParser:end_tag()
  -- close current opened element
  local token = self.current_token
  local should_pop = self:handle_insertion_mode(token)
  if token.type == "end_tag" then
    if #self.unfinished==0 then return nil end
    -- we shouldn't close elements if handle_insertion_mode() already closed them
    if should_pop then
      -- close the current element only if the token is in the current scope
      if is_in_scope(self, table.concat(token.name), {}) then
        self:pop_element()
      end
    end
  end
end

function HtmlParser:add_comment()
  local token = self.current_token
  if token.type == "comment" then
    self:start_attribute()
    local parent = self:get_parent()
    local text = table.concat(token.data)
    local node = Comment:init(text, parent)
    parent:add_child(node)
  end
end

function HtmlParser:add_doctype()
  local token = self.current_token
  if token.type == "doctype" then
    self:start_attribute()
    local parent = self:get_parent()
    local name = table.concat(token.name)
    local node = Doctype:init(name, parent)
    if #token.data > 0 then
      node:add_data(table.concat(token.data))
    end
    parent:add_child(node)
  end
end

function HtmlParser:switch_insertion(name)
  self.insertion_mode = name
end

function HtmlParser:current_node()
  return self:get_parent()
end

function HtmlParser:adjusted_current_node()
  -- we don't support this feature yet
  -- https://html.spec.whatwg.org/multipage/parsing.html#adjusted-current-node
  return self:current_node()
end


local simple_modes = {
  body = "in_body",
  td = "in_cell",
  th = "in_cell",
  tr = "in_row",
  tbody = "in_table_body",
  thead = "in_table_body",
  tfoot = "in_table_body",
  caption = "in_caption",
  colgroup = "in_column_group",
  table = "in_table",
  template = "current_template_insertion_mode",
  frameset = "in_frameset"
}

function HtmlParser:reset_insertion_mode()
  -- https://html.spec.whatwg.org/multipage/parsing.html#reset-the-insertion-mode-appropriately
  local last = false
  for position = #self.unfinished, 1, -1 do
    local node = self.unfinished[position]
    if position == 1 then last = true end
    local name = node.tag
    -- switch to insertion mode based on the current element name
    -- there is lot of other cases, but we support only basic ones
    -- we can support other insertion modes in the future
    if name == "head" and last == true then
      self:switch_insertion("in_head")
      return
    elseif name == "html" then
      if not self.head_pointer then
        self:switch_insertion("before_head")
        return
      else
        self:switch_insertion("after_head")
        return
      end
    elseif name == "select" then
      if not last then
        for x = position -1, 1, -1 do
          if x == 1 then break end
          local ancestor = self.unfinished[x] 
          local ancestor_name = ancestor.tag
          if ancestor_name == "template" then
            break
          elseif ancestor_name == "table" then
            self:switch_insertion("in_select_in_table")
            return 
          end
        end
      end
      self:switch_insertion("in_select")
      return
    elseif simple_modes[name] then
      self:switch_insertion(simple_modes[name])
      return
    elseif last == true then
      self:switch_insertion("in_body")
      return
    end
  end
  -- by default use in_body
  self:switch_insertion("in_body")
end


-- https://html.spec.whatwg.org/multipage/parsing.html#closing-elements-that-have-implied-end-tags
function HtmlParser:generate_implied_endtags(included, ignored)
  local included = included or implied_endtags
  -- parser can pass list of elements that should be removed from the "included" list
  local ignored = ignored or {}
  for _, name in ipairs(ignored) do included[name] = nil end
  local current = self:current_node() or {}
  -- keep removing elements while they are in the "included" list
  if included[current.tag] then
    self:pop_element()
    self:generate_implied_endtags(included, ignored)
  end
end

function HtmlParser:finish()
  -- tokenize without any real character
  self.codepoint = EOF
  self:tokenize(self.state)
  -- self:emit()
  self:add_text()
  -- close all unfinished elements
  if #self.unfinished == 0 then
    -- add implicit html tag
    self:start_tag("html")
  end
  while #self.unfinished > 0 do
    self:pop_element()
  end
  -- return root element
  return self.Document -- self:close_element()
end

-- 
M.Text       = Text
M.Element    = Element
M.HtmlParser = HtmlParser
M.HtmlStates = HtmlStates -- table with functions for particular parser states
M.self_closing_tags = self_closing_tags -- list of void elements
M.search_entity_tree = search_entity_tree
M.is_in_particular_scope = is_in_particular_scope
M.is_in_list_item_scope = is_in_list_item_scope
M.is_in_button_scope = is_in_button_scope
M.is_in_table_scope = is_in_table_scope
M.is_in_select_scope = is_in_select_scope

return M 

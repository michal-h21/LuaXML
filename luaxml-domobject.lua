--- DOM module for LuaXML
-- @module luaxml-domobject
-- @author Michal Hoftich <michal.h21@gmail.com
local dom = {}
local xml = require("luaxml-mod-xml")
local handler = require("luaxml-mod-handler")
local css_query = require("luaxml-cssquery")


local void = {area = true, base = true, br = true, col = true, hr = true, img = true, input = true, link = true, meta = true, param = true}

local escapes = {
  [">"] = "&gt;",
  ["<"] = "&lt;",
  ["&"] = "&amp;",
  ['"'] = "&quot;",
  ["'"] = "&#39;"
}

local function escape(search, text)
  return text:gsub(search, function(ch)
    return escapes[ch] or ""
  end)
end

local function escape_element(text)
  return escape("([<>&])", text)
end

local function escape_attr(text)
  return escape("([<>&\"'])", text)
end

local actions = {
  TEXT = {text = "%s"},
  COMMENT = {start = "<!-- ", text = "%s", stop = " -->"},
  ELEMENT = {start = "<%s%s>", stop = "</%s>", void = "<%s%s />"},
  DECL = {start = "<?%s %s?>"},
  DTD = {start = "<!DOCTYPE ", text = "%s" , stop=">"}
}

--- It serializes the DOM object back to the XML 
-- @param parser DOM object
-- @param current 
-- @param level
-- @param output
-- @return table
local function serialize_dom(parser, current,level, output)
  local output = output or {}
  local function get_action(typ, action)
    local ac = actions[typ] or {}
    local format = ac[action] or ""
    return format
  end
  local function insert(format, ...)
    table.insert(output, string.format(format, ...))
  end
  local function prepare_attributes(attr)
    local t = {}
    local attr = attr or {}
    for k, v in pairs(attr) do
      t[#t+1] = string.format("%s='%s'", k, escape_attr(v))
    end
    if #t == 0 then return "" end
    -- add space before attributes
    return " " .. table.concat(t, " ")
  end
  local function start(typ, el, attr)
    local format = get_action(typ, "start")
    insert(format, el, prepare_attributes(attr))
  end
  local function text(typ, text)
    local format = get_action(typ, "text")
    insert(format, escape_element(text))
  end
  local function stop(typ, el)
    local format = get_action(typ, "stop")
    insert(format,el)
  end
  local level = level or 0
  local spaces = string.rep(" ",level)
  local root= current or parser._handler.root
  local name = root._name or "unnamed"
  local xtype = root._type or "untyped"
  local text_content = root._text or ""
  local attributes = root._attr or {}
  -- if xtype == "TEXT" then
  --   print(spaces .."TEXT : " .. root._text)
  -- elseif xtype == "COMMENT" then
  --   print(spaces .. "Comment : ".. root._text)
  -- else
  --   print(spaces .. xtype .. " : " .. name)
  -- end
  -- for k, v in pairs(attributes) do
  --   print(spaces .. " ".. k.."="..v)
  -- end
  if xtype == "DTD" then
    text_content = string.format('%s %s "%s" "%s"', name, attributes["_type"],  attributes._name, attributes._uri )
    attributes = {}
  elseif xtype == "ELEMENT" and void[name] then
    local format = get_action(xtype, "void")
    insert(format, name, prepare_attributes(attributes))
    return output
  end

  start(xtype, name, attributes)
  text(xtype,text_content) 
  local children = root._children or {}
  for _, child in ipairs(children) do
    output = serialize_dom(parser,child, level + 1, output)
  end
  stop(xtype, name)
  return output
end

--- XML parsing function
-- Parse the XML text and create the DOM object. 
-- @return DOM_Object
local parse = function(xmltext)
  local domHandler = handler.domHandler()
  ---  @type DOM_Object
  local DOM_Object = xml.xmlParser(domHandler)
  -- preserve whitespace
  DOM_Object.options.stripWS = nil
  DOM_Object:parse(xmltext)
  DOM_Object.current = DOM_Object._handler.root
  DOM_Object.__index = DOM_Object
  DOM_Object.css_query = css_query()

  local function save_methods(element)
    setmetatable(element,DOM_Object)
    local children = element._children or {}
    for _, x in ipairs(children) do
      save_methods(x)
    end
  end
  local parser = setmetatable({}, DOM_Object)

  --- Returns root element of the DOM_Object 
  -- @return DOM_Object 
  function DOM_Object:root_node()
    return self._handler.root
  end


  --- Get current node type
  -- @param  el Optional node to get the type of
  function DOM_Object:get_node_type( el)
    local el = el or self
    return el._type
  end

  --- Test if the current node is an element.
  -- You can pass different element as parameter
  -- @return boolean
  function DOM_Object:is_element(el)
    local el = el or self
    return self:get_node_type(el) == "ELEMENT" -- @bool
  end

  
  --- Test if current node is text
  -- @return boolean
  function DOM_Object:is_text(el)
    local el = el or self
    return self:get_node_type(el) == "TEXT"
  end

  local lower = string.lower

  --- Return name of the current element
  -- @return string
  function DOM_Object:get_element_name( el)
    local el = el or self
    return el._name or "unnamed"
  end

  --- Get value of an attribute
  -- @return string
  function DOM_Object:get_attribute(name)
    local el = self
    if self:is_element(el) then
      local attr = el._attr or {}
      return attr[name]
    end
  end

  --- Set value of an attribute
  function DOM_Object:set_attribute( name, value)
    local el = self
    if self:is_element(el) then
      el._attr[name] = value
      return true
    end
  end
  

  --- Seriealize the current node back to XML
  function DOM_Object:serialize( current)
    local current = current
    -- if no current element is added and self is not plain parser object
    -- (_type is then nil), use the current object as serialized root
    if not current and self._type then
      current = self
    end
    return table.concat(serialize_dom(self, current))
  end


  --- Retrieve elements from the given path. 
  -- The path is list of elements separated with space,
  -- you must start from the root element
  -- @return table of elements which match the path
  function DOM_Object:get_path(path, current)
    local function traverse_path(path_elements, current, t)
      local t = t or {}
      if #path_elements == 0 then 
        -- for _, x in ipairs(current._children or {}) do
          -- table.insert(t,x)
        -- end
        table.insert(t,current)
        return t
      end
      local current_path = table.remove(path_elements, 1)
      for _, x in ipairs(self:get_children(current)) do
        if self:is_element(x) then
          local name = string.lower(self:get_element_name(x))
          if name == current_path then
            t = traverse_path(path_elements, x, t)
          end
        end
      end
      return t
    end
    local current = current or self:root_node() -- self._handler.root
    local path_elements = {}
    local path = string.lower(path)
    for el in path:gmatch("([^%s]+)") do table.insert(path_elements, el) end
    return traverse_path(path_elements, current)
  end

  --- Select elements chidlren using CSS selector syntax
  --
  function DOM_Object:query_selector(selector)
    local css_query = self.css_query
    local css_parts = css_query:prepare_selector(selector)
    return css_query:get_selector_path(self, css_parts)
  end

  --- Get table with children of the current element
  function DOM_Object:get_children(el)
    local el  = el or self
    local children = el._children or {}
    return children
  end

  --- Get the parent element
  function DOM_Object:get_parent( el)
    local el = el or self
    return el._parent
  end

  --- Execute function on the current element and all it's children elements
  function DOM_Object:traverse_elements( fn, current)
    local current = current or self --
    -- Following situation may happen when this method is called directly on the parsed object
    if not current:get_node_type() then
      current = self:root_node() 
    end
    local status = true
    if self:is_element(current) or self:get_node_type(current) == "ROOT"then
      local status = fn(current)
      -- don't traverse child nodes when the user function return false
      if status ~= false then
        for _, child in ipairs(self:get_children(current)) do
          self:traverse_elements(fn, child)
        end
      end
    end
  end

  --- Execute function on list of elements returned by DOM_Object:get_path()
  function DOM_Object:traverse_node_list( nodelist, fn)
    local nodelist = nodelist or {}
    for _, node in ipairs(nodelist) do
      for _, element in ipairs(node._children) do
        fn(element)
      end
    end
  end

  --- Replace the current node with new one
  function DOM_Object:replace_node(  new)
    local old = self
    local parent = self:get_parent(old)
    local id,msg = self:find_element_pos( old)
    if id then
      parent._children[id] = new
      return true
    end
    return false, msg
  end

  --- Add child node to the current node
  function DOM_Object:add_child_node( child)
    local parent = self
    child._parent = parent
    table.insert(parent._children, child)
  end


  --- Create copy of the current node
  function DOM_Object:copy_node( element)
    local element = element or self
    local t = {}
    for k, v in pairs(element) do
      if type(v) == "table" and k~="_parent" then
        t[k] = self:copy_node(v)
      else
        t[k] = v
      end
    end
    save_methods(t)
    return t
  end


  --- Create new element
  function DOM_Object:create_element( name, attributes, parent)
    local parent = parent or self
    local new = {}
    new._type = "ELEMENT"
    new._name = name
    new._attr = attributes or {}
    new._children = {}
    new._parent = parent
    save_methods(new)
    return new
  end

  --- Create new text node
  function DOM_Object:create_text_node( text, parent)
    local parent = parent or self
    local new = {}
    new._type = "TEXT"
    new._parent = parent
    new._text = text
    save_methods(new)
    return new
  end

  --- Delete current node
  function DOM_Object:remove_node( element)
    local element = element or self
    local parent = self:get_parent(element)
    local pos = self:find_element_pos(element)
    -- if pos then table.remove(parent._children, pos) end
    if pos then 
      -- table.remove(parent._children, pos) 
      parent._children[pos] = setmetatable({_type = "removed"}, DOM_Object)
    end
  end

  --- Find the element position in the current node list
  function DOM_Object:find_element_pos( el)
    local el = el or self
    local parent = self:get_parent(el)
    if not self:is_element(parent) and self:get_node_type(parent) ~= "ROOT" then return nil, "The parent isn't element" end
    for i, x in ipairs(parent._children) do
      if x == el then return i end
    end
    return false, "Cannot find element"
  end

  --- Get node list which current node is part of
  function DOM_Object:get_siblibgs( el)
    local el = el or self
    local parent = el:get_parent()
    if parent:is_element() then
      return parent:get_children()
    end
  end

  --- Get sibling node of the current node
  -- @param change Distance from the current node
  function DOM_Object:get_sibling_node( change)
    local el = self
    local pos = el:find_element_pos()
    local siblings = el:get_siblibgs()
    if pos and siblings then
      return siblings[pos + change]
    end
  end

  --- Get next node
  function DOM_Object:get_next_node( el)
    local el = el or self
    return el:get_sibling_node(1)
  end

  --- Get previous node
  function DOM_Object:get_prev_node( el)
    local el = el or self
    return el:get_sibling_node(-1)
  end


  -- include the methods to all xml nodes
  save_methods(parser._handler.root)
  -- parser:
  return parser
end

--- @export
return {
  parse = parse, 
  serialize_dom= serialize_dom
}

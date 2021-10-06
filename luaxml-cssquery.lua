--- CSS query module for LuaXML
-- @module luaxml-cssquery
-- @author Michal Hoftich <michal.h21@gmail.com
local parse_query = require("luaxml-parse-query")

-- the string.explode function is provided by LuaTeX
-- this is alternative for stock Lua
-- source: http://lua-users.org/wiki/SplitJoin
local function string_split(str, sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   str:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end

string.explode = string.explode or string_split

--- CssQuery constructor
-- @function cssquery
-- @return CssQuery object
local function cssquery()
  --- @type CssQuery
  local CssQuery = {}
  CssQuery.__index = CssQuery
  CssQuery.__debug = false
  CssQuery.querylist = {}

  function CssQuery.debug(self)
    self.__debug = true
  end

  function CssQuery:debug_print(text)
    if self.__debug then
      print("[CSS Object]: " .. text)
    end
  end
  --- Calculate CSS specificity of the query
  -- @param query table created by CssQuery:prepare_selector() function
  -- @return integer speficity value
  function CssQuery:calculate_specificity(query)
    local query = query or {}
    local specificity = 0
    for _, item in ipairs(query.query or {}) do
      for _, t in ipairs(item) do
        local key = t.key
      -- for key, value in pairs(item) do
        if key == "id" then
          specificity = specificity + 100
        elseif key == "tag" then
          specificity = specificity + 1
        elseif key == "any" then
          -- * has 0 specificity
        else
          specificity = specificity + 10
        end
      end
    end
    return specificity
  end

  -- save element position in the current siblings list
  local function make_nth(curr_el)
    local pos = 0
    local el_pos = 0
    local type_pos = 0
    -- get current node list
    local siblings = curr_el:get_siblings()
    if siblings then
      local parent = curr_el:get_parent()
      local element_types = {}
      for _, other_el in ipairs(siblings) do
        -- number the elements
        if other_el:is_element() then
          pos = pos + 1
          other_el.nth = pos
          -- save also element type, for nth-of-type and similar queries
          local el_name = other_el:get_element_name()
          local counter = (element_types[el_name] or 0) + 1
          other_el.type_nth = counter
          element_types[el_name] = counter
          -- save the current element position
          if other_el == curr_el then
            el_pos = pos
            type_pos = counter
          end
        end
      end
      -- save counter of element types
      parent.element_types = element_types
      -- save count of elements
      parent.child_elements = pos
    else
      return false
    end
    return el_pos, type_pos
  end

  local function test_first_child(el, nth)
    local el_pos = el.nth or make_nth(el)
    return el_pos == 1 
  end

  local function test_first_of_type(el, val)
    local type_pos = el.type_nth 
    if not type_pos then _, type_pos = make_nth(el) end
    return type_pos == 1
  end

  local function test_last_child(el, val)
    local el_pos = el.nth or make_nth(el)
    -- number of child elements is saved in the parent element
    -- by make_nth function
    local parent = el:get_parent()
    return el_pos == parent.child_elements
  end

  local function test_last_of_type(el, val)
    local type_pos = el.type_nth 
    if not type_pos then _, type_pos = make_nth(el) end
    -- get table with type counts in this sibling list
    local parent = el:get_parent()
    local element_types = parent.element_types or {}
    local type_count = element_types[el:get_element_name()]
    return type_pos == type_count 
  end

  -- test element for nth-child selector
  local function test_nth_child(el, nth)
    local el_pos = el.nth or make_nth(el)
    -- we support only the nth-child(number) form
    return el_pos == tonumber(nth)
  end

  -- test if element has attribute
  local function test_attr(el, attr)
    local result = el:get_attribute(attr)
    return result~=nil
  end

  local function test_any(el, value)
    -- * selector
    return true
  end

  -- test attribute values
  local function test_attr_value(el, parts)
    -- parts is a table: {attr_name, modifier, search value}
    local _, name, modifier, search = table.unpack(parts)
    local value = el:get_attribute(name)
    if value == nil then return false end
    -- make sure we deal with a string
    value = tostring(value)
    -- make the search string safe for pattern matching
    local escaped_search = search:gsub("([%(%)%.%%%+%–%*%?%[%^%$])", "%%%1")
    if modifier == "" then
      return value == search
    elseif modifier == "|" then
      -- attribute must be exactly the value or start with value + "-"
      return value == search or (value:match("^" .. escaped_search .. "%-")~=nil)
    elseif  modifier == "~" then
      -- test any word
      for word in value:gmatch("(%S+)") do
        if word == search then return true end
      end
      return false
    elseif modifier == "^" then
      -- value start 
      return value:match("^" .. escaped_search) ~= nil 
    elseif modifier == "$" then
      -- value ends
      return value:match(escaped_search .. "$") ~= nil 
    elseif modifier == "*" then
      -- value anywhere
      return value:match(escaped_search) ~= nil 
    end
  end

  --- Test prepared querylist
  -- @param domobj DOM element to test
  -- @param querylist [optional] List of queries to test
  -- @return table with CSS queries, which match the selected DOM element
  function CssQuery:match_querylist(domobj, querylist)
    local matches = {}
    -- querylist can be explicit, saved queries can be used otherwise
    local querylist = querylist or self.querylist

    local function test_part(key, value, el)
      -- print("testing", key, value, el:get_element_name())
      if key == "tag" then
        return el:get_element_name() == value
      elseif key == "id" then
        local id = el:get_attribute "id"
        return id and id == value
      elseif key == "class" then
        local class = el:get_attribute "class"
        if not class then return false end
        local c = {}
        for part in class:gmatch "([^%s]+)" do
          c[part] = true
        end
        return c[value] == true
      elseif key == "nth-child" then
        return test_nth_child(el, value)
      elseif key == "first-child" then
        return test_first_child(el, value)
      elseif key == "first-of-type" then
        return test_first_of_type(el, value)
      elseif key == "last-child" then
        return test_last_child(el, value)
      elseif key == "last-of-type" then
        return test_last_of_type(el, value)
      elseif key == "attr" then
        return test_attr(el, value)
      elseif key == "attr_value" then
        return test_attr_value(el, value)
      elseif key == "any" then
        return test_any(el, value)
      elseif key == "combinator" then
        -- ignore combinators in this function
      else
        if type(value) == "table" then value = table.concat(value, ":") end
        self:debug_print("unsupported feature", key, value)
        return false
      end
      -- TODO: Add more cases
      -- just return true for not supported selectors
      return true
    end

    local function test_object(query, el)
      -- test one object in CSS selector
      local matched = {}
      -- for key, value in pairs(query) do
      for _, part in ipairs(query) do
        local key, value = part.key, part.value
        local test =  test_part(key, value, el)
        if test~= true then return false end
        matched[#matched+1] = test
      end
      if #matched == 0 then return false end
      for k, v in ipairs(matched) do
        if v ~= true then return false end
      end
      return true
    end


    -- get next CSS selector
    local function get_next_selector(query)
      local query = query or {}
      local selector = table.remove(query)
      return selector 
    end

    local function get_next_combinator(query)
      local query = query or {}
      local combinator = " " -- default combinator
      local selector = query[#query] -- get the last item in selector query
      if not selector then return nil end
      -- detect if this selector is a combinator"
      -- combinator  object must have only one part, so we can assume that it is in the first part
      if selector and selector[1].key == "combinator"  then
        -- save the combinator and select next selector from the query  
        combinator = selector[1].value
        table.remove(query) -- remove combinator from query
      end
      return combinator
    end

    local function get_previous_element(el)
      -- try to find a previous element
      local prev = el:get_prev_node()
      if not prev then return nil end
      if prev:is_element() then return prev end
      return get_previous_element(prev)
    end


    local function match_query(query, el)
      local function match_parent(query, el)
        -- loop over the whole element tree and try to mach the css selector
        if el and el:is_element() then
          local query = query or {}
          local object = query[#query]
          local status = test_object(object, el)
          return status or match_parent(query, el:get_parent())
        else
          -- break processing if we reach top of the element tree
          return false
        end
      end
      local function match_sibling(query, el)
        -- match potentially more distant sibling
        if el and el:is_element() then
          return match_query(query, el) or match_query(query, get_previous_element(el))
        else
          return false
        end
      end
      local object = get_next_selector(query) -- get current object from the query stack
      if not object then return true end -- if the query stack is empty, then we can be sure that it matched previous items
      if not el or not el:is_element() then return false end -- if there is object to test, but current node isn't element, test failed
      local result = test_object(object, el)
      if result then
        local combinator = get_next_combinator(query) 
        if combinator == " " then
          -- we must traverse all parent elements to find if any matches
          return match_parent(query, el:get_parent())
        elseif combinator == ">" then -- simplest case, we need to match just the direct parent
          return match_query(query, el:get_parent())
        elseif combinator == "+" then -- match previous element
          return match_query(query, get_previous_element(el))
        elseif combinator == "~" then -- match all previous elements
          return match_sibling(query, get_previous_element(el))
        elseif combinator == nil then 
          return result
        end
      end
      return false
    end

    for _,element in ipairs(querylist) do
      local query =  {}
      for k,v in ipairs(element.query) do query[k] = v end
      if #query > 0 then -- don't try to match empty query
        local result = match_query(query, domobj)
        if result then matches[#matches+1] = element end
      end
    end
    return matches
  end

  --- Get elements that match the selector 
  -- @return table with DOM_Object elements
  function CssQuery:get_selector_path(
    domobj, -- DOM_Object 
    selectorlist -- querylist table created using CssQuery:prepare_selector 
    )
    local nodelist = {}
    domobj:traverse_elements(function(el)
      local matches = self:match_querylist(el, selectorlist)
      self:debug_print("Matching " ..  el:get_element_name() .." "..#matches)
      if #matches > 0 then nodelist[#nodelist+1] = el
      end
    end)
    return nodelist
  end

  --- Parse CSS selector to a query table.
  -- XML namespaces can be supported using
  -- namespace|element syntax
  --  @return table querylist
  function CssQuery:prepare_selector(
    selector -- string CSS selector query
    )
    local querylist = {}
    local function parse_selector(item)
      local query = {}
      -- for i = #item, 1, -1 do
      -- local part = item[i]
      for _, part in ipairs(item) do
        local t = {}
        for _, atom in ipairs(part) do
          
          local key = atom[1]
          local value
          if not atom[3] then
            value = atom[2]
          else
            -- save additional selector parts when available
            value = atom
          end
          -- support for XML namespaces in selectors
          -- the namespace should be added using "|" 
          -- like namespace|element
          if key=="tag" then 
            -- LuaXML doesn't support namespaces, so it is necessary
            -- to match namespace:element
            value=value:gsub("|", ":")
          end
          t[#t+1] = {key=key,  value=value}
        end
        query[#query + 1] = t
      end
      return query
    end
    -- for item in selector:gmatch("([^%s]+)") do
    -- elements[#elements+1] = parse_selector(item)
    -- end
    local parts = parse_query.parse_query(selector) or {}
    -- several selectors may be separated using ",", we must process them separately
    local sources = selector:explode(",")
    for i, part in ipairs(parts) do
      querylist[#querylist+1] = {query =  parse_selector(part), source = sources[i]}
    end
    return querylist
  end

  --- Add selector to CSS object list of selectors, 
  -- func is called when the selector matches a DOM object
  -- params is table which will be passed to the func
  -- @return integer number of elements in the prepared selector
  function CssQuery:add_selector(
    selector, -- CSS selector string
    func, -- function which will be executed on matched elements
    params -- table with parameters for the function
    )
    local selector_list = self:prepare_selector(selector)
    for k, query in ipairs(selector_list) do
      query.specificity = self:calculate_specificity(query)
      query.func = func
      query.params = params
      table.insert(self.querylist, query)
    end
    self:sort_querylist()
    return #selector_list
  end

  --- Sort selectors according to their specificity
  -- It is called automatically when the selector is added
  -- @return querylist table
  function CssQuery:sort_querylist(
    querylist -- [optional] querylist table
    )
    local querylist = querylist or self.querylist
    table.sort(self.querylist, function(a,b)
      return a.specificity > b.specificity
    end)
    return querylist
  end

  --- It tests list of queries agaings a DOM element and executes the
  --- coresponding function that is saved for the matched query.
  -- @return nothing
  function CssQuery:apply_querylist(
    domobj, -- DOM element
    querylist -- querylist table
    )
    for _, query in ipairs(querylist) do
      -- use default empty function which will pass to another match
      local func = query.func or function() return true end
      local params = query.params or {}
      local status = func(domobj, params)
      -- break the execution when the function return false
      if status == false then
        break
      end
    end
  end

  return setmetatable({}, CssQuery)
end

return cssquery

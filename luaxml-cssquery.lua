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
      for key, value in pairs(item) do
        if key == "id" then
          specificity = specificity + 100
        elseif key == "tag" then
          specificity = specificity + 1
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
    -- get current node list
    local siblings = curr_el:get_siblings()
    if siblings then
      for _, other_el in ipairs(siblings) do
        -- number the elements
        if other_el:is_element() then
          pos = pos + 1
          other_el.nth = pos
          -- save the current element position
          if other_el == curr_el then
            el_pos = pos
          end
        end
      end
    else
      return false
    end
    return el_pos
  end

  local function test_first_child(el, nth)
    local el_pos = el.nth or make_nth(el)
    return el_pos == 1 
  end

  -- test element for nth-child selector
  local function test_nth_child(el, nth)
    local el_pos = el.nth or make_nth(el)
    -- we support only the nth-child(number) form
    return el_pos == tonumber(nth)
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
      end
      -- TODO: Add more cases
      -- just return true for not supported selectors
      return true
    end

    local function test_object(query, el)
      -- test one object in CSS selector
      local matched = {}
      for key, value in pairs(query) do
        matched[#matched+1] = test_part(key, value, el)
      end
      if #matched == 0 then return false end
      for k, v in ipairs(matched) do
        if v ~= true then return false end
      end
      return true
    end

    local function match_query(query, el)
      local query = query or {}
      local object = table.remove(query) -- get current object from the query stack
      if not object then return true end -- if the query stack is empty, then we can be sure that it matched previous items
      if not el:is_element() then return false end -- if there is object to test, but current node isn't element, test failed
      local result = test_object(object, el)
      if result then
        return match_query(query, el:get_parent())
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
          local value = atom[2]
          -- support for XML namespaces in selectors
          -- the namespace should be added using "|" 
          -- like namespace|element
          if key=="tag" then 
            -- LuaXML doesn't support namespaces, so it is necessary
            -- to match namespace:element
            value=value:gsub("|", ":")
          end
          t[key] =  value
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

--- CSS query module for LuaXML
-- @module luaxml-cssquery
-- @author Michal Hoftich <michal.h21@gmail.com
local parse_query = require("luaxml-parse-query")


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
  function CssQuery.calculate_specificity(self, query)
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

  --- Test prepared querylist
  -- @param domobj DOM element to test
  -- @param querylist List of queries to test
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

  function CssQuery:get_selector_path(domobj, selectorlist)
    local nodelist = {}
    domobj:traverse_elements(function(el)
      local matches = self:match_querylist(el, selectorlist)
      self:debug_print("Matching " ..  el:get_element_name() .." "..#matches)
      if #matches > 0 then nodelist[#nodelist+1] = el
      end
    end)
    return nodelist
  end

  --- Parse CSS selector to match table
  function CssQuery:prepare_selector(selector)
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
  function CssQuery:add_selector(selector, func, params)
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
  function CssQuery:sort_querylist(querylist)
    local querylist = querylist or self.querylist
    table.sort(self.querylist, function(a,b)
      return a.specificity > b.specificity
    end)
    return querylist
  end

  --- Apply functions from a matched querylist to a DOM object 
  function CssQuery:apply_querylist(domobj, querylist)
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

--- @export {
return cssquery
--- }

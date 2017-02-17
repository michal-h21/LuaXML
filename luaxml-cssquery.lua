local query = require("luaxml-parse-query")
local function cssquery()
  local Parser = {}
  Parser.__index = Parser
  Parser.__debug = false

  function Parser.debug(self)
    self.__debug = true
  end

  function Parser.debug_print(self, text)
    if self.__debug then
      print("[CSS Object]: " .. text)
    end
  end
  function Parser.calculate_specificity(self, query)
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

  function Parser.match_querylist(self, domobj, querylist)
    local matches = {}
    local querylist = querylist

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

  function Parser.get_selector_path(self, domobj, selectorlist)
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
  function Parser.prepare_selector(self, selector)
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
    local parts = query.parse_query(selector) or {}
    -- several selectors may be separated using ",", we must process them separately
    for _, part in ipairs(parts) do
      querylist[#querylist+1] = {query =  parse_selector(part)}
    end
    return querylist
  end
  return setmetatable({}, Parser)
end

return cssquery

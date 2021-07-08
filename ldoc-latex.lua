local function escape(s)
  local escapes = {
    _ = "\\_{}",
    ["\\"] = "\\backspace{}"
  }
  -- only process strings
  if type(s) == "string" then
    s = s:gsub("%s+", " ")
    return s:gsub("([_\\])", function(a) return escapes[a] end)
  end
  return s
end

local function print_template(format, s)
  print(string.format(format, escape(s)))
end
local function print_module(mod)
  print_template("\\modulename{%s}", mod.mod_name)
  print_template("\\modulesummary{%s}", mod.summary)
  -- for k,v in pairs(mod.sections.by_name) do print("mod", k,v) end
end

local function print_class(mod, class, items)
  print_template("\\moduleclass{%s}", class)
  for _, item in ipairs(items) do

    local par = {}
    local map = item.params.map or {}
    for k,v in ipairs(item.params or {}) do
      par[#par+1] = escape(v)
    end
    print(string.format("\\functionname{%s}{%s}", escape(item.name), table.concat(par, ", ")))
    print_template("\\functionsummary{%s}", item.summary)
    for x,y in ipairs(item.params) do
      print(string.format("\\functionparam{%s}{%s}", escape(y), escape(map[y])))
      -- print(x,y)
    end
    for _, ret in ipairs(item.ret or {}) do
      print_template("\\functionreturn{%s}", ret)
    end
    -- print(string.format("\\functionreturn{%s}", escape(item.ret ) ))
  end

end

return {
  filter = function (t)
    local modules = {}
    for modid, mod in ipairs(t) do
      -- print basic information about module
      print_module(mod)
      local classes = {}
      for _, item in ipairs(mod.items) do
        if item.type == 'function' or item.type == "lfunction" then
          -- move functions to tables corresponding to their classes
          local curr_class = item.section
          if curr_class then
            local class = classes[curr_class] or {}
            class[#class+1] = item
            classes[curr_class] = class
          end
        end
      end
      for k,v in pairs(classes) do
        -- print class info and functions
        print_class(mod, k,v)
      end
    end
  end
}

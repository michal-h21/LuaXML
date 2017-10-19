local function escape(s)
  local escapes = {
    _ = "\\_{}"
  }
  return s:gsub("([_])", function(a) return escapes[a] end)
end

local function print_template(format, s)
  print(string.format(format, escape(s)))
end
local function print_module(mod)
  print_template("\\modulename{%s}", mod.mod_name)
  print_template("\\modulesummary{%s}", mod.summary)
  for k,v in pairs(mod.sections.by_name) do print("mod", k,v) end
end

local function print_class(mod, class, items)
  print_template("\\moduleclass{%s}", class)
  for _, item in ipairs(items) do

    local par = {}
    local map = item.params.map or {}
    for k,v in ipairs(item.params or {}) do
      par[#par+1] = escape(v)
    end
    print(string.format("\\functionname{%s}{%s}", escape(item.name), table.concat(par)))
    print_template("\\functionsummary{%s}", item.summary)
    for x,y in ipairs(item.params) do
      print(string.format("\\functionparam{%s}{%s}", escape(y), escape(map[y])))
      -- print(x,y)
    end
    print(string.format("\\functionreturn{%s}", item.ret ))
  end

end

return {
  filter = function (t)
    local modules = {}
    for modid, mod in ipairs(t) do
      print_module(mod)
      local classes = {}
      for _, item in ipairs(mod.items) do
        if item.type == 'function' then
          local curr_class = item.section
          if curr_class then
            local class = classes[curr_class] or {}
            class[#class+1] = item
            classes[curr_class] = class
          else
            -- print "Outside class"
          end
          -- print(mod.name,item.name,mod.file,item.lineno)
          local par = {}
          local map = item.params.map or {}
          for k,v in ipairs(item.params or {}) do
            -- print("parameter",k,v, map[v], map[k])
          end
          for k, v in pairs(item) do
            -- print ("item", k,v)
          end
          for k, v in pairs(item.modifiers or {}) do
            -- print("modifier", k,v)
            for _, yyy in pairs(v) do
              for x,y in pairs(yyy) do
                -- print("mod", x,y)
              end
            end
          end
          -- print("return",item.ret)
          -- print "----------"
        else
          -- print "***********"
          -- print(mod, item.type)
          -- print "***********"
        end
      end
      for k,v in pairs(classes) do
        print_class(mod, k,v)
        -- print("class", k, #v)
        -- if type(v) == "table" then
        -- for x,y in pairs(v) do
        -- print("", x,y)
        -- end
        -- end
      end
      -- for _,section in ipairs(mod.sections) do
      --   for k,v in pairs(section) do
      --     print("mod", k,v)
      --   end
      -- end
    end
  end
}

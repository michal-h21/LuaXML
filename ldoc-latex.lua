
return {
   filter = function (t)
     local modules = {}
      for modid, mod in ipairs(t) do
        local classes = {}
         for _, item in ipairs(mod.items) do
            if item.type == 'function' then
              local curr_class = item.section
              if curr_class then
                local class = classes[curr_class] or {}
                class[#class+1] = item
                classes[curr_class] = class
              else
                print "Outside class"
              end
               print(mod.name,item.name,mod.file,item.lineno)
               local par = {}
               local map = item.params.map or {}
               for k,v in ipairs(item.params or {}) do
                 print("parameter",k,v, map[v], map[k])
               end
               for k, v in pairs(item) do
                 print ("item", k,v)
               end
               for k, v in pairs(item.modifiers or {}) do
                 print("modifier", k,v)
               end
               print("return",item.ret)
               print "----------"
             else
               print "***********"
               print(mod, item.type)
               print "***********"
            end
         end
         for k,v in pairs(classes) do
           print("class", k, #v)
           if type(v) == "table" then
             for x,y in pairs(v) do
               print("", x,y)
             end
           end
         end
         for k,v in pairs(mod.sections[1]) do
           print("mod", k,v) 
         end
      end
   end
}

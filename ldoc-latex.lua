return {
   filter = function (t)
      for _, mod in ipairs(t) do
         for _, item in ipairs(mod.items) do
            if item.type == 'function' then
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
      end
   end
}

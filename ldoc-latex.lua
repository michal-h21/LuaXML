return {
   filter = function (t)
      for _, mod in ipairs(t) do
         for _, item in ipairs(mod.items) do
            if item.type == 'function' and not item.ret then
               print(mod.name,item.name,mod.file,item.lineno)
               local par = {}
               for k,v in pairs(item.params or {}) do
                 print("parameter",k,v)
               end
               for k, v in pairs(item) do
                 print ("item", k,v)
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

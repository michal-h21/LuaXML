return {
   filter = function (t)
      for _, mod in ipairs(t) do
         for _, item in ipairs(mod.items) do
            if item.type == 'function' and not item.ret then
               print(mod.name,item.name,mod.file,item.lineno)
            end
         end
      end
   end
}
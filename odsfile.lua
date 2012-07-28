module(...,package.seeall)
require "zip"
xmlparser = require ("xml-mod")
handler = require("handler-mod")

function load(filename)
  local p = {
    file = zip.open(filename),
    content_file_name = "content.xml",
    loadContent = function(self,filename)
      local treehandler = handler.simpleTreeHandler()
      local filename = filename or self.content_file_name  
      local xmlfile = self.file:open(filename)
      local text = xmlfile:read("*a")
      local xml = xmlparser.xmlParser(treehandler)
      xml:parse(text)
      return treehandler
    end
  }
  return p
end

function getTable(x,table_name)
  local tables = x.root["office:document-content"]["office:body"]["office:spreadsheet"]["table:table"]
  if #tables > 1 then
    if type(tables) == "table" and table_name ~= nil then 
        for k,v in pairs(tables) do
          if(v["_attr"]["table:name"]==table_name) then
            return v, k
          end 
        end
    elseif type(tables) == "table" and table_name == nil then
      return tables[1], 1  
    else 
      return tables  
    end
  else 
    return tables
  end
end

function tableValues(tbl,x1,y1,x2,y2)
  local t= {}
  if type(tbl["table:table-row"])=="table" then
    local rows = table_slice(tbl["table:table-row"],y1,y2)
    for k,v in pairs(rows) do
      local j = {}
      if #v["table:table-cell"] > 1 then
        local r = table_slice(v["table:table-cell"],x1,x2)
        for p,n in pairs(r) do
          table.insert(j,{value=n["text:p"],attr=n["_attr"]})
        end
      else
        local p = {value=v["table:table-cell"]["text:p"],attr=v["table:table-cell"]["_attr"]} 
        table.insert(j,p) 
      end  
      table.insert(t,j)
    end
  end
  return t
end

function getRange(range)
  local r = range:lower()
  local function getNumber(s)
    if s == "" or s == nil then return nil end
    local f,ex = 0,0
    for i in string.gmatch(s:reverse(),"(.)") do
      f = f + (i:byte()-96) * 26 ^ ex
      ex = ex + 1 
    end
    return f
  end
  for x1,y1,x2,y2 in r:gmatch("(%a*)(%d*):*(%a*)(%d*)") do
    return getNumber(x1),tonumber(y1),getNumber(x2),tonumber(y2) 
   --print(string.format("%s, %s, %s, %s",getNumber(x1),y1,getNumber(x2),y2))
  end
end

function table_slice (values,i1,i2)
  -- Function from http://snippets.luacode.org/snippets/Table_Slice_116
  local res = {}
  local n = #values
  -- default values for range
  i1 = i1 or 1
  i2 = i2 or n
  if i2 < 0 then
    i2 = n + i2 + 1
  elseif i2 > n then
    i2 = n
  end
  if i1 < 1 or i1 > n then
    return {}
  end
  local k = 1
  for i = i1,i2 do
    res[k] = values[i]
    k = k + 1
  end
  return res
end

function interp(s, tab)
  return (s:gsub('(-%b{})', function(w) return tab[w:sub(3, -2)] or w end))
end

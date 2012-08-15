module(...,package.seeall)

local inside = 0
function makeTag(s)
   local function makeTag(fuf)
     return fuf .. "[^>]*"
   end
   local print = texio.write_nl
   if inside > 0 then print ("inside "..inside) else print("outside") end
   --[[if inside then
     return s .. "[^>]*"
   else
     inside = true--]]	   
     inside = inside + 1
     local f = "<"..s.."[^>]*>"
     inside = inside - 1
     return f
   --end
end
function matchTag(tg)
   return makeTag(tg)
end

function matchDescendand(a,b)
   return makeTag(a)..makeTag(b)
end

function matchChild(a,b)
   return makeTag(a)..".*"..makeTag(b)
end

function matchSibling(a,b)
   return a .. "[^>]*".."@%("..b.."[^>]*%)"
end

function matchClass(tg,class)
   return tg.."[^>]*class=[|]*[^>]*|"..class.."[^>]*|"
end

function matchId(tg,id)
   return tg.."[^>]*id="..id	
end
matcher = {}

function makeElement(s)
  local function makeTag(fuf)
    return fuf .. "[^>]*"
  end
  return "<"..s .. "[^>]*>"
end

function matcher.new()
  local self =  {}
  local selectors={}
  function self:addSelector(sel,val)
     selectors[sel.."$"] = val
  end
  function self:testPath(path,fn)
    for k, v in pairs(selectors) do
       if path:match(k) then
         fn(v)
       end
    end
  end
  return self
end


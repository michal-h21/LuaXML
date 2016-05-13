--module(...,package.seeall)

local M =  {}
local inside = 0
local function makeTag(s)
   local function makeTag(fuf)
     return fuf .. "[^>]*"
   end
   local print = texio.write_nl
   -- if inside > 0 then print ("inside "..inside) else print("outside") end
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

M.makeTag = makeTag
local function matchTag(tg)
   return makeTag(tg)
end
M.matchTag=matchTag
local function matchDescendand(a,b)
   return makeTag(a)..makeTag(b)
end
M.matchDescendand = matchDescendand

local function matchChild(a,b)
   return makeTag(a)..".*"..makeTag(b)
end
M.matchChild = matchChild

local function matchSibling(a,b)
   return a .. "[^>]*".."@%("..b.."[^>]*%)"
end
M.matchSibling = matchSibling

local function matchClass(tg,class)
   return tg.."[^>]*class=[|]*[^>]*|"..class.."[^>]*|"
end

M.matchClass = matchClass
local function matchId(tg,id)
   return tg.."[^>]*id="..id	
end
M.matchId = matchId
local matcher = {}
M.matcher= matcher
local function makeElement(s)
  local function makeTag(fuf)
    return fuf .. "[^>]*"
  end
  return "<"..s .. "[^>]*>"
end

M.makeElement = makeElement
function matcher.new()
  local self =  {}
  local selectors={}
  function self:addSelector(sel,val)
     selectors[sel.."$"] = val
  end
  function self:testPath(path,fn)
    for k, v in pairs(selectors) do
       print("regex", k)
       if path:match(k) then
         fn(v)
       end
    end
  end
  return self
end


local t = matcher.new()
t:addSelector(matchTag("p"),"ahoj p")
t:addSelector(matchClass(".*", "ahoj"), "ahoj class")
t:testPath("<p class=|ahoj|>", print)
return M

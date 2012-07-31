module(...,package.seeall)


function makeTag(s)
   return "<"..s.."[^>]*>"
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
   return makeTag(a .. "[^>]*".."@%("..b.."[^>]*%)")
end

function matchClass(tg,class)
   return makeTag(tg.."[^>]*class=[|]*[^>]*|"..class.."[^>]*|")
end
matcher = {}
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


require "busted.runner" ()
kpse.set_program_name "luatex"

local dom = require "luaxml-domobject"

local cssquery = require "luaxml-cssquery"

local obj = cssquery()
obj:debug()

describe("CSS selector handling", function()
  local selector = "div#pokus span.ahoj, p, div.ahoj:first-child"
  local objects = obj:prepare_selector(selector)
  it("should parse selectors", function()
    assert.same(#objects, 3)
  end)
  it("should calculate specificity", function()
    assert.same(obj:calculate_specificity(objects[1]),  112)
  end)
  local document = [[
  <html>
  <body>
  <div class="ahoj" id="pokus">
  <span>first child</span>
  <span class="ahoj">Pokus</span>
  <p>Uff</p>
  <b>Something different</b>
  </div>
  </body>
  </html>
  ]]
  local newobj = dom.parse(document)
  local matchedlist = obj:get_selector_path(newobj, objects)
  it("should get selector path",function()
    assert.same(#matchedlist, 3)
  end)
  describe("List selectors that matches object", function()
    obj:add_selector(".ahoj", function(domobj)
      return false
    end)
    obj:add_selector("#pokus", function(domobj)
      return false
    end)
    for k,v in ipairs(obj.selectors) do
      print(k, v.source, v.specificity)
    end
  end)
  -- assert.truthy(#obj:prepare_selector(selector)==2)
end)

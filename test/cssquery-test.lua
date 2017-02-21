require "busted.runner" ()
kpse.set_program_name "luatex"

local dom = require "luaxml-domobject"

local cssquery = require "luaxml-cssquery"

local obj = cssquery()
-- obj:debug()

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
    -- this should match two elements with "ahoj" class
    obj:add_selector(".ahoj", function(domobj)
      domobj:set_attribute("style", "color:green")
      return false
    end)
    -- but the one with "pokus" id should block to use the class match
    obj:add_selector("#pokus", function(domobj)
      domobj:set_attribute("style", "color:red")
      return false
    end)
    -- Rule for #pokus should be first in the selectors list
    it("Automatic specificity sorting should work", function()
      assert.same(obj.querylist[1].specificity, 100)
    end)
    local span_ahoj = newobj:query_selector "span.ahoj" [1]
    local div_ahoj  = newobj:query_selector "div.ahoj" [1]
    it("query_selector should work", function()
      assert.same(span_ahoj:get_element_name(), "span")
      assert.same(div_ahoj:get_element_name(), "div")
    end)
    it("Saved query matches should work", function()
      assert.same(#obj:match_querylist(span_ahoj), 1)
      -- should match .ahoj and #pokus 
      assert.same(#obj:match_querylist(div_ahoj), 2)
    end)
    it("Applying querylist should work", function()
      local div_querylist = obj:match_querylist(div_ahoj)
      obj:apply_querylist(div_ahoj, div_querylist)
      assert.same(div_ahoj:get_attribute("style"), "color:red")
    end)
    -- for k,v in ipairs(obj.querylist) do
    --   print(k, v.source, v.specificity)
    -- end
  end)
  -- assert.truthy(#obj:prepare_selector(selector)==2)
end)

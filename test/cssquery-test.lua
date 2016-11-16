require "busted.runner" ()
kpse.set_program_name "luatex"

local dom = require "luaxml-domobject"

local cssquery = require "luaxml-cssquery"

local obj = cssquery()

describe("CSS selector handling", function()
  local selector = "div#pokus span.ahoj, p, div.ahoj:first-child"
  local objects = obj:prepare_selector(selector)
  it("should parse selectors", function()
    assert.truthy(#objects == 3)
  end)
  it("should calculate specificity", function()
    assert.truthy(obj:calculate_specificity(objects[1]) == 112)
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
    assert.truthy(#matchedlist == 3)
  end)
  -- assert.truthy(#obj:prepare_selector(selector)==2)
end)

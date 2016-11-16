require "busted.runner" ()
kpse.set_program_name "luatex"

local dom = require "luaxml-domobject"

local cssquery = require "luaxml-cssquery"

local obj = cssquery()

describe("CSS selector handling", function()
  local selector = "div#pokus span.ahoj, p, div.ahoj:first-child"
  local objects = obj:prepare_selector(selector)
  assert.truthy(#objects == 3)
  assert.truthy(obj:calculate_specificity(objects[1]) == 112)
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
  local matchedlist = newobj:get_selector_path(objects)
  assert.truthy(#matchedlist == 3)
  -- assert.truthy(#obj:prepare_selector(selector)==2)
end)

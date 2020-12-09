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
    it("Any selector should work", function()
      local div_any = newobj:query_selector("div *")
      local body_any = newobj:query_selector("body *")
      local body_direct_any = newobj:query_selector("body > *")
      assert.same(#div_any, 4)
      assert.same(#body_any, 5)
      assert.same(#body_direct_any, 1)
    end)
    -- for k,v in ipairs(obj.querylist) do
    --   print(k, v.source, v.specificity)
    -- end
  end)
  -- assert.truthy(#obj:prepare_selector(selector)==2)
end)

describe("pseudo-classes", function()
local  sample = [[
<data>
  <items>
    <item>foo</item>
    <item>bar</item>
    <item>baz</item>
    <another>last</another>
  </items>
</data>
]]
local nth = [[
data
items
item:nth-child(2)
]]

local first = "item:first-child"
local dom = dom.parse(sample)
local css = cssquery()

css:add_selector(nth, function(obj)
   assert.equal(obj:get_text(), "bar")
end)

css:add_selector(first, function(obj)
  assert.equal(obj:get_text(), "foo")
end)

css:add_selector("items :last-child", function(obj)
  assert.equal(obj:get_text(), "last")
end)

-- this shouldn't  match
local last_item_matched = false
-- item is not last child, ite element't doesn't exist
css:add_selector("item:last-child, ite :last-child", function(obj)
  last_item_matched = true
end)


it("Should match pseudo classes", function()
  dom:traverse_elements(function(el)
    local querylist = css:match_querylist(el)
    css:apply_querylist(el, querylist)
  end)
  assert.equal(last_item_matched, false)
end)
end)

describe("attribute selectors", function()
local sample = [[
<p>
  <a href="#hello">link to hello</a>
  <span id="hello">hello</span>
  <span lang="cs-CZ">czech text</span>
  <span class="hello world">test word</span>
  <span id="verylongword">test start</span>
</p>
]]
local dom = dom.parse(sample)
local css = cssquery()

local function asserttext(obj, text)
  assert.equal(obj:get_text(), text)
end
css:add_selector("a[href]", function(obj) asserttext(obj, "link to hello")  end)
css:add_selector("[id='hello']", function(obj) asserttext(obj, "hello")  end)
css:add_selector("[lang|='cs']", function(obj) asserttext(obj, "czech text") end)
css:add_selector("[class~='world']", function(obj) asserttext(obj, "test word") end)
css:add_selector("[id^='very']", function(obj) asserttext(obj, "test start") end)
css:add_selector("[id$='word']", function(obj) asserttext(obj, "test start") end)
css:add_selector("[id*='long']", function(obj) asserttext(obj, "test start") end)
it("Should match attributes", function()
  dom:traverse_elements(function(el)
    local querylist = css:match_querylist(el)
    css:apply_querylist(el, querylist)
  end)
end)

end)

describe("combinators", function()
local sample = [[
<p>
  <span id="hello">hello</span>
  <a href="#hello">link to hello</a>
  <span lang="cs-CZ">czech text</span>
  <span class="hello world">test word</span>
  <b>child content <i>ignore this</i></b> 
  <span id="verylongword">test start</span>
</p>
]]

local dom = dom.parse(sample)
local css = cssquery()

-- test how many span elements match the sibling combinator
local number_of_spans = 0
css:add_selector("a ~ span", function(obj)
  number_of_spans = number_of_spans + 1
end)

css:add_selector("b + span", function(obj)
  print("sibling", obj:get_text())
end)

css:add_selector("p i", function(obj)
  print("deep child", obj:get_text())
end)

it("Should match combinators", function()
  dom:traverse_elements(function(el)
    local querylist = css:match_querylist(el)
    css:apply_querylist(el, querylist)
  end)
  print("matched spans", number_of_spans)
end)

end)

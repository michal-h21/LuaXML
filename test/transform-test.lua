require "busted.runner" ()
kpse.set_program_name "luatex"

local domobject = require "luaxml-domobject"
local transform = require "luaxml-transform"

describe("Basic DOM functions", function() 
  local transformer1 = transform.new()
  local transformer2 = transform.new()
  local text="<b>hello</b>"
  transformer1:add_action("b", "transform1: %s")
  transformer2:add_action("b", "transform2: %s")
  it("should do basic transformations", function()
    assert.same("transform1: hello", transformer1:parse_xml(text))
  end)
  it("should support multiple tranformer objects", function()
    assert.same("transform2: hello", transformer2:parse_xml(text))
  end)
end)

describe("Transform DOM object", function()
  local transformer = transform.new()
  local dom = domobject.parse  [[<section>hello <b>world</b></section>]]
  transformer:add_action("section", "sect: %s")
  transformer:add_action("b", "b: %s")
  it("should transform dom object", function()
    assert.same("sect: hello b: world", transformer:process_dom(dom))
  end)
end)

describe("selectors support", function()
  local transformer = transform.new()
  local dom1 = domobject.parse  [[<x>hello <b>world</b></x>]]
  local dom2 = domobject.parse  [[<v>hello <b>world</b></v>]]
  local dom3 = domobject.parse  [[<v>hello <b class="hello">world</b></v>]]
  local dom4 = domobject.parse  [[<v>hello <b id="id">world</b></v>]]


  transformer:add_action("x b", "xb: %s")
  transformer:add_action("v b", "vb: %s")
  transformer:add_action(".hello", "hello: %s")
  transformer:add_action("#id", "id: %s")
  it("should support css selectors", function()
    assert.same("hello xb: world", transformer:process_dom(dom1))
    assert.same("hello vb: world", transformer:process_dom(dom2))
    assert.same("hello hello: world", transformer:process_dom(dom3))
    assert.same("hello id: world", transformer:process_dom(dom4))
  end)

end)


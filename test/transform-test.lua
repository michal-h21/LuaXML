require "busted.runner" ()
kpse.set_program_name "luatex"

local dom = require "luaxml-domobject"
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

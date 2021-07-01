require "busted.runner" ()
kpse.set_program_name "luatex"

local dom = require "luaxml-domobject"
local transform = require "luaxml-transform"

describe("Basic DOM functions", function() 
  local text="<b>hello</b>"
  transform.add_action("b", "transform1: %s")
  it("should do basic transformations", function()
    assert.same("transform1: hello", transform.parse_xml(text))
  end)

  
end)

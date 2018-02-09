require "busted.runner" ()
kpse.set_program_name "luatex"
local entities = require "luaxml-entities"

describe("Entities decoding should work",function()
  local decode = entities.decode
  it("should parse named entities", function()
    assert.same(decode("&amp;"), "&")
    assert.same(decode("&lt"), "<")
    assert.same(decode("&QUOT;"), '"')
    assert.same(decode("&NewLine;"), "\n")
  end)
  it("should parse decimal entities", function()
    print(decode("&#64;"))
    assert.same(decode("&#64;"), "@")
  end)

end)

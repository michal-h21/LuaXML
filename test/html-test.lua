require "busted.runner" ()
kpse.set_program_name "luatex"
local html = require "luaxml-mod-html"

-- debugging function
local function print_tree(node, indent)
  local indent = indent or 0
  print(string.rep(" ",indent*2) .. tostring(node))
  for _, child in ipairs(node.children) do
    print_tree(child, indent + 1)
  end
end


local HtmlParser = html.HtmlParser


local function get_html(text)
  -- parse text to html 
  local p = HtmlParser:init(text)
  return p:parse()
end

local function get_first_element(text)
  -- helper function that returns first element
  local tree = get_html(text)
  return tree.children[1]
end

describe("Basic features", function()
  local first = get_first_element('<p title="<!-- this is a comment-->">Test 1</p>')
  it("Element should be table", function()
    assert.same(type(first), "table")
  end)
  it("tostring should serialize element to HTML tag", function()
   assert.same(tostring(first), '<p title="<!-- this is a comment-->">')
   local selfclosing = get_first_element("<img src='hello.jpg' />")
   assert.same(tostring(selfclosing), '<img src="hello.jpg" />')
   local doublequotes = get_first_element('<img alt="hello \'world\'">')
   -- this img is not self closing
   assert.same(tostring(doublequotes), '<img alt="hello \'world\'">')
 end)
  

end)


describe("Test attribute parsing", function()
 it("Should handle comments in attribute values", function()
  local first = get_first_element('<p title="<!-- this is a comment-->">Test 1</p>')
  local attributes = first.attr
  assert.same(#attributes, 1)
  assert.same(attributes[1].name, "title")
  assert.same(attributes[1].value, "<!-- this is a comment-->")
 end)
 it("Should handle funky comments", function()
   local first = get_first_element("<p title=<!this-comment>Test 2</p>")
   assert.same(first.attr[1].value, "<!this-comment")
 end)

end)


-- local p = HtmlParser:init("  <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
local p = HtmlParser:init("<html><HEAD><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
-- local p = HtmlParser:init("Hello <čau> text, hello <img src='hello \"quotes\"' alt=\"sample <worldik> 'hello'\" id=image title=<!this-comment /> image")
-- local p = HtmlParser:init("<i>Hello <čau> text</i>")
local dom = p:parse()
print_tree(dom)


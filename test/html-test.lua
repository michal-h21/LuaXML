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

-- local p = HtmlParser:init("  <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
local p = HtmlParser:init("<html><HEAD><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
-- local p = HtmlParser:init("Hello <čau> text, hello <img src='hello \"quotes\"' alt=\"sample <worldik> 'hello'\" id=image title=<!this-comment /> image")
-- local p = HtmlParser:init("<i>Hello <čau> text</i>")
local dom = p:parse()
print_tree(dom)


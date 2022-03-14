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

local function get_first_children(text)
  -- helper function that returns first element
  local tree = get_html(text)
  local first = tree.children[1] or {}
  local children = first.children or {}
  return children[1]
end


describe("Basic features", function()
  local first = get_first_element('<p title="<!-- this is a comment-->">Test 1</p>')
  it("Element should be table", function()
    assert.same(type(first), "table")
    assert.same(first._type, "element")
  end)
  it("tostring should serialize element to HTML tag", function()
   assert.same(tostring(first), '<p title="<!-- this is a comment-->">')
   local selfclosing = get_first_element("<img src='hello.jpg' />")
   assert.same(tostring(selfclosing), '<img src="hello.jpg" />')
   local doublequotes = get_first_element('<img alt="hello \'world\'">')
   -- this img is not self closing
   assert.same(tostring(doublequotes), '<img alt="hello \'world\'">')
 end)
 it("shouldn't parse elements starting with nonalpha characters", function()
   local cau = get_first_element("<čau>")
   assert.same(cau._type, "text")
   assert.same(cau.text, "<čau>")
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
   local first = get_first_element("<p title='hello>world'>")
   assert.same(first.attr[1].value, "hello>world")

 end)

end)

describe("Test entities", function()
  it("Should find named entities", function()
    local amp = html.search_entity_tree {"a","m","p"}
    assert.same(type(amp), "table")
    assert.same(amp.char, "&")
    -- this entity doesn't exist
    local random = html.search_entity_tree {"r", "a", "n", "d", "o","m"}
    assert.same(type(random), "nil")
  end)
  it("Should support named entites", function()
    -- support named entites
    local first  = tostring(get_first_element("Hello &lt; world"))
    assert.same(first, "'Hello < world'")
    -- return unknown named entites as text
    local second = tostring(get_first_element("Hello &nonexistent; world"))
    assert.same(second, "'Hello &nonexistent; world'")
    -- match partial named entites
    -- &amp is translated to &, rest is returend as text
    local third  = tostring(get_first_element("hello &amperesand; world"))
    assert.same(third, "'hello &eresand; world'")
    -- in attribute values, &amp isn't matched 
    local fourth = tostring(get_first_element("<img alt='hello &amperesand; world'>"))
    assert.same(fourth, '<img alt="hello &amperesand; world">')
    -- but &amp; is
    local fifth  = tostring(get_first_element("<img alt='hello &amp; world'>"))
    assert.same(fifth, '<img alt="hello & world">')
    -- and &amp should be too
    local sixth  = tostring(get_first_element("<img alt='hello &amp world'>"))
    assert.same(sixth, '<img alt="hello & world">')
    -- just return & 
    local seventh = tostring(get_first_element("<img alt='hello & world'>"))
    assert.same(seventh, '<img alt="hello & world">')
    -- support entities, where names match only partly
    local notit = tostring(get_first_element("I'm &notit; I tell you"))
    assert.same(notit, "'I'm ¬it; I tell you'")
    -- &notin; is named entity
    local notin = tostring(get_first_element("I'm &notin; I tell you"))
    assert.same(notin, "'I'm ∉ I tell you'")
    -- &no; is nothing
    local no = tostring(get_first_element("I'm &no; I tell you"))
    assert.same(no, "'I'm &no; I tell you'")
  end)
  it("Should support numeric entities", function()
    local hexa    = tostring(get_first_element("hello &#x40;"))
    assert.same(hexa, "'hello @'")
    local ccaron = tostring(get_first_element("&#x010D"))
    assert.same(ccaron, "'č'")
    local wrong_hexa = tostring(get_first_element("hello &#xh0;"))
    assert.same(wrong_hexa, "'hello &#xh0;'")
    local strange_hexa = tostring(get_first_element("hello &#x40č"))
    assert.same(strange_hexa, "'hello @č'")
    local decimal = tostring(get_first_element("hello &#64;"))
    assert.same(decimal, "'hello @'")
    local fourth = tostring(get_first_element("<img alt='hello &#x40 world'>"))
    assert.same(fourth,'<img alt="hello @ world">')
    local replaced_character =  tostring(get_first_element("hello &#x80;"))
    assert.same(replaced_character, "'hello €'")
  end)
end)

describe("Comments and other specials", function()
  it("Should convert XML processing instructions to comments", function()
    -- convert XML processing instruction to comment
    local pi = tostring(get_first_element('<?xml-stylesheet type="text/css" href="style.css"?>'))
    assert.same(pi, '<!--xml-stylesheet type="text/css" href="style.css"?-->')
  end)
  it("Should support comments", function()
    local comment = tostring(get_first_element('<!-- text in --! comment ---!>'))
    assert.same(comment, '<!-- text in --! comment --->')
    local nested_comment = tostring(get_first_element("<!-- <!-- nested --> -->"))
    assert.same(nested_comment, "<!-- <!-- nested -->")
  end)
  it("Should support doctype", function()
    local doctype = tostring(get_first_element('<!doctype html>'))
    assert.same(doctype, "<!DOCTYPE html>")
    local xhtml = tostring(get_first_element('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'))
    assert.same(xhtml,'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">')
  end)
  it("Should support cdata", function()
    local cdata = tostring(get_first_element('<![CDATA[ Within this Character Data block I can use double dashes as much as I want (along with <, &, \', and ") *and* %MyParamEntity; will be expanded to the text "Has been expanded" ... however, I can\'t use the CEND sequence. If I need to use CEND I must escape one of the brackets or the greater-than sign using concatenated CDATA sections.  ]]>'))
    -- CDATA are transformed to comments
    assert.same(cdata, '<!--[CDATA[ Within this Character Data block I can use double dashes as much as I want (along with <, &, \', and ") *and* %MyParamEntity; will be expanded to the text "Has been expanded" ... however, I can\'t use the CEND sequence. If I need to use CEND I must escape one of the brackets or the greater-than sign using concatenated CDATA sections.  ]]-->')
    -- but cdata in XML should be transformed to text
    local cdata = tostring(get_first_children("<math xmlns='http://www.w3.org/1998/Math/MathML'><![CDATA[Hello CDATA]]></math>"))
    assert.same(cdata, "'Hello CDATA'")
  end)
end)

describe("Special scope detection", function()
  it("Should support basic scoping", function()
    -- we cannot just parse HTML, because it has closed unfinished table,
    -- so we just recreate similar strcture to test scoping
    local element = html.Element
    local html_el = element:init("html", {})
    local body = element:init("body", {})
    local p = element:init("p", {})
    local span = element:init("span", {})
    local caption = element:init("caption", {})
    local caption = element:init("table", {})

    local x = {unfinished = {html, body, p, span}}
    assert.truthy(html.is_in_button_scope(x, "p"))
    -- b is not in scope
    assert.falsy(html.is_in_button_scope(x, "b"))
    -- caption is in list of elemetns which should return false for the scoping function
    local notp = {unfinished = {html, body, p, table, caption, span}}
    assert.falsy(html.is_in_button_scope(notp, "p"))
    -- table scope ignores only table, template and html
    -- assert.falsy(html.is_in_table_scope(notp, "table"))
    -- <table> is child of p, so the is_in_table_scope returns false before it matches <p>
    assert.falsy(html.is_in_table_scope(notp, "p"))
  end)
end)


describe("Parse special elements", function()
  -- local p = HtmlParser:init("<title>hello <world> &amp'</title>")
  -- local p = HtmlParser:init("<style type='text/css'>p > a:before{xxxx: 'hello <world> &amp';}</STYLE>")
  -- local p = HtmlParser:init("<script><!-- if(a<2){let x=3;} else {print('</section>');}</SCRIPT>")
  print "***************************************"
  local p = HtmlParser:init(
  -- [[<!DOCTYPE html>
  -- Before
  -- <script>"<script>"</script>
  -- fine
  -- <script>"<!--"</script>
  -- still fine
  -- <script>"<!--<a>"</script>
  -- fine again
  -- <script>"<!--<script>"</script>
  -- Won't print
  [[<script>
    <!--    //hide from non-JS browsers
      function doSomething() {
        var coolScript = "<script>" + theCodeICopied + "</script>";
        document.write(coolScript);
      }
      // And if you forget to close your comment here, things go funnny
      -->
  </script>]])
  local dom = p:parse()
  print_tree(dom)

end)

local p = HtmlParser:init("  <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
-- local p = HtmlParser:init("<html><HEAD><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><h1>This is my webpage &amp;</h1><img src='hello' />")
-- local p = HtmlParser:init("Hello <čau> text, hello <img src='hello \"quotes\"' alt=\"sample <worldik> 'hello'\" id=image title=<!this-comment /> image")
-- local p = HtmlParser:init("<i>Hello <čau> text</i>")
local dom = p:parse()
print_tree(dom)


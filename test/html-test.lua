require "busted.runner" ()
kpse.set_program_name "luatex"
local html = require "luaxml-mod-html"
local encodings = require "luaxml-encodings"

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


-- helper function that will convert HTML text to DOM, and rebuild unfinished list
local function dom_with_unfinished(text)
  local p = HtmlParser:init(text)
  p:parse()
  local function reconstruct(children)
    if children then
      for _,child in ipairs(children.children) do
        if child.tag then
          table.insert(p.unfinished, child)
          reconstruct(child)
          return true
        end
      end
    end
  end
  reconstruct(p.Document)
  return p
end


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
  it("Should generate implied endtags", function()
    local dom = dom_with_unfinished("<html><body><div><p>")
    assert.same(#dom.unfinished, 4)
    dom:generate_implied_endtags()
    assert.same(#dom.unfinished, 3)
    local dom = dom_with_unfinished("<html><body><div><p><b>")
    -- don't close anything in this case, because current node is not <p>
    dom:generate_implied_endtags()
    assert.same(#dom.unfinished, 5)
  end)
end)

local function build_simple_tree(str, options)
  -- build simple DOM using string like html/body/p/b
  local tree = HtmlParser:init("")
  tree:parse()
  local options = options or {}

  -- local tree = {unfinished = {}}
  for tag in str:gmatch("([^/]+)") do
    local element = html.Element
    table.insert(tree.unfinished, element:init(tag, {}))
  end
  -- allow setting of extra options
  for k,v in pairs(options) do
    -- print(k,tree[k], v)
    tree[k] = v
  end
  return tree
end

describe("Insertion mode switching", function()
  local function get_insertion_node(path, options)
    local dom = build_simple_tree(path, options)
    dom:reset_insertion_mode()
    return dom.insertion_mode
  end
  it("Should handle select", function()
    assert.same(get_insertion_node("html/body/select"), "in_select")
    assert.same(get_insertion_node("html/body/table/select"), "in_select_in_table")
  end)
  it("Should handle table elements", function()
    assert.same(get_insertion_node("html/body/table/tr/td"), "in_cell")
    assert.same(get_insertion_node("html/body/table/tr/th/span"), "in_cell")
    assert.same(get_insertion_node("html/body/table/tr"), "in_row")
    assert.same(get_insertion_node("html/body/table/thead"), "in_table_body")
    assert.same(get_insertion_node("html/body/table"), "in_table")
  end)
  it("Should handle head", function()
    assert.same(get_insertion_node("html/head", {head_pointer = nil}), "before_head")
    assert.same(get_insertion_node("html/head", {head_pointer = true}), "after_head")
  end)
  it("Should handle body", function()
    assert.same(get_insertion_node("html/body/p"), "in_body")
    assert.same(get_insertion_node("p"), "in_body")
  end)

end)

describe("Test 8-bit text encoding handling", function()
  it("Should find text encoding in HTML", function()
    local text = [[<!doctype html>
    <html lang="cs" class="css-d" itemscope itemtype="https://schema.org/NewsArticle">
    <head>
        <meta charset="windows-1250">
        <meta http-equiv="cache-control" content="no-cache">
     ]]
     assert.same(encodings.find_html_encoding(text), "windows-1250")
     local text = [[<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
             "http://www.w3.org/TR/html4/loose.dtd">
             <html lang="cs">
             <head>
              <title>Technomorous - Čtvrtá grafika pro Blackbird</title>
                <meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-2">]]
     -- encodings are always lowercase, even if they were specified as uppercase in HTML
     assert.same(encodings.find_html_encoding(text), "iso-8859-2")
  end)
  it("Should translate characters to utf-8", function()
    -- construct text with diacritics in windows-1250 encoding
    local text = string.char(232, 237, 158)
    local mapping = encodings.load_mapping("windows-1250")
    assert.table(mapping)
    -- convert windows-1250 text to utf-8
    assert.same(encodings.recode(text, mapping), "číž")

  end)
end)

describe("Parse special elements", function()
  -- local p = HtmlParser:init("<title>hello <world> &amp'</title>")
  -- local p = HtmlParser:init("<style type='text/css'>p > a:before{xxxx: 'hello <world> &amp';}</STYLE>")
  -- local p = HtmlParser:init("<script><!-- if(a<2){let x=3;} else {print('</section>');}</SCRIPT>")
  -- this doesn't parse correctly
  local p = HtmlParser:init(
  [[<!DOCTYPE html>
  Before
  <script>"<script>"</script>
  fine
  <script>"<!--"</script>
  still fine
  <script>"<!--<a>"</script>
  fine again
  <script>"<!--<script>"</script>
  Won't print
  [[<script>
    <!--    //hide from non-JS browsers
      function doSomething() {
        var coolScript = "<script>" + theCodeICopied + "</script>";
        document.write(coolScript);
      }
      // And if you forget to close your comment here, things go funnny
  </script>]])
  local dom = p:parse()
  -- print_tree(dom)
  -- for k,v in pairs(dom.children) do
  --   print(k,v)
  -- end
  local trim = function(text) 
    local str = text.text
    return str:gsub("^%s*", ""):gsub("%s*$", "") 
  end

  assert.same(trim(dom.children[2]), "Before")
  assert.same(trim(dom.children[4]), "fine")
  assert.same(trim(dom.children[6]), "still fine")
  assert.same(trim(dom.children[8]), "fine again")
  -- print(dom.children[3])

end)


describe("Parse unclosed and wrongly nested elements", function()

  local p = HtmlParser:init("  <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1.0,user-scalable=yes'></head><body><p>this is uncloded paragraph <h1>This is my webpage &amp; <h2>nested header</h2></h1><p><img src='hello' /><p>another paragraph")
  local dom = p:parse()

  local html, head, body
  -- print_tree(dom)
  it("should create a correct dom", function()
    assert.same(type(dom.children), "table")
    -- there should be space, doctype and <html>
    assert.same(#dom.children, 3)
    html = dom.children[3]
    assert.same(html.tag, "html")
  end)
  it("should parse unclosed and wrongly nested tags", function()
    local head = html.children[1]
    local body = html.children[2]
    assert.same(head.tag, "head")
    -- only <meta> should be a child
    assert.same(#head.children, 1)
    assert.same(body.tag, "body")
    assert.same(#body.children, 5)
    assert.same(body.children[1].tag, "p")
    assert.same(body.children[2].tag, "h1")
    assert.same(body.children[3].tag, "h2")
    assert.same(body.children[4].tag, "p")
    assert.same(body.children[4].children[1].tag, "img")
    assert.same(body.children[5].tag, "p")
  end)
  it("should parse lists", function()
    local p = HtmlParser:init "<!doctype html><html><head></head><body><p>this is uncloded paragraph <ul><li>hello<li>another<ol><li>this is nested list</ol></ul><ol><li>"
    local dom = p:parse()
    -- print_tree(dom)
    local html = dom.children[2]
    assert.same(type(html), "table")
    assert.same(html.tag, "html")
    local body = html.children[2]
    assert.same(body.tag, "body")
    local ul = body.children[2]
    assert.same(ul.tag, "ul")
    assert.same(#ul.children, 2)
    local second li = ul.children[2]
    assert.same(li.tag, "li")
    local ol = li.children[2]
    assert.same(ol.tag, "ol")
    assert.same(#ol.children, 1)
    -- test that the last <ol> is child of body
    local last_ol = body.children[3]
    assert.same(last_ol.tag, "ol")
  end)
  it("should parse mismatched tags", function()
    local p = HtmlParser:init "<!doctype html><html><head></head><body><p><b>bold text <i>italic text</b> bold again"
    local dom = p:parse()
    -- print_tree(dom)
    local html = dom.children[2]
    assert.same(type(html), "table")
    assert.same(html.tag, "html")
    local body = html.children[2]
    assert.same(body.tag, "body")
    local  p = body.children[1]
    assert.same(p.tag, "p")
    local b = p.children[1]
    assert.same(b.tag, "b")
    assert.same(#b.children, 3)
    assert.same(b.children[1].text, "bold text ")
    assert.same(b.children[2].tag, "i")
    assert.same(b.children[3].text, " bold again")
  end)
end)


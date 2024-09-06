require "busted.runner" ()
kpse.set_program_name "luatex"

local dom = require "luaxml-domobject"

describe("Basic DOM functions", function() 
  local document = [[
  <html>
  <head><title>pokus</title></head>
  <body>
  <h1>pokus</h1>
  <p>nazdar</p>
  <br>
  <br />
  </body>
  </html>
  ]]

  local obj = dom.parse(document)
  it("It should parse XML", function()
    assert.same(type(obj), "table")
    assert.truthy(obj:root_node())
  end)

  it("Path retrieving should work", function()
    local path = obj:get_path("html body")
    assert.truthy(path)
    assert.same(#path,  1)
    assert.truthy(path[1]:is_element())
    assert.same(#path[1]:get_children(),  9)
  end)

  describe("Node traversing should work", function()
    it("Should get all nodes", function()
      local t = {}
      obj:traverse(function(node)
        t[#t+1] = node
      end)
      assert.same(#t, 21)
    end)
    it("Should get stripped strings", function()
      assert.same(#obj:stripped_strings(), 3)
    end)
    it("Should get all strings", function()
      assert.same(#obj:strings(),12)
    end)
  end)

 
  describe("Basic DOM traversing should work", function()
    local matched = false
    local count = 0
    obj:traverse_elements(function(el)
      count = count + 1
      if obj:get_element_name(el) == "p" then
        matched = true
        it("Element matching should work", function()
          assert.same(el:root_node():get_node_type(), "ROOT")
          assert.truthy(el:is_element())
          assert.same(el:get_element_name(), "p")
        end)
        it("Node serializing should work", function()
          local p_serialize = el:serialize()
          assert.same(p_serialize, "<p>nazdar</p>")
        end)
        it("Adding text elements should work", function()
          local newtext = el:create_text_node(" světe")
          el:add_child_node(newtext)
          assert.same(el:serialize(), "<p>nazdar světe</p>")
        end)
        el:remove_node(el)
      end
    end)
    it("Traverse should find 7 elements and match one <p>", function()
      assert.truthy(matched)
      assert.same(count, 9)
    end)
  end)

  describe("Modified DOM object serializing", function()
    local serialized = obj:serialize()
    assert.truthy(serialized)
    assert.same(type(serialized), "string")
    assert.truthy(serialized:match("<html>"))
    assert.is_nil(serialized:match("<p>"))
  end)


  describe("Query selector matching should work", function()
    local document = [[
    <html>
    <head><title>pokus</title></head>
    <body>
    <h1>pokus</h1>
    <p>nazdar</p>
    <p class="noindent">First noindent</p>
    <p class="noindent another-class">Second noindent</p>
    </body>
    </html>
    ]]
    local newobj = dom.parse(document)
    local matched = newobj:query_selector(".noindent")
    it("Should return table", function()
      assert.same(type(matched), "table")
    end)
    it("Should match two elemetns", function()
      assert.same(#matched, 2)
    end)
    local el = matched[2]
    it("Should be possible to add new elements to the matched elements",function()
      local text = newobj:create_text_node(" with added text")
      el:add_child_node(text)
      assert.same(el:serialize(),'<p class=\'noindent another-class\'>Second noindent with added text</p>')
    end)
    
  end)
  describe("Text retrieving should work", function()
    local document = [[
    <html>
    <body>
    <h1>pokus</h1>
    <p class="noindent">First <span class="hello">noindent</span>
some another text. More <b>text</b>.
    </p>
    </body>
    </html>
    ]]
    local newobj = dom.parse(document)
    local matched = newobj:query_selector(".noindent")
    it("Should return table", function()
      assert.same(type(matched), "table")
    end)
    it("Should have one element", function()
      assert.same(#matched, 1)
    end)
    local par = matched[1]
    local text = par:get_text()
    it("Should return element's text content", function()
      assert.truthy(text:match( "First noindent\nsome another text. More text."))
    end)
  end)
  describe("Handling of void elements", function()
    local test_metas = function(metas, msg)
      it(msg, function()
        assert.same(type(metas), "table")
        assert.same(#metas, 2)
      end)
    end

    local document = [[
    <html>
    <head>
    <meta name="sample" content="meta" />
    <meta name="hello" content="world">
    </head>
    </html>
    ]]
    local newobj = dom.parse(document)
    local metas = newobj:query_selector("meta")
    test_metas(metas,"Should match two meta elements")
    -- test configuration of void elements
    local second = [[
    <root>
    <meta>Hello</meta>
    <meta>world</meta>
    </root>
    ]]
    local newobj = dom.parse(second, {})
    local metas = newobj:query_selector("meta")
    test_metas(metas,"Should support configuration of the void elements")
  end)
  describe("Inner HTML", function()
    local document = [[
    <html><p>hello</p>
    </html>
    ]]
    local newdom = dom.html_parse(document)
    local p = newdom:query_selector("p")[1]
    -- insert inner_html as XML
    p:inner_html("hello <b>this</b> should be the new content", true)
    it("Should support inner_html", function()
      local children = p:get_children()
      assert.same(#children, 3)
      assert.truthy(children[1]:is_text())
      assert.same(children[1]._text,"hello ")
      assert.truthy(children[2]:is_element())
      assert.same(children[2]._name,"b")
      -- now insert inner_html as HTML
      p:inner_html("hello <b>this</b> should be the new content")
      children = p:get_children()
      assert.same(#children, 3)
    end)
    local text = [[ 
    <html><p>hello, <b>here <i>are some</i> tags</b></p>
    </html>
    ]]
    local newdom = dom.html_parse(text)
    local b = newdom:query_selector("b")[1]
    it("Should support insert_before_begin", function()
      b:insert_before_begin("here <x>are more tags</x>")
      local siblings = b:get_siblings()
      local pos = b:find_element_pos()
      assert.same(siblings[pos - 2]._text, "here ")
      assert.same(siblings[pos - 1]._name, "x")
    end)
    it("Should support insert_after_end", function()
      b:insert_after_end(", here are even <y>more</y> tags")
      local siblings = b:get_siblings()
      local pos = b:find_element_pos()
      assert.same(siblings[pos + 1]._text, ", here are even ")
      assert.same(siblings[pos + 2]._name, "y")
    end)
    it("Should support insert_after_begin", function()
      b:insert_after_begin("try <i>even</i> more, ")
      local children = b:get_children()
      assert.same(children[1]._text, "try ")
      assert.same(children[2]._name, "i")
    end)
    it("Should support insert_before_end", function()
      b:insert_before_end(", some <i>tags</i> at the end")
      local children = b:get_children()
      assert.same(children[#children-1]._name, "i")
      assert.same(children[#children]._text, " at the end")
    end)

  end)

end)

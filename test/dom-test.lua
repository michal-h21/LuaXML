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

end)

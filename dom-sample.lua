--kpse.set_program_name("luatex")
function traverseDom(parser, current,level)
	local level = level or 0
        local spaces = string.rep(" ",level)
	local root= current or parser._handler.root
	local name = root._name or "unnamed"
	local xtype = root._type or "untyped"
	local attributes = root._attr  or {} 
	if xtype == "TEXT" then 
		print(spaces .."TEXT : " .. root._text)
	else	 
		print(spaces .. xtype .. " : " .. name) 
	end
	for k, v in pairs(attributes) do
		print(spaces .. "  ".. k.."="..v)
	end
	local children = root._children or {}
	for _, child in ipairs(children) do
		traverseDom(parser,child, level + 1)
	end
end

local xml = require('luaxml-mod-xml')
local handler = require('luaxml-mod-handler')
local x = '<p>hello <a href="http://world.com/">world</a>, how are you?</p>'
local domHandler = handler.domHandler()
local parser = xml.xmlParser(domHandler)
parser:parse(x)
traverseDom(parser)

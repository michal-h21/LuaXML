lua_content = $(wildcard luaxml-*.lua) 
tex_content = $(wildcard *.tex)
tests       = $(wildcard test/*.lua)

name = luaxml
VERSION:= $(shell git --no-pager describe --abbrev=0 --tags --always )
DATE := $(firstword $(shell git --no-pager show --date=short --format="%ad" --name-only))
doc_file = luaxml.pdf
TEXMFHOME = $(shell kpsewhich -var-value=TEXMFHOME)
INSTALL_DIR = $(TEXMFHOME)/scripts/lua/$(name)
MANUAL_DIR = $(TEXMFHOME)/doc/latex/$(name)
SYSTEM_BIN = /usr/local/bin
BUILD_DIR = build
BUILD_LUAXML = $(BUILD_DIR)/$(name)
API_DOC = doc/api.tex
API_SOURCES = luaxml-domobject.lua luaxml-cssquery.lua luaxml-transform.lua
LDOC_FILTER = ldoc-latex.lua
LDOC = ldoc --all --filter ldoc-latex.filter
ENTITIES_SOURCE = data/entities.json
ENTITIES_MODULE = luaxml-namedentities.lua

all: doc $(ENTITIES_MODULE)

.PHONY: test 

doc: api $(doc_file) 

	
$(doc_file): $(name).tex $(API_DOC) $(ENTITIES_MODULE)
	latexmk -pdf -pdflatex='lualatex "\def\version{${VERSION}}\def\gitdate{${DATE}}\input{%S}"' $(name).tex

api: $(API_DOC)

$(API_DOC): $(API_SOURCES) $(LDOC_FILTER)
	mkdir -p doc
	$(LDOC) luaxml-domobject.lua > $(API_DOC)
	$(LDOC) luaxml-cssquery.lua  >> $(API_DOC)
	$(LDOC) luaxml-transform.lua >> $(API_DOC)

$(ENTITIES_MODULE): $(ENTITIES_SOURCE) data/jsontolua.lua
	lua data/jsontolua.lua < $< > $(ENTITIES_MODULE)

test: 
	texlua test/dom-test.lua
	texlua test/cssquery-test.lua
	texlua test/entities-test.lua
	texlua test/transform-test.lua

build: $(ENTITIES_MODULE) doc test $(lua_content) 
	@rm -rf build
	@mkdir -p $(BUILD_LUAXML)
	@cp $(lua_content) $(tex_content)  $(doc_file) $(ENTITIES_MODULE) $(BUILD_LUAXML)
	@cat README | sed -e "s/{{VERSION}}/${VERSION}/" | sed -e "s/{{DATE}}/${DATE}/" >  $(BUILD_LUAXML)/README
	@cat luaxml.tex | sed -e "s/{{VERSION}}/${VERSION}/" >  $(BUILD_LUAXML)/luaxml.tex
	@cd $(BUILD_DIR) && zip -r luaxml.zip luaxml

install: doc $(lua_content) $(filters)
	mkdir -p $(INSTALL_DIR)
	mkdir -p $(MANUAL_DIR)
	cp  $(doc_file) $(MANUAL_DIR)
	cp $(lua_content) $(INSTALL_DIR)

version:
	echo $(VERSION), $(DATE)


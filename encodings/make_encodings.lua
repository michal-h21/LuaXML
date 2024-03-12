-- this file should generate Lua module with mappings between 8-bit encodings and UTF-8
-- source of encoding files: https://encoding.spec.whatwg.org/#legacy-single-byte-encodings
-- each encoding starts at value of 128 - first 127 characters are the same as ASCII
local lfs = require "lfs" 

-- insert replacement char at empty fields
local replacement_char = utf8.char(0xFFFD)

local function load_enc(filename)
  local enc = {}
  local i = 0
  local last_pos 
  for line in io.lines(filename) do
    local pos, uni_char = line:match("^%s*(%d+)%s*0x(%x+)")
    if pos then
      pos = tonumber(pos)
      if i < pos then
        for x = i, pos - 1 do
          enc[#enc+1] = replacement_char
        end
        i = pos
      end
      enc[#enc+1] = utf8.char(tonumber(uni_char, 16))
      i = i + 1
      last_pos = pos
    end
  end
  return table.concat(enc)
end

local dir = "encodings"

local encodings = {}
local named_encodings = {}
for file in lfs.dir(dir) do
  local curr_enc = file:match("^index%-(.-)%.txt")
  if curr_enc then
    local encoding = load_enc(dir .. "/" .. file)
    encodings[#encodings+1] = {
      name = curr_enc,
      encoding = encoding
    }
    named_encodings[curr_enc] = encoding
  end
end

if arg[1] then
  -- try to translate from the encoding given in the argument to utf-8"
  local enc = named_encodings[arg[1]]
  if not enc then 
    print("unknown encoding", arg[1])
    os.exit()
  end
  -- prepare mapping from 8-bit chars to UTF-8
  local mapping = {}
  local i = 128
  for pos, charpoint in utf8.codes(enc) do
    mapping[i] = utf8.char(charpoint)
    i = i + 1
  end
  -- read testing string from stdin
  local str = io.read("*all")
  -- convert string
  local newstr = str:gsub("(.)", function(char)
    local charpoint = string.byte(char)
    if charpoint > 127 then
      print(char, charpoint, mapping[charpoint])
      return mapping[charpoint]
    else
      return false
    end
  end)
  print(newstr)

else
  print "return {"

  for k,v in ipairs(encodings) do
    print(v.name .. " = '" .. v.encoding .. "'")
  end

  print "}"
end

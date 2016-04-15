local c = require('lexer').load("css")
local src = [[
<!--
@import "my-styles{.css";

@media max-width: 30em{
  body{color:red;}
}
.sample, #another{
  font-style:italic;
}
/* Komentář */
-->
]] 
local tokens = c:lex(src) 

local start = 1
for i = 1, #tokens, 2 do
  local t, len = tokens[i], tokens[i+1]
  print(t,len, src:sub(start, len-1))
  start = len
end

-- Source: https://github.com/leafo/web_sanitize
-- Author: Leaf Corcoran
local R, S, V, P
do
  local _obj_0 = require("lpeg")
  R, S, V, P = _obj_0.R, _obj_0.S, _obj_0.V, _obj_0.P
end
local C, Cs, Ct, Cmt, Cg, Cb, Cc, Cp
do
  local _obj_0 = require("lpeg")
  C, Cs, Ct, Cmt, Cg, Cb, Cc, Cp = _obj_0.C, _obj_0.Cs, _obj_0.Ct, _obj_0.Cmt, _obj_0.Cg, _obj_0.Cb, _obj_0.Cc, _obj_0.Cp
end
local alphanum = R("az", "AZ", "09")
local num = R("09")
local quotes = S("'\"") ^ 1
local white = S(" \t\n") ^ 0
-- this is a deviation from the upstream, we allow "|" in the tag name, because
-- luaxml doesn't support XML namespaces and elements must be queried using
-- dom:query_selector("namespace|element")
local word = (alphanum + S("_-") + S("|")) ^ 1
local attr_word = (alphanum + S("_-") + S("|:")) ^ 1

local combinators = S(">~+")

local attr_name = (alphanum + S("_-:")) ^ 1
local attr_function = S("~|^$*") ^ 0

local attr_content = C((P(1) - quotes) ^ 1)
local mark
mark = function(name)
  return function(...)
    return {
      name,
      ...
    }
  end
end
local parse_query
parse_query = function(query)
  local tag = word / mark("tag")
  local cls = P(".") * (word / mark("class"))
  local id = P("#") * (word / mark("id"))
  local any = P("*") / mark("any")
  local nth = P(":nth-child(") * C(num ^ 1) * ")" / mark("nth-child")
  local first = P(":first-child") / mark("first-child")
  local first_of_type = P(":first-of-type") / mark("first-of-type")
  local last = P(":last-child") / mark("last-child")
  local last_of_type = P(":last-of-type") / mark("last-of-type")
  local attr = P("[") * C(attr_word) * P("]") / mark("attr")
  local attr_value = P("[") * C(attr_name ) * C(attr_function)* P("=") * quotes * attr_content * quotes * P("]") / mark("attr_value")
  local combinator = C(combinators) / mark("combinator")
  local selector = Ct((any + nth + first + first_of_type + last + last_of_type + tag + cls + id + attr + attr_value + combinator) ^ 1)
  local pq = Ct(selector * (white * selector) ^ 0)
  local pqs = Ct(pq * (white * P(",") * white * pq) ^ 0)
  pqs = pqs * (white * -1)
  return pqs:match(query)
end
return {
  parse_query = parse_query
}

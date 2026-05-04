-- Plain strings, escapes, line comments, and long brackets.
local plain = "hello\nworld"
local quoted = 'single quoted'
local block = [=[
line one
line two
]=]
--[==[
The parser should skip this whole long comment.
]==]

return plain .. quoted .. block

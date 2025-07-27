local cases = {
'bitwise.lua',
'bwcoercion.lua',
'constructs.lua',
'events.lua',
'math.lua',
'strings.lua',
'tpack.lua',
'utf8.lua',
'vararg.lua',
}

for i = 1, #cases do
  local file = cases[i]
  print("Running test case: " .. file)
  dofile(file)
    print("Test case " .. file .. " completed successfully.")
end
-- LLVM pipeline test: closure with string constants
-- Regression: closures must have their constant table wired
local function check(x)
  if x == 42 then
    print("pass")
  else
    print("fail")
  end
end
check(42)

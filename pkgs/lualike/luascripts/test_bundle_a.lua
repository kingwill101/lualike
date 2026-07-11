-- Test the bundler: module A requires module B
local B = require("test_bundle_b")
print("A loaded, B says:", B)

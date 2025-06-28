local co = coroutine.wrap(function()
    assert(not pcall(table.sort, { 1, 2, 3 }, coroutine.yield))
    assert(coroutine.isyieldable())
    coroutine.yield(20)
    return 30
end)

first_result = co()
second_result = co()
print("first_result:", first_result)
print("second_result:", second_result)

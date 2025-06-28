local co = coroutine.wrap(function()
    return pcall(pcall, pcall, pcall, pcall, pcall, pcall, pcall, error, "hi")
end)

result = { co() }
print(result[1], result[2], result[3], result[4], result[5], result[6], result[7], result[8], result[9])

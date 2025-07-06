local x = '"\225lo"\n\\'
result = string.format('%q%s', x, x)
print(result)
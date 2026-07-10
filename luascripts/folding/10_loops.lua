-- Loop unrolling correctness and instruction comparison
local sum = 0
for i = 1, 3 do
    sum = sum + i
end
print("sum 1..3 =", sum)

-- Nested constant loops
local matrix = 0
for x = 1, 2 do
    for y = 1, 3 do
        matrix = matrix + x * y
    end
end
print("matrix sum =", matrix)

-- Const-variable bounds
local N <const> = 4
local total = 0
for i = 1, N do
    total = total + i * 10
end
print("total 1..4*10 =", total)

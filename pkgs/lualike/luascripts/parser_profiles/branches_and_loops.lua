local total = 0

for i = 1, 6 do
  if i % 2 == 0 then
    total = total + i
  elseif i == 3 then
    total = total + 30
  else
    total = total - 1
  end
end

while total < 60 do
  total = total + 7
end

repeat
  total = total - 3
until total < 50

return total

local alpha = 0x1p+4 + 12.5e-1
local beta = ((alpha * 3) // 2) % 7
local gamma = not false and (beta >= 0 or alpha < 0)

return alpha, beta, gamma, nil

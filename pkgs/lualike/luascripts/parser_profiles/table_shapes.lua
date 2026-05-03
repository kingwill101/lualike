local data = {
  name = "profile",
  values = {1, 2, 3, 4},
  nested = {
    ["with space"] = true,
    [{1, 2, 3}] = "table-key",
  },
}

data.values[#data.values + 1] = 5
return data.name, data.values[5], data.nested["with space"]

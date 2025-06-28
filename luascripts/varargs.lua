function format(template, ...)
    print("format", #...)
    return string.format(template, ...)
end

function printAll(...)
    print("printAll", #...)
    return format("Count: %d, First: %s", select("#", ...), select(1, ...))
end

local result = printAll("A", "B", "C")
print("this is the result", result)

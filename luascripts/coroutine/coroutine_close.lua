-- ok to close a dead coroutine
co = coroutine.create(print)
assert(coroutine.resume(co, "testing 'coroutine.close'"))
assert(coroutine.status(co) == "dead")
close_result, close_msg = coroutine.close(co)

-- also ok to close it again
second_close_ok, second_close_msg = coroutine.close(co)

-- cannot close the running coroutine
main_close_ok, main_close_error = pcall(coroutine.close, coroutine.running())

-- cannot close a "normal" coroutine
normal_close_error = nil
;
(coroutine.wrap(function()
    local ok, msg = pcall(coroutine.close, coroutine.running())
    normal_close_error = msg
end))()

print("normal close results: " .. tostring(close_result) .. " " .. " normal close message: " .. tostring(normal_close_error))
print("main_close_error: " .. tostring(main_close_error) )

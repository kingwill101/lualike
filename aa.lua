    local obj = {x = 42}
        function obj:foo(...)
          return self.x, select('#', ...), ...
        end
        local sx, n, a, b = obj:foo(10, 20)


        print(sx)
        print(n)
        print(a)
        print(b)
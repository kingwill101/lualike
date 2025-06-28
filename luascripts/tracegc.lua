local M = {}

        M.status = "inactive"

        function M.start()
          M.status = "active"
          return "GC tracing started"
        end

        -- Add a property method
        M.property = function(propName)
          return "TracerProperty: " .. propName
        end

        return M
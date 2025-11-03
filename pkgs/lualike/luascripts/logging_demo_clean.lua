-- Enhanced Logging Library Demo (Clean Output)
-- Demonstrates all features without verbose internal logging

print("=== Enhanced Logging Library Demo ===\n")

-- Enable logging at INFO level (less verbose than DEBUG)
logging.enable("INFO")

print("1. Basic logging at different levels:")
logging.info("This is an info message")
logging.warning("This is a warning message")
logging.error("This is an error message")

print("\n2. Logging with a single category:")
logging.info("Processing user request", {category = "HTTP"})

print("\n3. Logging with multiple categories:")
logging.info("Database query completed", {
  categories = {"Database", "Performance"}
})

print("\n4. Logging with structured context data:")
logging.info("API request processed", {
  category = "API",
  method = "POST",
  endpoint = "/users",
  status = 201,
  duration_ms = 45
})

print("\n5. Logging with nested context:")
logging.warning("Slow database query detected", {
  categories = {"Database", "Performance"},
  query = "SELECT * FROM users WHERE active = true",
  duration_ms = 5000,
  metadata = {
    connection_id = "conn_123",
    pool_size = 10,
    active_connections = 8
  }
})

print("\n6. Category filtering - only show 'Security' logs:")
logging.set_categories({"Security"})
logging.info("This won't show (App)", {category = "App"})
logging.info("Login attempt detected", {category = "Security", user = "admin"})
logging.info("This also won't show (Database)", {category = "Database"})

print("\n7. Reset filters to show all categories again:")
logging.reset_filters()
logging.info("Now all categories show again", {category = "App"})

print("\n8. Level filtering - only show WARNING and above:")
logging.set_level("WARNING")
logging.info("This info won't show")
logging.warning("This warning will show", {category = "Test"})
logging.error("This error will show", {category = "Test"})

print("\n9. Complex real-world example:")
logging.reset_filters()
logging.set_level("INFO")

local function process_user_request(user_id, action)
  logging.info("Processing user request", {
    categories = {"API", "User"},
    user_id = user_id,
    action = action,
    timestamp = os.time()
  })
  
  -- Simulate database query
  local query_time = 123
  
  if query_time > 100 then
    logging.warning("Slow query detected", {
      categories = {"Database", "Performance"},
      query_time_ms = query_time,
      threshold_ms = 100,
      optimization_needed = true
    })
  end
  
  logging.info("Request completed successfully", {
    categories = {"API", "User"},
    user_id = user_id,
    success = true
  })
end

process_user_request(42, "update_profile")

print("\n10. Check logging state:")
print("Logging enabled:", logging.is_enabled())
local level = logging.get_level()
if level then
  print("Current level:", level)
else
  print("No level filter set")
end

print("\n11. Disable logging:")
logging.disable()
print("Logging enabled:", logging.is_enabled())
logging.info("This won't show - logging disabled")

print("\n=== Demo Complete ===")


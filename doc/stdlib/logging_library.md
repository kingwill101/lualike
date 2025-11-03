# Enhanced Logging Library

The lualike logging library provides powerful structured logging capabilities powered by the `contextual` package. It supports multiple log levels, categories, and rich context data.

## Features

- **Multiple log levels**: debug, info, warning, error
- **Category tagging**: Single or multiple categories per log
- **Structured context**: Attach arbitrary key-value data to logs
- **Flexible filtering**: Filter by level and/or categories
- **Zero overhead when disabled**: Logging calls are no-ops when disabled

## Configuration Functions

### `logging.enable(level?)`

Enable logging with an optional minimum level.

```lua
logging.enable()          -- Enable at DEBUG level
logging.enable("INFO")    -- Enable at INFO level
logging.enable("WARNING") -- Enable at WARNING level
```

**Levels** (from most to least verbose):
- `"DEBUG"`, `"FINE"`, `"FINER"`, `"FINEST"` → debug level
- `"INFO"`, `"CONFIG"` → info level  
- `"WARNING"`, `"SEVERE"` → warning level
- `"ERROR"` → error level
- `"CRITICAL"`, `"ALERT"`, `"EMERGENCY"`, `"SHOUT"` → higher severity

### `logging.disable()`

Disable all logging output.

```lua
logging.disable()
```

### `logging.is_enabled()`

Check if logging is currently enabled.

```lua
if logging.is_enabled() then
  print("Logging is on")
end
```

### `logging.set_level(level)`

Set the minimum log level threshold.

```lua
logging.set_level("WARNING")  -- Only show WARNING and above
logging.set_level("ERROR")    -- Only show ERROR and above
```

### `logging.get_level()`

Get the current log level filter, or nil if none set.

```lua
local level = logging.get_level()
if level then
  print("Current level:", level)
end
```

### `logging.set_category(category)`

Filter logs to show only a specific category.

```lua
logging.set_category("HTTP")    -- Only show HTTP logs
logging.set_category(nil)       -- Clear filter
```

### `logging.set_categories(categories)`

Filter logs to show only specified categories (any-match).

```lua
logging.set_categories({"HTTP", "Database", "API"})
-- Shows logs with HTTP OR Database OR API category
```

### `logging.reset_filters()`

Clear all category and level filters.

```lua
logging.reset_filters()
```

## Logging Functions

All logging functions accept:
1. **message** (required): The log message string
2. **options** (optional): Table with context data

### `logging.debug(message, options?)`

Log at DEBUG level.

```lua
logging.debug("Processing started")

logging.debug("User action", {
  category = "App",
  user_id = 123
})
```

### `logging.info(message, options?)`

Log at INFO level.

```lua
logging.info("Request completed", {
  categories = {"HTTP", "API"},
  status = 200,
  duration_ms = 45
})
```

### `logging.warning(message, options?)`

Log at WARNING level.

```lua
logging.warning("Slow query detected", {
  category = "Database",
  duration_ms = 5000,
  threshold = 100
})
```

### `logging.error(message, options?)`

Log at ERROR level.

```lua
logging.error("Authentication failed", {
  categories = {"Auth", "Security"},
  user = "admin",
  reason = "invalid_token"
})
```

## Options Table Format

The options table supports these special keys:

- **`category`**: Single category string
- **`categories`**: Table/array of category strings
- **All other keys**: Become structured context data

```lua
logging.info("Complex log", {
  -- Special: single category
  category = "HTTP",
  
  -- Or: multiple categories
  categories = {"HTTP", "API", "Performance"},
  
  -- Context data: any key-value pairs
  method = "POST",
  endpoint = "/api/users",
  status = 201,
  duration_ms = 45,
  
  -- Nested data works too
  metadata = {
    user_id = 123,
    ip = "192.168.1.1"
  }
})
```

## Usage Examples

### Basic Logging

```lua
logging.enable("INFO")

logging.info("Server started")
logging.warning("High memory usage")
logging.error("Failed to connect to database")
```

### With Categories

```lua
logging.enable("DEBUG")

-- Single category
logging.debug("Fetching user data", {category = "Database"})

-- Multiple categories
logging.info("Request handled", {
  categories = {"HTTP", "API", "Performance"}
})
```

### With Structured Context

```lua
logging.enable("INFO")

logging.info("API request processed", {
  category = "API",
  method = "POST",
  endpoint = "/users",
  status = 201,
  duration_ms = 45,
  user_id = 123
})
```

### Category Filtering

```lua
logging.enable("DEBUG")

-- Only show HTTP and Database logs
logging.set_categories({"HTTP", "Database"})

logging.debug("Won't show", {category = "App"})
logging.info("Will show", {category = "HTTP"})
logging.warning("Will show", {category = "Database"})
logging.error("Won't show", {category = "Security"})
```

### Level Filtering

```lua
logging.enable("DEBUG")
logging.set_level("WARNING")

logging.debug("Won't show")   -- Below threshold
logging.info("Won't show")    -- Below threshold
logging.warning("Will show")  -- At threshold
logging.error("Will show")    -- Above threshold
```

### Real-World Example

```lua
logging.enable("INFO")

local function process_request(user_id, action)
  logging.info("Processing request", {
    categories = {"API", "User"},
    user_id = user_id,
    action = action,
    timestamp = os.time()
  })
  
  -- Simulate work
  local start = os.clock()
  -- ... do work ...
  local duration = (os.clock() - start) * 1000
  
  if duration > 100 then
    logging.warning("Slow request", {
      categories = {"Performance", "API"},
      duration_ms = duration,
      threshold_ms = 100,
      user_id = user_id
    })
  end
  
  logging.info("Request completed", {
    categories = {"API", "User"},
    user_id = user_id,
    duration_ms = duration,
    success = true
  })
end

process_request(42, "update_profile")
```

## Output Format

Logs appear with timestamps, levels, messages, and context:

```
[2025-10-11 12:42:07.071] [INFO] This is an info message
[2025-10-11 12:42:07.071] [WARNING] This is a warning message
[2025-10-11 12:42:07.071] [ERROR] This is an error message

[2025-10-11 12:42:07.072] [INFO] Processing user request | Context: {categories: [HTTP]}

[2025-10-11 12:42:07.073] [INFO] API request processed | Context: {method: POST, endpoint: /users, status: 201, duration_ms: 45, categories: [API]}

[2025-10-11 12:42:07.074] [WARNING] Slow query detected | Context: {query_time_ms: 123, threshold_ms: 100, optimization_needed: true, categories: [Database, Performance]}
```

## Best Practices

### 1. Use Appropriate Levels

- **DEBUG**: Development diagnostics, verbose tracing
- **INFO**: Normal operational messages, state changes
- **WARNING**: Unexpected but recoverable issues
- **ERROR**: Failures requiring attention

### 2. Use Categories for Organization

Group related logs with categories for easy filtering:

```lua
logging.debug("Query executed", {category = "Database"})
logging.info("Request received", {category = "HTTP"})
logging.warning("Cache miss", {category = "Performance"})
```

### 3. Add Structured Context

Include relevant data to make logs actionable:

```lua
logging.error("Payment failed", {
  category = "Payment",
  user_id = 123,
  amount = 99.99,
  error_code = "CARD_DECLINED",
  transaction_id = "txn_abc123"
})
```

### 4. Filter in Production

Use level and category filtering to reduce noise:

```lua
-- In production: only warnings and errors
logging.enable("WARNING")

-- Debug specific subsystem
logging.set_level("DEBUG")
logging.set_categories({"Payment", "Auth"})
```

### 5. Disable When Not Needed

Logging has zero overhead when disabled:

```lua
-- Disable for performance-critical sections
logging.disable()
-- ... hot path code ...
logging.enable("INFO")
```

## Migration from Old API

If you were using the old logging API, here's how to migrate:

### Old Style
```lua
-- Old: just enable/disable
logging.enable()
logging.disable()
```

### New Style
```lua
-- New: same, plus logging functions and context
logging.enable("INFO")
logging.info("Message", {category = "App", user = 123})
logging.disable()
```

The old `enable()` and `disable()` still work for backward compatibility.

## Implementation Notes

- Uses the `contextual` package for efficient structured logging
- Category filtering uses any-match (OR logic)
- Level filtering uses threshold comparison (≥ minimum level)
- Context data is automatically converted from Lua types to Dart types
- Nested tables in context are supported
- Categories can be specified as single string or array

## See Also

- Example script: `luascripts/logging_example.lua`
- Clean demo: `luascripts/logging_demo_clean.lua`
- Tests: `test/stdlib/logging_library_test.dart`


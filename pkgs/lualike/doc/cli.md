# CLI Logging Controls

lualike’s CLI supports fine-grained logging control similar to the Lua CLI, with extra flags for categories and levels.

## Common Flags

- `--debug`             Enable debug mode (also sets a fine-grained default log level)
- `--level LEVEL`       Set log level (e.g., `FINE`, `INFO`, `WARNING`, `SEVERE`)
- `--level LEVEL`       Set log level (debug, info, warning, error, critical, alert, emergency; legacy synonyms like FINE/INFO/WARNING/SEVERE supported)
- `--category CAT`      Filter by category (repeat flag to include multiple, or pass comma-separated)

If no script or code is provided, lualike starts in REPL mode.

## Environment Variables

- `LOGGING_ENABLED=true`   Enables logging in all modes
- `LOGGING_LEVEL=FINE`     Sets the default log level
  - Accepts: debug/info/warning/error/critical/alert/emergency or FINE/INFO/WARNING/SEVERE/SHOUT/CONFIG
- `LOGGING_CATEGORY=Interp,GC`  Comma-separated category filters
- `LOGGING_BACKEND=contextual|basic`  Selects logging backend (default: contextual)
- `LOGGING_PRETTY=true|false`  Pretty formatting for contextual backend (default: true)

## Examples

```sh
# Run a script with debug logging for two categories
lualike --debug --category Interp --category Value myscript.lua

# Same using comma-separated values
lualike --debug --category Interp,Value myscript.lua

# Using environment variables for logging
LOGGING_ENABLED=true LOGGING_LEVEL=INFO LOGGING_CATEGORY=Interp,GC lualike myscript.lua

# REPL with warnings only
lualike --level WARNING
```

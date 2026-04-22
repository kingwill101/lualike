#!/usr/bin/env lua

local EXPECTED_VERSION = '11.5'
local LOVE_API_REPO = 'https://github.com/love2d-community/love-api.git'
local OUTPUT_FILE = 'doc/love_11_5_api_audit.md'
local MATRIX_OUTPUT_FILE = 'doc/love_11_5_compatibility_matrix.md'
local OVERRIDES_FILE = 'tool/love_compatibility_overrides.lua'

local function script_path()
  local source = debug.getinfo(1, 'S').source
  if source:sub(1, 1) == '@' then
    return source:sub(2)
  end
  return source
end

local function dirname(path)
  return path:match('^(.*)/[^/]+$') or '.'
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

local function run_checked(command)
  local ok, _, code = os.execute(command)
  if ok == true or ok == 0 then
    return
  end
  error(string.format('Command failed (%s): %s', tostring(code), command))
end

local function capture_checked(command)
  local pipe = assert(io.popen(command, 'r'))
  local output = pipe:read('*a')
  local ok, _, code = pipe:close()
  if not ok then
    error(string.format('Command failed (%s): %s', tostring(code), command))
  end
  return (output:gsub('%s+$', ''))
end

local function file_exists(path)
  local file = io.open(path, 'r')
  if file == nil then
    return false
  end
  file:close()
  return true
end

local function count(list)
  return list and #list or 0
end

local function fullname(item)
  return item.fullname or item.name
end

local function code_list(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    out[#out + 1] = string.format('`%s`', fullname(item))
  end
  if #out == 0 then
    return '_none_'
  end
  return table.concat(out, ', ')
end

local function constant_list(enum)
  local out = {}
  for _, item in ipairs(enum.constants or {}) do
    out[#out + 1] = string.format('`%s`', item.name)
  end
  if #out == 0 then
    return '_none_'
  end
  return table.concat(out, ', ')
end

local function write_line(lines, value)
  lines[#lines + 1] = value
end

local function ordered_modules(modules)
  local ordered = {}
  for _, module_ in ipairs(modules) do
    if module_.fullname == 'love' then
      ordered[#ordered + 1] = module_
    end
  end
  for _, module_ in ipairs(modules) do
    if module_.fullname ~= 'love' then
      ordered[#ordered + 1] = module_
    end
  end
  return ordered
end

local script_dir = dirname(script_path())
local package_root = dirname(script_dir)
local output_path = package_root .. '/' .. OUTPUT_FILE
local matrix_output_path = package_root .. '/' .. MATRIX_OUTPUT_FILE
local overrides_path = package_root .. '/' .. OVERRIDES_FILE

local backend_buckets = {
  ['love'] = 'Runtime lifecycle, callback dispatch, and compatibility shims',
  ['love.audio'] = 'Flame/Flutter audio bridge',
  ['love.data'] = 'Custom runtime data codecs and binary packing',
  ['love.event'] = 'Custom runtime event bus',
  ['love.filesystem'] = 'Flutter assets and save-directory abstraction',
  ['love.font'] = 'Flutter text/font loading bridge',
  ['love.graphics'] = 'Flame renderer plus Flutter graphics adapters',
  ['love.image'] = 'Image decode/encode bridge on Flutter codecs',
  ['love.joystick'] = 'Gamepad bridge',
  ['love.keyboard'] = 'Keyboard input bridge',
  ['love.math'] = 'Pure Dart math helpers and transforms',
  ['love.mouse'] = 'Pointer and cursor bridge',
  ['love.physics'] = 'Forge2D compatibility bridge',
  ['love.sound'] = 'Audio decode and sample-data bridge',
  ['love.system'] = 'Platform services bridge',
  ['love.thread'] = 'Shared async worker bridge',
  ['love.timer'] = 'Game loop and timing bridge',
  ['love.touch'] = 'Touch input bridge',
  ['love.video'] = 'Video stream control bridge',
  ['love.window'] = 'Flutter window/surface bridge',
}

local default_phases = {
  ['love'] = 'foundation',
  ['love.audio'] = 'high',
  ['love.data'] = 'medium',
  ['love.event'] = 'foundation',
  ['love.filesystem'] = 'foundation',
  ['love.font'] = 'high',
  ['love.graphics'] = 'foundation',
  ['love.image'] = 'high',
  ['love.joystick'] = 'medium',
  ['love.keyboard'] = 'foundation',
  ['love.math'] = 'foundation',
  ['love.mouse'] = 'foundation',
  ['love.physics'] = 'high',
  ['love.sound'] = 'high',
  ['love.system'] = 'medium',
  ['love.thread'] = 'later',
  ['love.timer'] = 'foundation',
  ['love.touch'] = 'foundation',
  ['love.video'] = 'later',
  ['love.window'] = 'foundation',
}

local function file_exists(path)
  local file = io.open(path, 'r')
  if file then
    file:close()
    return true
  end
  return false
end

local function load_overrides()
  if not file_exists(overrides_path) then
    return {modules = {}, symbols = {}, extra_symbols = {}}
  end

  local chunk = assert(loadfile(overrides_path))
  local data = chunk()
  data = data or {}
  data.modules = data.modules or {}
  data.symbols = data.symbols or {}
  data.extra_symbols = data.extra_symbols or {}
  return data
end

local function merge_tables(...)
  local merged = {}
  for i = 1, select('#', ...) do
    local source = select(i, ...)
    if source then
      for key, value in pairs(source) do
        merged[key] = value
      end
    end
  end
  return merged
end

local function extra_symbol_code_list(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    out[#out + 1] = string.format('`%s`', item.symbol)
  end
  if #out == 0 then
    return '_none_'
  end
  return table.concat(out, ', ')
end

local function ordered_extra_symbols(items)
  local ordered = {}
  for _, item in ipairs(items or {}) do
    ordered[#ordered + 1] = item
  end
  table.sort(ordered, function(left, right)
    return left.symbol < right.symbol
  end)
  return ordered
end

local function group_extra_symbols(extra_symbols)
  local by_module = {}
  local by_module_container = {}

  for _, extra in ipairs(extra_symbols or {}) do
    local module_items = by_module[extra.module]
    if module_items == nil then
      module_items = {}
      by_module[extra.module] = module_items
    end
    module_items[#module_items + 1] = extra

    if extra.container ~= nil then
      local module_containers = by_module_container[extra.module]
      if module_containers == nil then
        module_containers = {}
        by_module_container[extra.module] = module_containers
      end
      local container_items = module_containers[extra.container]
      if container_items == nil then
        container_items = {}
        module_containers[extra.container] = container_items
      end
      container_items[#container_items + 1] = extra
    end
  end

  for module_name, items in pairs(by_module) do
    by_module[module_name] = ordered_extra_symbols(items)
  end

  for _, containers in pairs(by_module_container) do
    for container_name, items in pairs(containers) do
      containers[container_name] = ordered_extra_symbols(items)
    end
  end

  return by_module, by_module_container
end

local temp_root
local vendored_repo_dir = package_root .. '/third_party/love-api'
local vendored_repo_entry = vendored_repo_dir .. '/love_api.lua'
local using_vendored_repo = file_exists(vendored_repo_entry)
local repo_dir = vendored_repo_dir
local repo_commit = 'vendored-local'

local function cleanup()
  if temp_root ~= nil and temp_root ~= '' then
    os.execute('rm -rf ' .. shell_quote(temp_root))
  end
end

local ok, err = xpcall(function()
  if using_vendored_repo then
    repo_commit = capture_checked(
      'git -C ' ..
        shell_quote(vendored_repo_dir) ..
        ' rev-parse HEAD 2>/dev/null || printf vendored-local'
    )
  else
    temp_root = capture_checked('mktemp -d')
    repo_dir = temp_root .. '/love-api'
    run_checked(
      'git clone --depth 1 ' ..
        shell_quote(LOVE_API_REPO) ..
        ' ' ..
        shell_quote(repo_dir) ..
        ' >/dev/null 2>&1'
    )
    repo_commit = capture_checked(
      'git -C ' .. shell_quote(repo_dir) .. ' rev-parse HEAD'
    )
  end

  package.path =
    repo_dir ..
    '/?.lua;' ..
    repo_dir ..
    '/?/init.lua;' ..
    repo_dir ..
    '/?/?.lua;' ..
    package.path

  local api = require('extra')(require('love_api'))
  local overrides = load_overrides()
  local extra_symbols_by_module, extra_symbols_by_module_container =
    group_extra_symbols(overrides.extra_symbols)
  local total_extra_symbols = count(overrides.extra_symbols)
  if api.version ~= EXPECTED_VERSION then
    error(
      string.format(
        'Expected LOVE API version %s but fetched %s',
        EXPECTED_VERSION,
        tostring(api.version)
      )
    )
  end

  local function partition_root_functions(module_)
    local root_functions = {}
    local callbacks = {}
    for _, fn in ipairs(module_.functions or {}) do
      if fn.what == 'callback' then
        callbacks[#callbacks + 1] = fn
      else
        root_functions[#root_functions + 1] = fn
      end
    end
    return root_functions, callbacks
  end

  local total_constructors = 0
  local total_enum_constants = 0
  local total_free_functions = count(api.functions)

  for _, module_ in ipairs(api.modules) do
    for _, type_ in ipairs(module_.types or {}) do
      total_constructors = total_constructors + count(type_.constructors)
    end
    for _, enum in ipairs(module_.enums or {}) do
      total_enum_constants = total_enum_constants + count(enum.constants)
    end
  end

  local root_module
  for _, module_ in ipairs(api.modules) do
    if module_.fullname == 'love' then
      root_module = module_
      break
    end
  end
  assert(root_module, 'Expected root love module')

  local root_functions, root_callbacks = partition_root_functions(root_module)

  local lines = {}
  local matrix_lines = {}

  write_line(lines, '# LOVE 11.5 API Audit')
  write_line(lines, '')
  write_line(
    lines,
    'This document is generated by `tool/generate_love_api_audit.lua`.'
  )
  write_line(lines, '')
  write_line(lines, '## Scope')
  write_line(lines, '')
  write_line(lines, '- Compatibility target: `LÖVE 11.5`.')
  write_line(
    lines,
    '- Official status baseline: `11.5` is the current released line and `12.0` is still in development.'
  )
  write_line(
    lines,
    '- Core parity scope: the first-party `love` module plus all built-in submodules.'
  )
  write_line(
    lines,
    '- Explicitly out of scope for the first 1:1 pass: third-party modules listed on the wiki (`lua-enet`, `socket`, and `utf8`).'
  )
  write_line(lines, '')
  write_line(lines, '## Provenance')
  write_line(lines, '')
  write_line(
    lines,
    '- Official LOVE wiki version scope: `https://www.love2d.org/wiki/Version_History`'
  )
  write_line(
    lines,
    '- Official LOVE 11.5 release page: `https://www.love2d.org/wiki/11.5`'
  )
  write_line(
    lines,
    '- Official LOVE 12.0 development page: `https://www.love2d.org/wiki/12.0`'
  )
  write_line(
    lines,
    '- Official root module documentation: `https://www.love2d.org/wiki/love`'
  )
  if using_vendored_repo then
    write_line(
      lines,
      '- Machine-readable inventory source: vendored `third_party/love-api` (preferred over remote `' ..
        LOVE_API_REPO ..
        '`).'
    )
  else
    write_line(
      lines,
      '- Machine-readable inventory source: `https://github.com/love2d-community/love-api`'
    )
  end
  local repo_ref = using_vendored_repo and repo_commit or ('master@' .. repo_commit)
  write_line(lines, '- Generator input ref: `' .. repo_ref .. '`')
  write_line(lines, '')
  write_line(lines, '## Surface Summary')
  write_line(lines, '')
  write_line(lines, '| Surface | Count |')
  write_line(lines, '| --- | ---: |')
  write_line(lines, '| Modules including `love` | ' .. count(api.modules) .. ' |')
  write_line(lines, '| Built-in submodules excluding `love` | ' .. (count(api.modules) - 1) .. ' |')
  write_line(lines, '| Root `love` functions | ' .. count(root_functions) .. ' |')
  write_line(lines, '| Callbacks | ' .. count(root_callbacks) .. ' |')
  write_line(
    lines,
    '| Non-method functions (`love` + submodules, excluding callbacks) | ' ..
      total_free_functions ..
      ' |'
  )
  write_line(lines, '| Types | ' .. count(api.types) .. ' |')
  write_line(lines, '| Constructors | ' .. total_constructors .. ' |')
  write_line(lines, '| Methods | ' .. count(api.methods) .. ' |')
  write_line(lines, '| Enums | ' .. count(api.enums) .. ' |')
  write_line(lines, '| Enum constants | ' .. total_enum_constants .. ' |')
  write_line(lines, '| Source-backed extra symbols | ' .. total_extra_symbols .. ' |')
  write_line(lines, '')
  write_line(lines, '## Backend Buckets')
  write_line(lines, '')
  write_line(
    lines,
    'These are implementation-planning buckets for the Flutter/Flame-based compatibility layer, not claims about completed support.'
  )
  write_line(lines, '')
  write_line(lines, '| Module | Likely backend bucket |')
  write_line(lines, '| --- | --- |')
  for _, module_ in ipairs(ordered_modules(api.modules)) do
    write_line(
      lines,
      '| `' ..
        module_.fullname ..
        '` | ' ..
        (backend_buckets[module_.fullname] or 'Custom compatibility shim') ..
        ' |'
    )
  end
  write_line(lines, '')
  write_line(lines, '## Detailed Inventory')
  write_line(lines, '')

  local function render_types(lines_, types, extra_symbols_by_container)
    if count(types) == 0 then
      write_line(lines_, '- Types: _none_')
      return
    end

    write_line(lines_, '- Types (' .. count(types) .. '):')
    for _, type_ in ipairs(types) do
      write_line(lines_, '  - `' .. fullname(type_) .. '`')
      if count(type_.supertypes) > 0 then
        write_line(lines_, '    - Supertypes: ' .. code_list(type_.supertypes))
      end
      if count(type_.constructors) > 0 then
        write_line(
          lines_,
          '    - Constructors (' ..
            count(type_.constructors) ..
            '): ' ..
            code_list(type_.constructors)
        )
      end
      if count(type_.functions) > 0 then
        write_line(
          lines_,
          '    - Methods (' ..
            count(type_.functions) ..
            '): ' ..
            code_list(type_.functions)
        )
      else
        write_line(lines_, '    - Methods: _none_')
      end
      local extra_symbols =
        extra_symbols_by_container and
        extra_symbols_by_container[fullname(type_)] or
        nil
      if count(extra_symbols) > 0 then
        write_line(
          lines_,
          '    - Source-backed extra symbols (' ..
            count(extra_symbols) ..
            '): ' ..
            extra_symbol_code_list(extra_symbols)
        )
      end
    end
  end

  local function render_enums(lines_, enums)
    if count(enums) == 0 then
      write_line(lines_, '- Enums: _none_')
      return
    end

    write_line(lines_, '- Enums (' .. count(enums) .. '):')
    for _, enum in ipairs(enums) do
      write_line(lines_, '  - `' .. fullname(enum) .. '`')
      write_line(
        lines_,
        '    - Constants (' ..
          count(enum.constants) ..
          '): ' ..
          constant_list(enum)
      )
    end
  end

  local function write_extra_symbol_inventory(lines_, module_name)
    local extra_symbols = extra_symbols_by_module[module_name]
    if count(extra_symbols) == 0 then
      return
    end

    write_line(
      lines_,
      '- Source-backed extra symbols (' ..
        count(extra_symbols) ..
        '): ' ..
        extra_symbol_code_list(extra_symbols)
    )
  end

  for _, module_ in ipairs(ordered_modules(api.modules)) do
    local module_extra_symbols = extra_symbols_by_module[module_.fullname]
    local extra_summary = count(module_extra_symbols) > 0 and
        (', ' .. count(module_extra_symbols) .. ' source-backed extras') or
        ''
    if module_.fullname == 'love' then
      write_line(
        lines,
        '<details><summary><code>love</code> — ' ..
          count(root_functions) ..
          ' root functions, ' ..
          count(root_callbacks) ..
          ' callbacks, ' ..
          count(module_.types) ..
          ' types' ..
          extra_summary ..
          '</summary>'
      )
      write_line(lines, '')
      write_line(lines, '- Root functions (' .. count(root_functions) .. '): ' .. code_list(root_functions))
      write_line(lines, '- Callbacks (' .. count(root_callbacks) .. '): ' .. code_list(root_callbacks))
      write_extra_symbol_inventory(lines, module_.fullname)
      render_types(
        lines,
        module_.types or {},
        extra_symbols_by_module_container[module_.fullname]
      )
      render_enums(lines, module_.enums or {})
      write_line(lines, '')
      write_line(lines, '</details>')
      write_line(lines, '')
    else
      write_line(
        lines,
        '<details><summary><code>' ..
          module_.fullname ..
          '</code> — ' ..
          count(module_.functions) ..
          ' functions, ' ..
          count(module_.types) ..
          ' types, ' ..
          count(module_.enums) ..
          ' enums' ..
          extra_summary ..
          '</summary>'
      )
      write_line(lines, '')
      write_line(
        lines,
        '- Module functions (' ..
          count(module_.functions) ..
          '): ' ..
          code_list(module_.functions)
      )
      write_extra_symbol_inventory(lines, module_.fullname)
      render_types(
        lines,
        module_.types or {},
        extra_symbols_by_module_container[module_.fullname]
      )
      render_enums(lines, module_.enums or {})
      write_line(lines, '')
      write_line(lines, '</details>')
      write_line(lines, '')
    end
  end

  local function symbol_key(kind, item, parent)
    if kind == 'module' then
      return fullname(item)
    end
    if kind == 'constant' then
      return fullname(parent) .. '.' .. item.name
    end
    return fullname(item)
  end

  local function default_note(kind, item, parent, module_name)
    if kind == 'module' then
      return 'Top-level compatibility surface for this LOVE module.'
    end
    if kind == 'function' then
      return 'Free function on `' .. module_name .. '`.'
    end
    if kind == 'callback' then
      return 'Runtime callback expected to be dispatched by the compatibility layer.'
    end
    if kind == 'constructor' then
      local target = item.constructs and fullname(item.constructs) or nil
      if target then
        return 'Constructor function for `' .. target .. '`.'
      end
      return 'Constructor function.'
    end
    if kind == 'method' then
      if fullname(parent) == 'Object' and item.name == 'release' then
        return 'Shared base-object release contract used by the implemented wrapper types. Release is idempotent and returns `true` the first time and `false` on later calls. The released Lua wrapper is invalidated so later method calls stop treating it as a live object, and wrappers with owned runtime resources such as `Source`, `Video`, and `VideoStream` also dispose or detach their backing runtime state during the first release.'
      end
      return 'Instance method on `' .. fullname(parent) .. '`.'
    end
    if kind == 'type' then
      if count(item.supertypes) > 0 then
        return 'Type with supertypes: ' .. code_list(item.supertypes) .. '.'
      end
      return 'Type surface.'
    end
    if kind == 'enum' then
      return 'Enum with ' .. count(item.constants) .. ' constants.'
    end
    if kind == 'constant' then
      return 'Enum constant on `' .. fullname(parent) .. '`.'
    end
    return ''
  end

  local function row_state(module_name, kind, item, parent)
    local module_defaults = {
      backend = backend_buckets[module_name] or 'Custom compatibility shim',
      phase = default_phases[module_name] or 'later',
      status = 'planned',
      conformance = 'inventory-only',
    }
    local raw_module_override = overrides.modules[module_name] or {}
    local module_override = merge_tables(raw_module_override)
    module_override.notes = nil
    local key = symbol_key(kind, item, parent)
    local symbol_override = overrides.symbols[key]
    local state = merge_tables(module_defaults, module_override, symbol_override)
    if kind == 'module' and raw_module_override.notes and not state.notes then
      state.notes = raw_module_override.notes
    end
    state.notes = state.notes or default_note(kind, item, parent, module_name)
    state.key = key
    return state
  end

  local function push_matrix_row(rows, module_name, symbol, kind, state)
    rows[#rows + 1] =
      '| `' ..
      symbol ..
      '` | `' ..
      kind ..
      '` | `' ..
      state.phase ..
      '` | `' ..
      state.status ..
      '` | ' ..
      state.backend ..
      ' | `' ..
      state.conformance ..
      '` | ' ..
      state.notes ..
      ' |'
  end

  local function extra_item(symbol)
    return {fullname = symbol, name = symbol}
  end

  local function extra_parent(container)
    if container == nil then
      return nil
    end
    return {fullname = container, name = container}
  end

  local function extra_row_state(extra)
    local state = row_state(
      extra.module,
      extra.kind,
      extra_item(extra.symbol),
      extra_parent(extra.container)
    )
    if extra.notes ~= nil then
      state.notes = extra.notes
    end
    return state
  end

  write_line(matrix_lines, '# LOVE 11.5 Compatibility Matrix')
  write_line(matrix_lines, '')
  write_line(
    matrix_lines,
    'This document is generated by `tool/generate_love_api_audit.lua` and merged with `tool/love_compatibility_overrides.lua`.'
  )
  write_line(matrix_lines, '')
  write_line(matrix_lines, '## Scope')
  write_line(matrix_lines, '')
  write_line(matrix_lines, '- Target API version: `LÖVE 11.5`.')
  write_line(matrix_lines, '- Matrix scope: first-party `love` API surface only.')
  write_line(
    matrix_lines,
    '- All rows default to `planned` until explicit overrides are recorded.'
  )
  write_line(matrix_lines, '')
  write_line(matrix_lines, '## Legend')
  write_line(matrix_lines, '')
  write_line(matrix_lines, '- `phase`: rough implementation ordering for the Flutter/Flame compatibility layer.')
  write_line(matrix_lines, '- `status`: `planned`, `investigating`, `blocked`, `partial`, `shimmed`, `implemented`, or `conformance-tested`.')
  write_line(matrix_lines, '- `conformance`: `inventory-only`, `tests-planned`, `smoke-tested`, `parity-tested`, or `golden-tested`.')
  write_line(matrix_lines, '')
  write_line(matrix_lines, '## Module Summary')
  write_line(matrix_lines, '')
  write_line(matrix_lines, '| Module | Phase | Rows | Backend |')
  write_line(matrix_lines, '| --- | --- | ---: | --- |')

  local matrix_sections = {}

  for _, module_ in ipairs(ordered_modules(api.modules)) do
    local module_name = module_.fullname
    local module_rows = {}
    local module_state = row_state(module_name, 'module', module_)

    push_matrix_row(module_rows, module_name, module_name, 'module', module_state)

    if module_name == 'love' then
      for _, fn in ipairs(root_functions) do
        local kind = fn.constructs and 'constructor' or 'function'
        local state = row_state(module_name, kind, fn)
        push_matrix_row(module_rows, module_name, fullname(fn), kind, state)
      end
      for _, fn in ipairs(root_callbacks) do
        local state = row_state(module_name, 'callback', fn)
        push_matrix_row(module_rows, module_name, fullname(fn), 'callback', state)
      end
    else
      for _, fn in ipairs(module_.functions or {}) do
        local kind = fn.constructs and 'constructor' or 'function'
        local state = row_state(module_name, kind, fn)
        push_matrix_row(module_rows, module_name, fullname(fn), kind, state)
      end
    end

    for _, type_ in ipairs(module_.types or {}) do
      local type_state = row_state(module_name, 'type', type_)
      push_matrix_row(module_rows, module_name, fullname(type_), 'type', type_state)

      for _, method in ipairs(type_.functions or {}) do
        local state = row_state(module_name, 'method', method, type_)
        push_matrix_row(module_rows, module_name, fullname(method), 'method', state)
      end
    end

    for _, enum in ipairs(module_.enums or {}) do
      local enum_state = row_state(module_name, 'enum', enum)
      push_matrix_row(module_rows, module_name, fullname(enum), 'enum', enum_state)

      for _, constant in ipairs(enum.constants or {}) do
        local state = row_state(module_name, 'constant', constant, enum)
        push_matrix_row(
          module_rows,
          module_name,
          fullname(enum) .. '.' .. constant.name,
          'constant',
          state
        )
      end
    end

    for _, extra in ipairs(extra_symbols_by_module[module_name] or {}) do
      local state = extra_row_state(extra)
      push_matrix_row(module_rows, module_name, extra.symbol, extra.kind, state)
    end

    local module_row_count = #module_rows
    write_line(
      matrix_lines,
      '| `' ..
        module_name ..
        '` | `' ..
        module_state.phase ..
        '` | ' ..
        module_row_count ..
        ' | ' ..
        module_state.backend ..
        ' |'
    )

    write_line(
      matrix_sections,
      '<details><summary><code>' ..
        module_name ..
        '</code> — ' ..
        module_row_count ..
        ' matrix rows</summary>'
    )
    write_line(matrix_sections, '')
    write_line(
      matrix_sections,
      '| Symbol | Kind | Phase | Status | Backend | Conformance | Notes |'
    )
    write_line(
      matrix_sections,
      '| --- | --- | --- | --- | --- | --- | --- |'
    )
    for _, row in ipairs(module_rows) do
      write_line(matrix_sections, row)
    end
    write_line(matrix_sections, '')
    write_line(matrix_sections, '</details>')
    write_line(matrix_sections, '')
  end

  write_line(matrix_lines, '')
  write_line(matrix_lines, '## Detailed Matrix')
  write_line(matrix_lines, '')
  for _, line in ipairs(matrix_sections) do
    write_line(matrix_lines, line)
  end

  run_checked('mkdir -p ' .. shell_quote(dirname(output_path)))
  local file = assert(io.open(output_path, 'w'))
  file:write(table.concat(lines, '\n'))
  file:write('\n')
  file:close()

  run_checked('mkdir -p ' .. shell_quote(dirname(matrix_output_path)))
  local matrix_file = assert(io.open(matrix_output_path, 'w'))
  matrix_file:write(table.concat(matrix_lines, '\n'))
  matrix_file:write('\n')
  matrix_file:close()

  io.stdout:write('Wrote ' .. output_path .. '\n')
  io.stdout:write('Wrote ' .. matrix_output_path .. '\n')
end, debug.traceback)

cleanup()

if not ok then
  io.stderr:write(err .. '\n')
  os.exit(1)
end

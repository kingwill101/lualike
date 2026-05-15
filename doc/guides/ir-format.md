# Lualike Intermediate Representation (IR) Format

This guide describes the Lualike Intermediate Representation (IR), the internal bytecode format used by the Lualike VM. The IR is designed to be a register-based instruction set that closely mirrors Lua 5.4's bytecode (lopcodes.h), while providing extensibility for Dart-specific features.

## Overview

Lualike translates Lua source code into a hierarchy of **Prototypes** contained within a **Chunk**. Each prototype corresponds to a Lua function (including the main script body) and contains:

- **Constants**: Values used by the code (strings, numbers, etc.).
- **Instructions**: The executable bytecode.
- **Upvalue Descriptors**: Information about variables captured from outer scopes.
- **Debug Info**: Line numbers, local variable names, and source mapping.
- **Child Prototypes**: Nested function definitions.

## Chunk and Prototype Structure

### Chunk
A chunk is the top-level unit of compilation, typically representing a single source file.
- `has_debug_info`: Boolean flag indicating if the chunk contains debug metadata.
- `mainPrototype`: The entry point prototype representing the script's body.

### Prototype
- `name`: The name of the prototype (e.g., `main` or a function name).
- `register_count`: The number of registers required for this function.
- `param_count`: The number of fixed parameters.
- `is_vararg`: Boolean flag indicating if the function accepts variable arguments.
- `line_defined` / `last_line_defined`: Source range where the function is defined.
- `instructions`: List of IR instructions.
- `constants`: List of constant values. In IR dumps, these are prefixed by their type:
    - `int`: 64-bit integer.
    - `number`: 64-bit float.
    - `bool`: Boolean value.
    - `short`: String (typically <= 40 chars).
    - `long`: String (typically > 40 chars).
    - `nil`: The `nil` value.
- `upvalue_descriptors`: Metadata for upvalues accessed by this function. Each descriptor includes:
    - `in_stack`: `1` if the upvalue refers to a local variable in the parent function's stack, `0` if it refers to an upvalue of the parent function.
    - `index`: The register index (if `in_stack=1`) or upvalue index (if `in_stack=0`) in the parent function.
    - `kind`: Reserved for future use (mirrors Lua's internal categorization).
- `upvalue_names`: List of upvalue names for this prototype, useful for debugger symbols.
- `absolute_source_path`: The full path to the source file.
- `prototypes`: List of child prototypes (nested functions). In IR dumps, these are sequentially labeled as `main_0`, `main_1`, etc., based on their order in the parent prototype.
- `register_const_flags`: Flags indicating which registers are currently treated as constant.
- `const_seal_points`: Map of instruction indices to sets of registers that become constant after that point.

## Instruction Formats

Lualike IR uses several instruction formats with different operand layouts:

| Format | Operands | Bit Widths | Description |
| :--- | :--- | :--- | :--- |
| **ABC** | A, B, C, [k] | 8, 8, 9, 1 | Standard 3-register instruction with an optional constant flag. |
| **ABx** | A, Bx | 8, 17 | Register A and an unsigned 17-bit immediate/index. |
| **AsBx** | A, sBx | 8, 17 (signed) | Register A and a signed 17-bit immediate/offset. |
| **Ax** | Ax | 25 | A single 25-bit unsigned operand. |
| **sJ** | sJ | 25 (signed) | A single 25-bit signed jump offset. |
| **AvBC** | A, vB, vC, [k] | 8, 8, 8, 1 | Variant format for specific instructions. |

## Opcode Reference

### Loading and Moving

| Opcode | Format | Logic | Description |
| :--- | :--- | :--- | :--- |
| **MOVE** | ABC | `R(A) := R(B)` | Copy value between registers. |
| **LOADI** | ABC | `R(A) := sB` | Load a signed 8-bit integer into a register. |
| **LOADF** | ABC | `R(A) := sB (float)` | Load a signed 8-bit integer as a float. |
| **LOADK** | ABx | `R(A) := K(Bx)` | Load a constant from the constant table. |
| **LOADKX** | ABx | `R(A) := K(extra)` | Load a constant using an `EXTRAARG` follow-up. |
| **LOADNIL** | ABC | `R(A..A+B) := nil` | Load `nil` into a range of registers. |
| **LOADTRUE** | ABC | `R(A) := true` | Load `true` into a register. |
| **LOADFALSE**| ABC | `R(A) := false` | Load `false` into a register. |
| **LFALSESKIP**| ABC | `R(A) := false; pc++`| Load `false` and skip the next instruction. |

### Upvalues and Globals

| Opcode | Format | Logic | Description |
| :--- | :--- | :--- | :--- |
| **GETUPVAL** | ABC | `R(A) := UpValue[B]` | Load an upvalue into a register. |
| **SETUPVAL** | ABC | `UpValue[B] := R(A)` | Store a register value into an upvalue. |
| **GETTABUP** | ABC | `R(A) := UpValue[B][K(C)]` | Access a table in an upvalue (often used for globals via `_ENV`). |
| **SETTABUP** | ABC | `UpValue[A][K(B)] := RK(C)`| Store into a table in an upvalue. |
| **CHECKGLOBAL**| ABC | - | Lualike extension: verify if a global variable write is permitted. |

### Tables

| Opcode | Format | Logic | Description |
| :--- | :--- | :--- | :--- |
| **NEWTABLE** | ABC | `R(A) := {}` | Create a new table. B is array size hint, C is hash size hint. |
| **GETTABLE** | ABC | `R(A) := R(B)[R(C)]` | Access table value by register key. |
| **GETI** | ABC | `R(A) := R(B)[C]` | Access table value by integer key. |
| **GETFIELD** | ABC | `R(A) := R(B)[K(C)]` | Access table value by constant string key. |
| **SELF** | ABC | `R(A+1) := R(B); R(A) := R(B)[RK(C)]` | Prepare for method call (colon syntax). |
| **SETTABLE** | ABC | `R(A)[R(B)] := RK(C)` | Set table value by register key. |
| **SETI** | ABC | `R(A)[B] := RK(C)` | Set table value by integer key. |
| **SETFIELD** | ABC | `R(A)[K(B)] := RK(C)` | Set table value by constant string key. |
| **SETLIST** | ABC | `R(A)[i] := R(A+i)` | Set a list of values into a table. |

### Arithmetic and Bitwise

Most arithmetic instructions have versions for register-register, register-constant (**K**), and register-immediate (**I**).

| Opcode | Format | Logic | Description |
| :--- | :--- | :--- | :--- |
| **ADD** | ABC | `R(A) := R(B) + R(C)` | Addition. |
| **ADDI** | ABC | `R(A) := R(B) + sC` | Addition with immediate. |
| **ADDK** | ABC | `R(A) := R(B) + K(C)` | Addition with constant. |
| **SUB** / **SUBK** | ABC | `R(A) := R(B) - RK(C)` | Subtraction. |
| **MUL** / **MULK** | ABC | `R(A) := R(B) * RK(C)` | Multiplication. |
| **DIV** / **DIVK** | ABC | `R(A) := R(B) / RK(C)` | Division. |
| **IDIV** / **IDIVK**| ABC | `R(A) := R(B) // RK(C)`| Floor division. |
| **MOD** / **MODK** | ABC | `R(A) := R(B) % RK(C)` | Modulo. |
| **POW** / **POWK** | ABC | `R(A) := R(B) ^ RK(C)` | Exponentiation. |
| **BAND** / **BANDK**| ABC | `R(A) := R(B) & RK(C)` | Bitwise AND. |
| **BOR** / **BORK** | ABC | `R(A) := R(B) \| RK(C)` | Bitwise OR. |
| **BXOR** / **BXORK**| ABC | `R(A) := R(B) ~ RK(C)` | Bitwise XOR. |
| **SHL** / **SHLI** | ABC | `R(A) := R(B) << RK(C)`| Bitwise Left Shift. |
| **SHR** / **SHRI** | ABC | `R(A) := R(B) >> RK(C)`| Bitwise Right Shift. |
| **UNM** | ABC | `R(A) := -R(B)` | Unary minus. |
| **BNOT** | ABC | `R(A) := ~R(B)` | Bitwise NOT. |
| **MMBIN** | ABC | `call MM(B, C, A)` | Metamethod binary operation using two register operands. Triggered when standard arithmetic/bitwise operations hit metamethods. |
| **MMBINI** | ABC | `call MM(B, sC, A)` | Metamethod binary operation with immediate. Triggered when operations with immediates hit metamethods. |
| **MMBINK** | ABC | `call MM(B, K(C), A)` | Metamethod binary operation with constant. Triggered when operations with constants hit metamethods. |

### Logical and Comparison

| Opcode | Format | Logic | Description |
| :--- | :--- | :--- | :--- |
| **NOT** | ABC | `R(A) := !R(B)` | Boolean NOT. |
| **LEN** | ABC | `R(A) := length(R(B))` | Length operator. |
| **CONCAT** | ABC | `R(A) := R(B)..R(C)` | String concatenation of a range of registers. |
| **EQ** / **EQK** / **EQI** | ABC | `if (R(B) == RK(C)) != k then pc++` | Equality comparison. |
| **LT** / **LTI** | ABC | `if (R(B) < RK(C)) != k then pc++` | Less than comparison. |
| **LE** / **LEI** | ABC | `if (R(B) <= RK(C)) != k then pc++` | Less than or equal comparison. |
| **GTI** / **GEI** | ABC | `if (R(B) > RK(C)) != k then pc++` | Greater than / Equal comparison (immediate). |
| **TEST** | ABC | `if !R(A) == k then pc++` | Test register for truthiness. |
| **TESTSET** | ABC | `if !R(B) == k then pc++ else R(A) := R(B)` | Test and conditional move. |
| **CLOSE** | ABC | `CLOSE R(A)` | Close all upvalues at or below register A. Used when leaving scopes or with to-be-closed variables. |

### Control Flow and Loops

| Opcode | Format | Logic | Description |
| :--- | :--- | :--- | :--- |
| **JMP** | sJ | `pc += sJ` | Unconditional jump. |
| **FORPREP** | AsBx | - | Prepare a numeric `for` loop. |
| **FORLOOP** | AsBx | - | Step and repeat a numeric `for` loop. |
| **TFORPREP** | AsBx | - | Prepare a generic `for` loop. |
| **TFORCALL** | ABC | - | Call the iterator in a generic `for` loop. |
| **TFORLOOP** | AsBx | - | Repeat a generic `for` loop. |
| **TBC** | ABC | `mark R(A) as to-be-closed` | Mark a variable as to-be-closed (Lua 5.4 `<close>` attribute). The variable's `__close` metamethod will be called when it goes out of scope. |

### Calls and Functions

| Opcode | Format | Logic | Description |
| :--- | :--- | :--- | :--- |
| **CALL** | ABC | `R(A..A+C-2) := R(A)(R(A+1..A+B-1))` | Function call. |
| **TAILCALL** | ABC | `return R(A)(R(A+1..A+B-1))` | Tail-recursive function call. |
| **RETURN** | ABC | `return R(A..A+B-2)` | Return from function. |
| **RETURN0** | ABC | `return` | Fast return with 0 results. |
| **RETURN1** | ABC | `return R(A)` | Fast return with 1 result. |
| **VARARG** | ABC | `R(A..A+B-2) := varargs` | Copy variable arguments to registers. |
| **GETVARG** | ABC | `R(A) := varargs[C]` | Access a single variable argument. |
| **VARARGPREP**| ABC | - | Prepare for variable arguments. |
| **CLOSURE** | ABx | `R(A) := closure(K(Bx))`| Create a closure from a child prototype. |
| **EXTRAARG** | Ax | `Ax := extra` | Extra argument used with `LOADKX` to load constants that don't fit in 17 bits. |

## Imports and Module System

Lualike handles module imports (via `require`) at **runtime only** - there are no special IR opcodes or structures for imports. 

When the compiler encounters `require("module")`:
1. It emits `GETTABUP` to load `require` from `_ENV` (the global environment table)
2. It emits `LOADK` to load the module path string constant
3. It emits `CALL` to invoke the require function

The actual module resolution and loading is implemented in the standard library (`lib/src/stdlib/lib_package.dart`), which:
- Maintains `package.loaded` table for caching loaded modules
- Uses searchers to find modules in the filesystem or preload table
- Returns the module value to be used by the calling code

**IR representation of `require("mod")`**:
```
abc GETTABUP a=2 b=0 c=3;    // R(2) := _ENV["require"]
abx LOADK a=3 bx=5;           // R(3) := K(5) ("mod")
abc CALL a=2 b=2 c=2;         // R(2) := require(R(3))
```

## Debug Information

Debug info provides metadata for tooling and error reporting:
- **Line Info**: An array where each entry corresponds to an instruction, storing its source line number.
- **Source Path**: `absolute_source_path` for stack traces.
- **Local Names**: Metadata for local variables, including their name, start PC, end PC, and register index.
- **Upvalue Names**: Names of upvalues defined in this prototype.
- **Preferred Name**: `preferred_name` and `preferred_name_what` (e.g., "local", "field") used to provide better function names in stack traces.
- **To-Be-Closed Names**: Mapping of PC to variable names that are marked for automatic closing (per Lua 5.4 `<close>`).

## Interpretation Example

Consider the following Lua script:
```lua
local a = 1
local b = 2
print(a + b)
```

The generated IR dump:
```
prototype main register_count=5 param_count=0 is_vararg=true {
  constants {
    // [0] int(1)
    int 1;
    // [1] int(2)
    int 2;
    // [2] short("print")
    short "print";
  }
  instructions {
    abc VARARGPREP a=0 b=0 c=0;   // Initialize varargs
    abx LOADK a=1 bx=0;           // R(1) := K(0)  (value 1)
    abc MOVE a=0 b=1 c=0;          // R(0) := R(1)  (local a)
    abx LOADK a=2 bx=1;           // R(2) := K(1)  (value 2)
    abc MOVE a=1 b=2 c=0;          // R(1) := R(2)  (local b)
    abc GETTABUP a=2 b=0 c=2;      // R(2) := _ENV["print"]
    abc MOVE a=3 b=0 c=0;          // R(3) := R(0)  (copy a for call)
    abc MOVE a=4 b=1 c=0;          // R(4) := R(1)  (copy b for call)
    abc ADD a=3 b=3 c=4;           // R(3) := R(3) + R(4)
    abc CALL a=2 b=2 c=1;          // call R(2) with 1 arg, 0 expected results
    abc RETURN0 a=0 b=0 c=0;       // Return
  }
}
```

### Key Takeaways:
1. **Register Allocation**: The compiler uses registers starting from 0 for locals. `a` is in `R(0)`, `b` is in `R(1)`.
2. **Global Access**: `print` is accessed via `GETTABUP` from upvalue 0 (which is the environment table `_ENV`).
3. **Call Stack**: For the `print(a + b)` call, the function (`print`) is loaded into `R(2)`, and its arguments start at `R(3)`.

## Generating IR Dumps

To view the IR for any Lua script, use the `--ir --dump-ir` flags with the Lualike CLI:

```bash
./lualike --ir --dump-ir script.lua
```

Or for inline code:

```bash
./lualike --ir --dump-ir -e "print(1 + 1)"
```

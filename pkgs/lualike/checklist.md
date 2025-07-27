# lualike VM Checklist

This checklist tracks tasks and features required to complete the VM and interpreter for lualike.

## General Architecture
- [ ] Review the complete AST structure and ensure all node types are supported.
- [x] Validate the integration of the AST visitor pattern within the VM.
- [ ] Refactor and improve the VM run loop if needed.

## VM Core
- [x] Implement a proper stack for handling expression evaluation.
- [x] Design and implement a call stack to properly handle function calls and return statements.
- [x] Enhance the global environment; implement local scopes and closure support.
- [x] Implement missing VM visitor methods (FunctionDef, ElseIfClause, Program, FunctionBody, FunctionLiteral, FunctionName, MethodCall, VarArg)
- [ ] Add error handling improvements in the State class (tracking, reporting, and recovery).
- [x] Add tests for the State class error reporting.
- [ ] Integrate comprehensive logging and debugging information.

## AST Node Evaluations
- [ ] Complete the evaluation of binary expressions, including support for additional operators.
- [ ] Implement proper type checking and coercion where needed.
- [x] Evaluate function calls through proper lookup and invocation (resolve user-defined and built-in functions).
- [x] Enhance table constructor evaluation and management of table entries.
- [ ] Ensure the visitor methods return consistent types and handle edge cases.
- [x] Write unit tests for function definitions and function calls.

## Control Flow Implementations
- [x] Refine implementation of conditional statements (if-else) ensuring boolean condition evaluation.
- [x] Fully support all loop constructs (while, for, repeat-until) with break/continue semantics.
- [x] Implement return semantics to unwind from function calls.

## State and Parsing
- [ ] Improve the State class to handle UTF-16 characters and more advanced error messages.
- [ ] Add more robust error reporting and error recovery strategies in parsing.
- [ ] Ensure that the parser transitions and matchers properly propagate errors.

## Testing and Validation
- [ ] Write unit tests for individual AST visitor methods.
- [x] Write unit tests for variable declaration and assignment.
- [x] Write unit tests for if statement evaluation.
- [x] Write unit tests for while statement evaluation.
- [x] Write unit tests for binary expression evaluation.
- [x] Write unit tests for table constructor evaluation.
- [x] Write unit tests for literal evaluation (Number, String, Boolean, Nil).
- [x] Write unit tests for the generic stack implementation.
- [x] Write unit tests for the call stack implementation.
- [x] Write unit tests for repeat-until loop evaluation.
- [x] Create integration tests for full VM execution (sample lualike scripts).
- [x] Write unit tests for return statement evaluation.
- [x] Write unit tests for return statement evaluation.
- [x] Write unit tests for goto and label support.
- [x] Write unit tests for function definitions and function calls.
- [x] Add tests for the State class error reporting.

## Future Enhancements
## Testing Coverage
### Basic Library Tests Needed
- [ ] assert() function tests
- [ ] dofile() function tests
- [ ] error() function tests
- [ ] ipairs() iteration tests
- [ ] load() function tests
- [ ] pairs() iteration tests
- [ ] print() function tests
- [ ] select() function tests
- [ ] tonumber() conversion tests
- [ ] tostring() conversion tests
- [ ] type() function tests

### String Library Tests Needed
- [ ] Basic string operations
- [ ] Pattern matching
- [ ] String metamethods

### Math Library Tests Needed
- [ ] Basic arithmetic functions
- [ ] Trigonometric functions
- [ ] Random number generation

### Table Library Tests Needed
- [ ] Table manipulation functions
- [ ] Table metamethods
- [ ] Table iteration
- [ ] Consider implementing built-in functions and libraries.
- [ ] Implement optimization passes for both the AST and VM execution.
- [ ] Profile and benchmark the VM to identify performance bottlenecks.

# LuaLike Standard Library Implementation Checklist

## Basic Library (§6.1)
- [x] assert() - Implemented with proper truthiness checks
- [x] collectgarbage() (via GC class)
- [x] dofile() - Basic implementation, needs testing
- [x] error() - Basic implementation
- [x] _G (global environment table)
- [x] getmetatable()
- [x] ipairs() - Basic implementation
- [x] load()
- [x] loadfile() - Basic implementation
- [x] next() - Basic implementation
- [x] pairs() - Basic implementation
- [x] pcall() - Basic implementation with error handling
- [x] print() - Basic implementation
- [x] rawequal() - Basic implementation
- [x] rawget()
- [x] rawlen() - Basic implementation
- [x] rawset()
- [x] select() - Basic implementation
- [x] setmetatable()
- [x] tonumber() - With base support
- [x] tostring() - With metamethod support
- [x] type() - Basic type checking
- [x] _VERSION
- [x] warn() - Basic implementation writing to stderr
- [x] xpcall() - Basic implementation with error handler

## String Library (§6.4)
- [x] string.byte()
- [x] string.char()
- [ ] string.dump()
- [x] string.find()
- [x] string.format()
- [x] string.gmatch() (placeholder implementation)
- [x] string.gsub()
- [x] string.len()
- [x] string.lower()
- [x] string.match() (placeholder implementation)
- [ ] string.pack()
- [ ] string.packsize()
- [x] string.rep()
- [x] string.reverse()
- [x] string.sub()
- [ ] string.unpack()
- [x] string.upper()

### String Metamethods
- [x] __len
- [x] __concat

## Math Library (§6.7)
- [x] math.abs()
- [x] math.acos()
- [x] math.asin()
- [x] math.atan()
- [x] math.ceil()
- [x] math.cos()
- [x] math.deg()
- [x] math.exp()
- [x] math.floor()
- [x] math.fmod()
- [x] math.huge (constant)
- [x] math.log()
- [x] math.max()
- [x] math.min()
- [x] math.modf()
- [x] math.pi (constant)
- [x] math.rad()
- [x] math.random()
- [x] math.randomseed()
- [x] math.sin()
- [x] math.sqrt()
- [x] math.tan()
- [x] math.tointeger()
- [x] math.type()
- [ ] math.ult()

## Table Library (§6.6)
- [ ] table.concat()
- [x] table.insert()
- [ ] table.move()
- [ ] table.pack()
- [x] table.remove()
- [ ] table.sort()
- [ ] table.unpack()

### Table Metamethods
- [x] __len

## Input/Output Library (§6.8)
- [ ] io.close()
- [ ] io.flush()
- [ ] io.input()
- [ ] io.lines()
- [ ] io.open()
- [ ] io.output()
- [ ] io.popen()
- [ ] io.read()
- [ ] io.tmpfile()
- [ ] io.type()
- [ ] io.write()

## Operating System Library (§6.9)
- [ ] os.clock()
- [ ] os.date()
- [ ] os.difftime()
- [ ] os.execute()
- [ ] os.exit()
- [ ] os.getenv()
- [ ] os.remove()
- [ ] os.rename()
- [ ] os.setlocale()
- [ ] os.time()
- [ ] os.tmpname()

## Debug Library (§6.10)
- [ ] debug.debug()
- [ ] debug.gethook()
- [ ] debug.getinfo()
- [ ] debug.getlocal()
- [ ] debug.getmetatable()
- [ ] debug.getupvalue()
- [ ] debug.sethook()
- [ ] debug.setlocal()
- [ ] debug.setmetatable()
- [ ] debug.setupvalue()
- [ ] debug.traceback()

## Notes
- Pattern matching functions in the string library need full implementation
- Some functions have placeholder implementations that need to be completed
- Debug library implementation is optional and mainly for development purposes
- IO and OS libraries need careful consideration for platform compatibility

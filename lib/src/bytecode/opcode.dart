// ignore_for_file: constant_identifier_names

enum OpCode {
  // Method operations
  SELF, // Setup method call
  VARARGS, // Load varargs onto stack
  SETUPVARARGS, // Setup varargs for function
  // Stack operations
  LOAD_CONST, // Load constant onto stack
  LOAD_NIL, // Load nil onto stack
  LOAD_BOOL, // Load boolean onto stack
  LOAD_LOCAL, // Load local variable onto stack
  LOAD_UPVAL, // Load upvalue onto stack
  LOAD_GLOBAL, // Load global variable onto stack

  STORE_LOCAL, // Store stack top to local variable
  STORE_UPVAL, // Store stack top to upvalue
  STORE_GLOBAL, // Store stack top to global variable
  // Arithmetic operations
  ADD, // Add top two stack values
  SUB, // Subtract
  MUL, // Multiply
  DIV, // Divide
  MOD, // Modulo
  POW, // Power
  UNM, // Unary minus
  NOT, // Logical not
  // Comparison operations
  EQ, // Equal
  LT, // Less than
  LE, // Less than or equal
  // Table operations
  NEWTABLE, // Create new table
  GETTABLE, // Get table field
  SETTABLE, // Set table field
  // Control flow
  JMP, // Unconditional jump
  JMPF, // Jump if false
  JMPT, // Jump if true
  CALL, // Call function
  RETURN, // Return from function
  // Function operations
  CLOSURE, // Create closure
  GETUPVAL, // Get upvalue
  SETUPVAL, // Set upvalue
  // Other
  MOVE, // Move value between registers
  CONCAT, // Concatenate strings
  LEN, // Get length
  // For-in loop operations
  SETUPFORLOOP, // Setup for-in loop state
  FORNEXT, // Get next value from iterator
  // Stack manipulation
  POP, // Pop top value from stack
  // Bitwise operations
  BNOT, // Bitwise not
}

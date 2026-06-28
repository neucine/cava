# Porting Plan

The rewrite should proceed module by module, aiming for Zava parity rather than a reduced toy implementation.

## Order

1. Core utilities and memory helpers.
2. Runtime type model.
3. Classfile parser.
4. Method area and class loading.
5. Heap objects, arrays, strings, and class objects.
6. Thread, frame, operand stack, and interpreter loop.
7. Bytecode instructions.
8. Native method bridge.
9. Bootstrap and command-line entry point.
10. Example parity checks.

## Reference Mapping

```text
Zava module        Cava responsibility
----------         -------------------
vm.zig            VM utilities, endian reads, string helpers, logging
mem.zig           allocation helpers and dynamic containers
type.zig          Value, Reference, Object, Class, Field, Method
classfile.zig     Java classfile reader and parsed structures
method_area.zig   class loading, linking, resolution, interning
heap.zig          object allocation, arrays, Java strings/classes
engine.zig        Thread, Frame, call loop, return/throw handling
instruction.zig   opcode registry and bytecode semantics
native.zig        native method bridge currently supported by Zava
bootstrap.zig     startup, main class lookup, args setup
main.zig          executable entry point
```

## Parity Discipline

Do not redesign while porting.

During the parity phase:

- Keep data structures close to Zava unless Cyna exposes a language gap.
- Keep unsupported operations unsupported.
- Prefer behavior comparison against Zava over interpretation of the JVM spec.
- Use small executable examples as regression checks.
- Record Cyna gaps before introducing workarounds.

## Suggested Milestones

### M1: Core Runtime Shape

- Port primitive aliases.
- Port `Value` and `Reference`.
- Port object/class/method/field metadata structures.
- Port basic allocation helpers needed by those structures.

### M2: Classfile Reader

- Read `.class` bytes.
- Parse constant pool, fields, methods, and attributes covered by Zava.
- Compare parsed debug output with Zava.

### M3: Method Area

- Load classes from the same classpath model.
- Derive runtime `Class` structures.
- Resolve fields and methods.
- Intern symbols.

### M4: Interpreter Core

- Implement `Thread`, `Frame`, local variables, operand stack, PC movement, return, and throw state.
- Dispatch opcodes using a table or the closest clean Cyna equivalent.

### M5: Instruction Parity

- Port implemented bytecodes from `instruction.zig`.
- Preserve unimplemented instruction behavior.
- Use the opcode registry as the checklist.

### M6: Heap and Native Bridge

- Port object and array allocation.
- Port Java string/class helpers.
- Port native methods required by current examples.

### M7: Example Parity

- Run the same examples as Zava.
- Compare stdout.
- Compare logs where useful.


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

- Treat Zava as the behavioral oracle. Before changing Cava VM behavior, read
  the corresponding Zava implementation and keep the Cava change structurally
  aligned unless Cyna cannot express it.
- Every Cava behavior change should be traceable to one of:
  - a direct port of a Zava module/function;
  - an explicitly documented Cyna gap in `docs/gap-log.md`;
  - an intentionally temporary milestone shim, marked as such near the code.
- Keep data structures close to Zava unless Cyna exposes a language gap.
- Keep unsupported operations unsupported.
- Prefer behavior comparison against Zava over interpretation of the JVM spec.
- Use small executable examples as regression checks.
- Record Cyna gaps before introducing workarounds.

Do not grow Cava by chasing examples with local guesses. When an example fails,
first identify the Zava path that handles it, then port that path or record why
Cyna currently blocks the port.

## Current Drift To Remove

- Cava preloads selected JDK classes and recursively scans constant pools;
  Zava resolves classes on demand through `method_area.resolveClass` using an
  initiating/defining loader model.
- Cava executes methods by recursively calling `execute_method_frame`; Zava has
  an explicit `Thread.invoke` call boundary that handles native calls, frame
  push/pop, return propagation, and uncaught exception reporting centrally.
- Cava has several special-case Java method shortcuts in `instruction.cy`;
  Zava implements these through bytecode execution, native dispatch, heap
  helpers, or VM throws.
- Cava native dispatch is organized similarly to Zava, but coverage should be
  compared signature-by-signature against `zava/src/native.zig`, not added only
  when an example happens to fail.

## Text Ownership Rule

Java-owned text is not a Cyna `string` by default.

Classfile UTF-8 constants, class names, field names, method names, descriptors,
attribute names, and method-area interned symbols should be represented as
`[]const u8` views into JVM-owned or method-area-owned bytes. Convert to Cyna
`string` only at host/Cyna boundaries where Cyna owns or controls the lifetime,
such as diagnostics, printing, APIs that explicitly require Cyna strings, or
implementation-owned synthesized metadata such as `Class.descriptor`.

Do not build long-lived JVM metadata from `string.bytes()` on a by-value Cyna
`string`. The returned byte view is tied to the Cyna string value, not to JVM
storage. If metadata must outlive the source view, first store the bytes in
method-area-owned storage and keep `[]const u8` views to that storage.

`Class.descriptor` is implementation metadata, not a Java `String` object, so it
may be a Cyna `string`. Build it from classfile byte views with `string.from`,
which copies the bytes into Cyna-owned string storage.

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

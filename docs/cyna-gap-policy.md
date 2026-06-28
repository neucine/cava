# Cyna Gap Policy

Cava is a Cyna language exercise. Finding gaps is a successful outcome.

When the port encounters a Cyna limitation, pause and document it before adding a workaround.

## Gap Categories

### Hard Gap

Cyna cannot express a required concept directly.

Examples:

- No tagged union equivalent for JVM `Value`.
- No nullable pointer/reference model.
- No stable object identity.
- No function pointer or dispatch table equivalent.

### Ergonomic Gap

Cyna can express the construct, but the resulting code is much noisier, less safe, or less direct than the Zig reference.

Examples:

- Byte parsing requires excessive boilerplate.
- Pattern matching on variant values is awkward.
- Manual bounds checks obscure instruction logic.

### Library or Runtime Gap

The language is sufficient, but the standard library or runtime lacks a needed systems feature.

Examples:

- No arena allocator.
- No growable array.
- No hash map.
- No byte buffer utilities.
- No filesystem API suitable for class loading.

### Tooling Gap

The implementation is blocked or slowed by missing tools.

Examples:

- No test runner.
- Poor compiler diagnostics.
- No formatter.
- No debugger support.
- No way to inspect generated code or runtime traces.

### FFI or Platform Gap

The port needs platform behavior that Cyna cannot currently access cleanly.

Examples:

- Reading files.
- Writing logs.
- Process arguments.
- Time or environment information needed by native methods.

## Required Gap Report

Each gap should be recorded in `docs/gap-log.md` with:

- Date.
- Module being ported.
- Zava construct.
- Smallest Cyna reproduction.
- Expected capability.
- Current blocker.
- Classification.
- Decision.

## Workaround Rule

Do not add a workaround until the gap is recorded.

The preferred decisions are:

- Change Cyna.
- Add a Cyna standard-library feature.
- Add a Cyna tooling feature.
- Accept a temporary workaround after recording the limitation.


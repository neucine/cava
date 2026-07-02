# Cava

Cava is a Cyna rewrite of [Zava](https://github.com/chaoyangnz/zava), a small Java VM originally written in Zig.

The goal is not to build a full JVM, add a JIT, or redesign Zava. The goal is to reimplement the behavior that Zava already supports, using the Zig codebase as the executable reference, while exercising Cyna on a real systems-programming workload.

## Purpose

Cava has two equal purposes:

- Reach behavior parity with the current Zava implementation.
- Identify Cyna language, runtime, standard-library, and tooling gaps.

When Cyna cannot express a Zava construct directly and cleanly, the port should pause and record the gap instead of hiding it behind a workaround.

## Scope

In scope:

- Current Zava classfile parser behavior.
- Current class loading model.
- Current method area and symbol/string interning.
- Current `Value`, `Reference`, `Object`, `Class`, `Field`, and `Method` model.
- Current heap allocation style.
- Current bytecode interpreter loop.
- Current implemented JVM bytecodes.
- Current exception handling behavior.
- Current native method bridge.
- Current example programs and supported JDK classes.

Out of scope:

- Garbage collection.
- JIT compilation.
- JVM verifier.
- Full JVM compliance.
- Threading and concurrency.
- Performance redesign.
- New class library support beyond what Zava already runs.
- Architecture refactoring before parity.

## Project Rule

If Zig Zava supports it, Cava should support it.

If Zig Zava panics, leaves it TODO, or does not support it, Cava may do the same until parity is reached.

If Cyna has a language, runtime, library, or tooling limitation that prevents a clean port, stop at the smallest reproducible case and document it in `docs/gap-log.md`.

## Documentation

- [Scope](docs/scope.md)
- [Porting Plan](docs/porting-plan.md)
- [Cyna Gap Policy](docs/cyna-gap-policy.md)
- [Gap Log](docs/gap-log.md)

## Tracing

Set `CAVA_TRACE=1` to print each executed bytecode instruction:

```sh
CAVA_TRACE=1 ./build/cava examples/classes/HelloWorld.class
```

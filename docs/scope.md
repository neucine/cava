# Scope

Cava is a parity rewrite of Zava in Cyna.

The Java VM is the workload. The broader purpose is to test whether Cyna is ready for systems application development.

## Reference Implementation

Reference repository:

```text
https://github.com/chaoyangnz/zava
```

Reference rule:

```text
Zava behavior is the specification until Cava reaches parity.
```

This includes both supported behavior and unsupported behavior. If Zava currently panics or leaves a feature unimplemented, Cava does not need to improve it during the parity phase.

## In Scope

- Classfile parsing as currently implemented by Zava.
- Runtime class representation.
- Method area and class loading.
- Symbol/string interning.
- Java value representation.
- Object and array allocation.
- Operand stack and local variable frame model.
- Bytecode dispatch and implemented instructions.
- Method invocation.
- Static and instance field access.
- Exceptions as currently handled.
- Native methods as currently implemented.
- Existing Zava examples and supported JDK classes.

## Out of Scope

- Full JVM specification compliance.
- Bytecode verifier.
- Garbage collector.
- JIT compiler.
- Threads and monitors beyond current Zava behavior.
- Performance-oriented redesign.
- Broader Java standard library compatibility.
- Semantic changes intended to make Zava more complete.

## Compatibility Target

The first compatibility target is to run the same example programs that Zava already supports, with equivalent stdout and comparable execution traces.

Known examples from Zava:

- `HelloWorld`
- `Base62`
- `Calendar`
- `Pyramid`


# Cava

Cava is a [Cyna](https://cyna.dev) rewrite of [Zava](https://github.com/chaoyangnz/zava), a small Java VM originally written in Zig.

The goal is not to build a full JVM, add a JIT, or redesign Zava. The goal is to reimplement the behavior that Zava already supports, using the Zig codebase as the executable reference, while exercising Cyna on a real systems-programming workload.

I am proud to be the author of Cyna. ✨🚀💛

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
- A simple post-parity stop-the-world mark/sweep garbage collector.

Out of scope:

- Moving, generational, concurrent, or performance-oriented garbage collection.
- JIT compilation.
- JVM verifier.
- Full JVM compliance.
- Performance redesign.
- New class library support beyond what Zava already runs.
- Architecture refactoring before parity.

## Project Rule

If Zig Zava supports it, Cava should support it.

If Zig Zava panics, leaves it TODO, or does not support it, Cava may do the same until parity is reached.

If Cyna has a language, runtime, library, or tooling limitation that prevents a clean port, stop at the smallest reproducible case and record it in Cyna's `docs/LANGUAGE_GAPS.md`. Do not create a Cava-local Cyna gap log.

## Documentation

- [Scope](docs/scope.md)
- [Porting Plan](docs/porting-plan.md)
- [Cyna Gap Policy](docs/cyna-gap-policy.md)
- [Historical Porting Findings](docs/gap-log.md) (closed to new Cyna entries)

## Testing

Cava requires Cyna 0.4.0 with compiler fixes through commit
`b62ab8b9750c1f90b15b4e68b4d4553c693525b3` on
`neucine/cyna` `master`. Put that compiler's
`zig-out/bin` on `PATH` before building or testing Cava. The initial 0.4.0
release lacks fixes needed by this migration.

Cava tests live beside their production modules as `src/*.test.cy` files.
Each test file explicitly imports its sibling module and is compiled as an
independent root:

```sh
cyna test
```

Use `cyna build --verbose` for phase progress or `cyna build --timings` for a
phase summary after compilation.

## Java Threads

Java threads execute in parallel on native threads. Frame-only bytecodes
(locals, arithmetic, branches, and returns) have handlers that cannot access
the VM and run without its lock. Array loads/stores and length checks use a
separate concurrent array-storage guard, not the metadata lock. Class loading,
field resolution, static-field operations, and native VM services use scoped
metadata critical sections. These operations remain serialized; this is not
yet per-object or per-class locking throughout the VM.

Each frame owns bytecode and constant-pool snapshots. Method calls release the
metadata guard while the callee executes and reacquire it before resuming the
caller. Class initialization tracks the initializing native thread, permits
recursive initialization by that owner, and makes other threads wait for
completion. Monitor contention and sleep/yield release their metadata scope
while blocked; there is no periodic whole-VM execution quantum.

The runtime records worker handles and joins them, including workers started
by workers, before clearing or destroying VM state. Worker registration retains
the correct Java `currentThread()` identity. This is not a claim of complete
JVM concurrency or full `Object.wait`/notification semantics.

### Specification boundaries

Internal storage guards and Java synchronization are different layers. Narrowing
an internal guard must preserve the following Java-level requirements:

- [JVMS 2.11.10](https://docs.oracle.com/javase/specs/jvms/se8/html/jvms-2.html#jvms-2.11.10):
  explicit monitor entry/exit and implicit `ACC_SYNCHRONIZED` method monitors.
  A synchronized instance method locks its receiver; a synchronized static method
  locks its declaring class's `Class` object. Ownership is reentrant and must be
  released on both normal and abrupt method completion. Cava handles explicit
  monitor bytecodes and wraps interpreted and native method entry with the same
  monitor acquisition API. Method exit releases that acquisition on ordinary
  return, a Java exception, or an interpreter/native error. Contended acquisition
  releases the metadata guard while waiting, never another Java monitor.
- [JVMS 5.5](https://docs.oracle.com/javase/specs/jvms/se8/html/jvms-5.html#jvms-5.5):
  class/interface initialization requires coordinated ownership, recursive entry
  by the initializing thread, waiting by other threads, and failure handling.
  Cava tracks ownership and completion/failure; this does not establish complete
  initialization exception compatibility.
- [JLS 17.4.5](https://docs.oracle.com/javase/specs/jls/se8/html/jls-17.html#jls-17.4.5):
  monitor release/acquire, volatile writes/reads, thread start, and successful
  join establish happens-before relationships. Current field operations share
  the metadata guard; any future field-lock split must preserve publication
  across fields and arrays, not merely make individual accesses race-free.
- [JLS 17.2](https://docs.oracle.com/javase/specs/jls/se8/html/jls-17.html#jls-17.2)
  defines wait sets and notification; those native operations remain stubs here.
  [JLS 17.3](https://docs.oracle.com/javase/specs/jls/se8/html/jls-17.html#jls-17.3)
  specifies that sleep/yield do not provide synchronization semantics, and sleep
  does not release Java monitors. Releasing Cava's metadata guard while sleeping
  must never release an owned Java monitor.

Keep these semantic boundaries explicit at runtime APIs rather than distributing
additional locks through opcode bodies. The current tests demonstrate supported
parallel execution, not full Java Memory Model compliance.

The parallel-progress regression starts two actual interpreter workers at an
array-backed barrier, then holds the metadata guard while both perform
arithmetic and publish completion through arrays. It tests independent progress
without timing-based speedup assertions.

Thread smoke checks (after building Cava):

```sh
javac --release 8 -d examples/classes examples/sources/ThreadSynchronizationSmoke.java
javac --release 8 -d examples/classes examples/sources/ThreadParallelSmoke.java
javac --release 8 -d examples/classes examples/sources/SynchronizedMethodSmoke.java
./build/cava examples/classes/ThreadStartSmoke.class
./build/cava examples/classes/ThreadSynchronizationSmoke.class
./build/cava examples/classes/ThreadParallelSmoke.class
./build/cava examples/classes/SynchronizedMethodSmoke.class
```

The synchronized-method smoke covers receiver-monitor reentrancy, static-method
agreement with an explicit class monitor, Java exception release, preservation
of monitor ownership across sleep/yield, and independent progress of methods
locking different receivers. Unit tests also cover synchronized native entry
and cleanup after interpreter/native errors.

## Tracing

Set `CAVA_TRACE=1` to print each executed bytecode instruction:

```sh
CAVA_TRACE=1 ./build/cava examples/classes/HelloWorld.class
```

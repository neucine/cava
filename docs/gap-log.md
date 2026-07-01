# Gap Log

This file records Cyna language, runtime, library, and tooling gaps found while porting Zava to Cava.

## Template

```md
## YYYY-MM-DD: Short Title

Module:

Zava construct:

Smallest Cyna reproduction:

Expected capability:

Current blocker:

Classification:

Decision:

Status:
```

## Open Gaps

## 2026-06-30: JVM Constant-Pool Object Constants

Module: `src/instruction.cy`

Zava construct: `ldc` and `ldc_w` can materialize `String`, `Class`, method type, method handle, and dynamic constants in addition to primitive numeric constants.

Smallest Cyna reproduction:

```cyna
fn load_string_constant(index: u16): Reference {
    // Cava needs to resolve the constant-pool string, intern or allocate a
    // java/lang/String object, and push its heap reference.
    assert(false);
    return null_ref;
}
```

Expected capability: Cava needs method-area/class context and Java object construction for constant-pool entries whose JVM value is a heap object or dynamically linked value.

Current blocker: `Context` now carries a constant-pool view, and Cava can construct `java/lang/String`, class mirror, and `java/lang/invoke/MethodType` constants. It does not yet construct method handles or dynamic constants.

Classification: Cava Runtime Gap.

Decision: Implement `ldc`/`ldc_w` primitive numeric constants, `CONSTANT_Class`, `CONSTANT_String`, and `CONSTANT_MethodType`; implement `ldc2_w` primitive wide numeric constants. Return `InstructionError.invalid_constant` for method handles and dynamic constants until method-handle and bootstrap linking are designed.

Status: Open.

## 2026-06-30: JVM Array Exception Construction for Bytecode Array Ops

Module: `src/instruction.cy`

Zava construct: `newarray`, `iaload`, `iastore`, `arraylength`, and null `athrow` throw Java exceptions for negative sizes, null array references, out-of-bounds indexes, and rethrowing a null throwable.

Smallest Cyna reproduction:

```cyna
fn load(heap: &Heap, reference: Reference, index: i32): i32 {
    if reference.is_null() or index < 0 {
        // Cava needs to throw NullPointerException or ArrayIndexOutOfBoundsException.
        assert(false);
    }
    return 0;
}
```

Expected capability: Cava should allocate the correct Java exception object and return `FrameResult.exception`, then later route it through method exception handlers.

Current blocker: Cava has a heap and `FrameResult.exception`, but not Java exception object construction or handler search in the interpreter loop.

Classification: Cava Runtime Gap.

Decision: Implement normal paths for primitive int array creation, load, store, length, and non-null `athrow` now. Keep exceptional paths that require constructing a Java exception object explicit with `assert(false)` until Java exception dispatch exists.

Status: Open.

## 2026-06-30: JVM Floating-Point NaN and Saturating Conversion Semantics

Module: `src/instruction.cy`

Zava construct: `fcmpl`, `fcmpg`, `dcmpl`, `dcmpg`, `f2i`, `f2l`, `d2i`, `d2l`, `f2d`, and `d2f` preserve JVM floating-point edge semantics, including NaN ordering choices, infinities, signed zero, truncation toward zero, and saturation for integer conversions.

Smallest Cyna reproduction:

```cyna
fn convert(value: f64): i32 {
    // Cyna checked casts require finite in-range exact values.
    // JVM d2i must instead map NaN to 0 and out-of-range values to int bounds.
    return value as i32;
}
```

Expected capability: Cava needs either runtime helpers for JVM float comparison/conversion or Cyna primitives that expose unordered/NaN checks and unchecked/saturating float casts.

Current blocker: Cyna lowers float comparisons to ordered LLVM predicates and checked float casts enforce finite/exact conversion. That is good Cyna semantics, but it cannot directly express JVM bytecode edge behavior.

Classification: Cava Runtime Gap with possible Cyna runtime/helper support.

Decision: Implement `i2f`, `i2d`, `l2f`, and `l2d` now because mixed integer/float arithmetic lowers to raw integer-to-float conversion. Keep the NaN-sensitive compare and float-to-int/float-to-float opcodes unsupported until Cava has explicit JVM helpers.

Status: Open.

## 2026-06-30: JVM ArithmeticException Construction for Integer Div/Rem

Module: `src/instruction.cy`

Zava construct: `idiv`, `ldiv`, `irem`, and `lrem` throw `java/lang/ArithmeticException` when the divisor is zero.

Smallest Cyna reproduction:

```cyna
fn div(value: i32, divisor: i32): i32 {
    if divisor == 0 {
        // Cava needs to allocate and throw java/lang/ArithmeticException here.
        assert(false);
    }
    return value / divisor;
}
```

Expected capability: Cava needs method-area lookup plus heap construction for `java/lang/ArithmeticException`, then instruction execution should set `FrameResult.exception` instead of asserting or trapping.

Current blocker: Cava has `Frame.throw_exception` and a `FrameResult.exception` carrier, but the interpreter does not yet allocate Java exception objects or search exception handlers.

Classification: Cava Runtime Gap.

Decision: Implement the non-zero normal paths for `idiv`, `ldiv`, `irem`, and `lrem` now. Keep zero-divisor behavior explicit with `assert(false)` until Java exception allocation/handler dispatch exists.

Status: Open.

## 2026-06-29: Dynamic Filesystem Path String Leaks Through std.fs

Module: `src/method_area.cy`

Zava construct: classpath loading builds `<root>/<class>.class`, reads the bytes, and keeps classfile storage alive while runtime metadata borrows from it.

Smallest Cyna reproduction:

```cyna
import { read_file } from std.fs;

fn main(): i32 {
    var path = string.from("/tmp/Main.class".bytes());
    const result = read_file(path);
    drop path;
    const ignored = result;
    return 0;
}
```

Expected capability: Passing a dynamically built `string` to `std.fs.read_file` should not leave a live allocation after the caller drops the path and any returned source string is cleaned up.

Current blocker: A classpath-loading test that writes `/tmp/CavaLoaderTest.class`, builds the path with `class_file_path`, and calls `read_file(path)` passes functionally but fails Cyna runtime leak checking with one live allocation. Attempting to retain owned dense class bytes directly as `List<[:]u8>` also exposed a Cyna sema crash in dense-array type interning, so Cava cannot currently use that as a storage workaround.

Classification: Runtime / Tooling Gap.

Decision: Keep parsed-byte loading and path construction in Cava. Keep the `load_class_from_path` API shape, but do not enable the filesystem integration test until the dynamic `std.fs` string leak and/or dense-array list crash is fixed in Cyna. For now, classfile metadata tests use caller-owned byte buffers.

Status: Open.

## 2026-06-29: Method-Area String Bytes View Cannot Escape

Module: `src/method_area.cy`

Zava construct: method-area interning stores class names and descriptors in an arena, then runtime metadata carries views to those stable bytes.

Smallest Cyna reproduction:

```cyna
struct Metadata {
    name: []const u8;
}

fn derive(name: string): Metadata {
    return Metadata { name: name.bytes() };
}
```

Expected capability: Cava needs JVM-origin metadata to point at bytes that outlive the derived `Class`, either by forwarding classfile-owned `[]const u8` views or by storing owned interned bytes in method-area storage. Implementation-owned synthesized metadata may use Cyna `string` when Cava/Cyna controls the lifetime.

Current blocker: Cyna intentionally rejects returning `string.bytes()` from a by-value `string` parameter, including inside a returned struct, because the byte view is tied to the local `string` parameter. Returning a struct containing a `[]const u8` parameter view is supported and is used by `derive_array_class`.

Classification: Design Gap.

Decision: Do not derive long-lived JVM-origin metadata through by-value `string.bytes()`. Keep method-area APIs slice-based (`[]const u8`) for classfile and interned-symbol bytes. Use Cyna `string` for implementation-owned synthesized metadata such as `Class.name` and `Class.descriptor`, and build those strings with `string.from` so the bytes are copied into Cyna-owned storage.

Status: Fixed locally.

## 2026-06-30: JVM Logical Right Shift Needs Integer Bit Reinterpretation

Module: `src/instruction.cy`

Zava construct: `iushr` and `lushr` implement logical right shift by reinterpreting signed integer bits as the same-width unsigned integer, shifting, then reinterpreting the result back to the signed JVM value type.

Smallest Cyna reproduction:

```cyna
fn logical_shift(value: i32, amount: i32): i32 {
    const bits: u32 = value as! u32;
    return (bits >> (amount & 31)) as! i32;
}
```

Expected capability: Cava needs an explicit bit reinterpretation path between same-width signed and unsigned integer types to model JVM logical right shift for negative `int` values.

Current blocker: Fixed in Cyna by allowing `as!` between explicit same-width integer types, such as `i32` to `u32` and `i64` to `u64`, while continuing to reject width mismatches.

Classification: Tooling Gap.

Decision: Implemented `iushr` and `lushr` in Cava using same-width integer `as!` reinterpretation.

Status: Fixed locally.

## 2026-06-29: Borrowed Union Payload Return From List Storage

Module: `src/classfile.cy`

Zava construct: classfile helper functions return borrowed UTF-8 constant-pool payloads when resolving class names, names, and descriptors.

Smallest Cyna reproduction:

```cyna
union Entry {
    text: []const u8;
    other: i32;
}

struct Table {
    entries: List<Entry>;

    fn text(self: &Table, index: usize): []const u8 {
        switch self.entries[index] {
        case .text(bytes) {
            return bytes;
        }
        case .other(value) {
            const ignored = value;
            return "".bytes();
        }
        }
    }
}
```

Expected capability: A method borrowing `self` should be able to return a borrowed slice payload from storage reachable through `self`, with the returned slice provenance tied to the receiver borrow.

Current blocker: `cyna check` rejected the return with `borrowed values cannot escape the function via return`. Switching directly on `self.entries[index]` treated the captured slice as escaping a temporary rather than as a borrow from the receiver.

Classification: Semantic Gap.

Decision: Fixed in Cyna by letting switch payload captures prefer return-safe provenance from the switch subject projection, while preserving existing payload provenance for local unions that already carry borrowed data from elsewhere. Cava now exposes direct borrowed-return constant-pool helpers again.

Status: Fixed locally.

## 2026-06-28: Widening i32 to usize Cast Range Check

Module: `src/classfile.cy`

Zava construct: using a list length as a `usize` index bound while resolving constant-pool indexes.

Smallest Cyna reproduction:

```cyna
fn main(): i32 {
    var values: List<i32> = [];
    values.push(1);
    values.push(2);
    const len = values.len() as usize;
    var result: i32 = 1;
    if len == 2 {
        result = 0;
    }
    drop values;
    return result;
}
```

Expected capability: Widening a non-negative `i32` to `usize` should not trap when the value is in range.

Current blocker: Native execution trapped in the generated cast range check for normal values such as list lengths.

Classification: Tooling Gap.

Decision: Fixed in Cyna by widening source integer values narrower than 64 bits to `i64` before comparing against target cast bounds.

Status: Fixed locally.

## 2026-06-28: Optional Struct Global Constant Codegen

Module: `src/types.cy`

Zava construct: `pub const NULL: Reference = .{ .ptr = null };`

Smallest Cyna reproduction:

```cyna
struct Reference {
    object_id: ?u64;
}

const null_ref: Reference = Reference { object_id: none };

fn main(): i32 {
    if null_ref.object_id == none {
        return 0;
    }
    return 1;
}
```

Expected capability: A top-level optional constant, and a top-level struct constant containing an optional field, should lower to valid native code.

Current blocker: `cyna check` succeeds, but native compilation emits invalid LLVM IR for the constant initializer: `expected value token`.

Root cause: `compiler/backend/llvm/emitter.zig` prints the LLVM type inside `emitGlobalInit` for optional initializers. The callers already print the storage or field type, so optional constants are emitted with duplicate type text. For example:

```llvm
@nothing = constant { i8, i64 } { i8, i64 } zeroinitializer
```

and inside a struct field:

```llvm
@null_ref = constant { { i8, i64 } } { { i8, i64 } { i8, i64 } zeroinitializer }
```

The initializer should emit only the value form, such as `zeroinitializer`, when the surrounding global or field has already emitted the type.

Classification: Tooling Gap.

Decision: Fixed in the local Cyna compiler by making optional global initializers emit initializer values only. Cyna supports explicit `Type.init(...)`-style functions for runtime construction, but not hidden constructors and not function-call initializers for top-level constants.

Status: Fixed locally.

## 2026-06-28: Borrowed Indexed Projection Into Resource List Lowering

Module: `src/types.cy`

Zava construct: `Class.method(...)` iterates over method metadata and checks fields of each `Method`.

Smallest Cyna reproduction:

```cyna
struct Method {
    code: List<i8>;
    name: string;
}

struct Class {
    methods: List<Method>;

    fn method_index(self: &Class, name: string): ?i32 {
        var i: i32 = 0;
        while i < self.methods.len() {
            if self.methods[i].name == name {
                return i;
            }
            i = i + 1;
        }
        return none;
    }
}
```

Expected capability: Borrowed indexed projection into a list of resource-shaped structs should lower when only reading a non-resource field.

Current blocker: Previously, `cyna check` succeeded, but `cyna test` failed during lowering with `Unsupported` in `lowerAddressablePlacePointer` / borrowed index projection.

Classification: Tooling Gap.

Decision: Fixed in the local Cyna compiler. Cava now uses real `List<Field>` and `List<Method>` metadata, and the class metadata lookup test indexes through those lists successfully.

Status: Fixed locally.

## 2026-06-28: Borrowed Subslice From Existing Byte Slice

Module: `src/classfile.cy`

Zava construct: classfile reader keeps borrowed views into the original class bytes for `CONSTANT_Utf8` payloads.

Smallest Cyna reproduction:

```cyna
fn sub(data: []const u8, start: usize, end: usize): []const u8 {
    return data[start..end];
}
```

Expected capability: A parser should be able to return a bounded borrowed subslice from an existing `[]const u8` without copying bytes.

Current blocker: `cyna check` failed with `slice expression requires a view-producing foundation type or hook __view`.

Classification: Tooling Gap.

Decision: Fixed in the local Cyna compiler by allowing an existing slice to be a ranged-slice source. The derived slice keeps the same non-owning provenance root as the source view.

Status: Fixed locally.

## 2026-06-28: Slice Payload In List-Backed Union Switch Lowering

Module: `src/classfile.cy`

Zava construct: `CONSTANT_Utf8` entries store borrowed byte slices in constant-pool entries.

Smallest Cyna reproduction:

```cyna
union Entry {
    text: []const u8;
    other: i32;
}

fn first(entries: List<Entry>): i32 {
    switch entries[0] {
    case .text(bytes) {
        return bytes[0] as i32;
    }
    case .other(value) {
        return value;
    }
    }
}
```

Expected capability: A union containing a slice payload should be switchable after indexing through a list when the code only reads the borrowed payload.

Current blocker: Lowering failed with `Unsupported` in `lowerAddressablePlacePointer` / `lowerBorrowedIndexExpr` when Cava stored `CONSTANT_Utf8` as `[]const u8` and switched on `constants[index]`.

Classification: Tooling Gap.

Decision: Fixed in the local Cyna compiler by letting borrowed-index lowering materialize non-place array/slice/list-view values into a temporary, then index through that temporary. Cava now stores `CONSTANT_Utf8` payloads directly as `[]const u8`.

Status: Fixed locally.

## 2026-06-28: Owned List In Result Payload Leaks Runtime Storage

Module: `src/classfile.cy`

Zava construct: parser helpers return owned parsed containers or errors.

Smallest Cyna reproduction:

```cyna
enum E { bad = 0 }

fn make(): result<List<i32>, E> {
    var xs: List<i32> = [];
    xs.push(1);
    return .ok(xs);
}

fn run(): result<i32, E> {
    const xs = try make();
    drop xs;
    return .ok(0);
}
```

Expected capability: Returning an owned `List<T>` in a `result` success payload and then dropping the unwrapped value should release the list storage.

Current blocker: With Cyna runtime leak checking enabled, the unwrapped-and-dropped list reported a live allocation at process exit.

Root cause: Result union case lowering prepared resource-shaped payloads twice: `lowerUnionCaseExpr` captured the `.ok(...)` payload once, then `lowerResultCaseValue` captured it again before `make_result`. For owned payloads such as `List<T>`, the intermediate retained copy owned runtime storage but had no matching drop.

Classification: Tooling Gap.

Decision: Fixed in the local Cyna compiler by letting result-specific lowering perform the single required payload capture. Cava now returns the owned constant-pool list as `result<List<Constant>, ClassfileError>`.

Status: Fixed locally.

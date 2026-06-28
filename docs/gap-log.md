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

Current blocker: `cyna check` succeeds, but `cyna test` fails during lowering with `Unsupported` in `lowerAddressablePlacePointer` / borrowed index projection.

Classification: Tooling Gap.

Decision: Keep early `Method` metadata copyable for now by storing counts instead of owned lists. Reintroduce full list-backed method attributes when the method-area storage model is ported or the lowering gap is fixed.

Status: Open.

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

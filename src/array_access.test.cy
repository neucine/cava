import { Runtime, new_runtime } from .runtime;
import { VM } from .vm;
import { Reference, ReferenceKind, null_ref } from .types;

test "parallel array access rejects stale and out of bounds references" {
    const runtime = new_runtime();
    var reference = null_ref;
    switch runtime.state.with_result<i32, Reference>(0, fn (vm: &VM, ignored: i32): Reference {
        return vm.heap.allocate_array(0, "I".bytes(), 2);
    }) {
        case .ok(actual) {
            reference = actual;
        }
        case .err {
            assert(false);
        }
    }
    assert(runtime.arrays.set(reference, 0, .int_value(42)));
    if runtime.arrays.get(reference, 0) is value {
        switch value {
            case .int_value(actual) {
                assert(actual == 42);
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }
    const stale = Reference {
        kind: reference.kind,
        slot: reference.slot,
        generation: reference.generation + 1
    };
    const wrong_kind = Reference {
        kind: ReferenceKind.object,
        slot: reference.slot,
        generation: reference.generation
    };
    assert(runtime.arrays.get(stale, 0) == none);
    assert(runtime.arrays.length(stale) == none);
    assert(!runtime.arrays.set(stale, 0, .int_value(9)));
    assert(runtime.arrays.get(wrong_kind, 0) == none);
    assert(runtime.arrays.get(reference, 2) == none);
    assert(!runtime.arrays.set(reference, 2, .int_value(9)));
    runtime.finish();
}

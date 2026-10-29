import { Runtime, new_runtime } from .runtime;
import { VM } from .vm;
import { execute_method_frame_with_runtime, new_frame } from .engine;
import { Class, Method, Reference, Value, class_access_flags, method_access_flags, null_ref } from .types;
import { SyncStatus } from std.sync;
import { sleep_ms } from std.time;
import std.thread;

struct ParallelRequest {
    runtime: Runtime;
    array: Reference;
}

struct ParallelPair {
    runtime: Runtime;
    first: Reference;
    second: Reference;
}

fn install_parallel_method(vm: &VM, ignored: i32): void {
    const method = Method {
        class_name: "Parallel",
        access_flags: method_access_flags(8),
        name: "run",
        descriptor: "([I)V",
        code: [0x2a, 0x03, 0x04, 0x4f, 0x2a, 0x04, 0x2e, 0x99, 0xff, 0xfd,
            0x03, 0x3c, 0x1b, 0x11, 0x27, 0x10, 0xa2, 0x00, 0x09,
            0x84, 0x01, 0x01, 0xa7, 0xff, 0xf6, 0x2a, 0x05, 0x10, 0x2a, 0x4f, 0xb1
        ],
        max_stack: 3,
        max_locals: 2,
        code_len: 31,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 1,
        return_descriptor: "V",
    };
    const class = Class {
        name: "Parallel",
        descriptor: "LParallel;",
        access_flags: class_access_flags(1),
        super_class: "",
        interfaces: [],
        fields: [],
        methods: [method],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Parallel.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: true,
        class_object: null_ref,
    };
    vm.method_area.classes.push(class);
}

fn run_parallel_frame(vm: &VM, request: ParallelRequest): void {
    var frame = new_frame(0, 0, 2, 3);
    frame.store(0, .ref_value(request.array));
    const ignored_result = execute_method_frame_with_runtime(request.runtime.alias_handles(), vm, 0, 0, frame, vm.method_area.classes[0].constant_pool[..]) catch (problem) {
        assert(false);
        return;
    };
}

fn parallel_worker(request: ParallelRequest): void {
    assert(request.runtime.state.with<ParallelRequest>(request, run_parallel_frame) == SyncStatus.ok);
}

fn parallel_flag(runtime: &const Runtime, array: Reference, index: usize): i32 {
    if runtime.arrays.get(array, index) is value {
        return switch value {
            .int_value(actual) => actual;
            _ => unreachable;
        };
    }
    return 0;
}

fn await_parallel_completion(vm: &VM, pair: ParallelPair): void {
    assert(pair.runtime.arrays.set(pair.first, 1, .int_value(1)));
    assert(pair.runtime.arrays.set(pair.second, 1, .int_value(1)));
    var attempts: usize = 0;
    var done = false;
    while !done and attempts < 5000 {
        done = parallel_flag(&pair.runtime, pair.first, 2) == 42 and parallel_flag(&pair.runtime, pair.second, 2) == 42;
        if !done {
            sleep_ms(1) catch (problem) {
                assert(false);
                return;
            };
        }
        attempts = attempts + 1;
    }
    assert(done);
}

test "Java workers execute arithmetic and arrays while metadata is locked" {
    const runtime = new_runtime();
    assert(runtime.state.with<i32>(0, install_parallel_method) == SyncStatus.ok);
    var arrays: List<Reference> = [];
    var index: usize = 0;
    while index < 2 {
        const reference = runtime.state.with_result<i32, Reference>(0, fn (vm: &VM, ignored: i32): Reference {
            return vm.heap.allocate_array(0, "I".bytes(), 3);
        }) catch (problem) {
            assert(false);
            return;
        };
        arrays.push(reference);
        const worker = thread.spawn(parallel_worker, ParallelRequest {
            runtime: runtime.alias_handles(),
            array: arrays[index]
        }) catch (problem) {
            assert(false);
            return;
        };
        runtime.track(worker);
        index = index + 1;
    }
    var ready = false;
    var attempts: usize = 0;
    while !ready and attempts < 5000 {
        ready = parallel_flag(&runtime, arrays[0], 0) == 1 and parallel_flag(&runtime, arrays[1], 0) == 1;
        if !ready {
            sleep_ms(1) catch (problem) {
                assert(false);
                return;
            };
        }
        attempts = attempts + 1;
    }
    assert(ready);
    assert(runtime.state.with<ParallelPair>(ParallelPair {
        runtime: runtime.alias_handles(),
        first: arrays[0],
        second: arrays[1]
    }, await_parallel_completion) == SyncStatus.ok);
    runtime.finish();
}

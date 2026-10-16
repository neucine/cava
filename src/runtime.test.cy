import { Runtime, new_runtime } from .runtime;
import { VM } from .vm;
import std.sync;
import std.thread;
import { ConcurrentList, SyncStatus } from std.sync;

struct RuntimeTestRequest {
    runtime: Runtime;
    completed: ConcurrentList<usize>;
}

fn runtime_test_worker(request: RuntimeTestRequest): void {
    const status = request.runtime.state.with<RuntimeTestRequest>(request, fn (vm: &VM, actual: RuntimeTestRequest): void {
        var index: usize = 0;
        while index < 100 {
            vm.method_area.symbols.symbols.push("worker");
            index = index + 1;
        }
        assert(actual.completed.push(vm.method_area.symbols.symbols.len()) == SyncStatus.ok);
    });
    assert(status == SyncStatus.ok);
}

fn runtime_test_parent(request: RuntimeTestRequest): void {
    switch thread.spawn(runtime_test_worker, request) {
        case .ok(worker) {
            request.runtime.track(worker);
        }
        case .err {
            assert(false);
        }
    }
}

test "runtime shutdown also joins workers started by workers" {
    const runtime = new_runtime();
    const completed = sync.concurrent_list<usize>();
    switch thread.spawn(runtime_test_parent, RuntimeTestRequest {
        runtime: copy runtime,
        completed: copy completed
    }) {
        case .ok(worker) {
            runtime.track(worker);
        }
        case .err {
            assert(false);
        }
    }
    runtime.finish();
    switch completed.len() {
        case .ok(count) {
            assert(count == 1);
        }
        case .err {
            assert(false);
        }
    }
    assert(completed.destroy() == SyncStatus.ok);
}

test "runtime serializes metadata access and joins all workers before cleanup" {
    const runtime = new_runtime();
    const completed = sync.concurrent_list<usize>();
    var index: usize = 0;
    while index < 6 {
        switch thread.spawn(runtime_test_worker, RuntimeTestRequest {
            runtime: copy runtime,
            completed: copy completed
        }) {
            case .ok(worker) {
                runtime.track(worker);
            }
            case .err {
                assert(false);
            }
        }
        index = index + 1;
    }
    runtime.finish();
    switch completed.len() {
        case .ok(count) {
            assert(count == 6);
        }
        case .err {
            assert(false);
        }
    }
    assert(completed.destroy() == SyncStatus.ok);
}

test "runtime pause lets a worker enter while the calling Java thread sleeps" {
    const runtime = new_runtime();
    const completed = sync.concurrent_list<usize>();
    const request = RuntimeTestRequest {
        runtime: copy runtime,
        completed: copy completed
    };
    const status = runtime.state.with<RuntimeTestRequest>(request, fn (vm: &VM, actual: RuntimeTestRequest): void {
        switch thread.spawn(runtime_test_worker, actual) {
            case .ok(worker) {
                actual.runtime.track(worker);
            }
            case .err {
                assert(false);
            }
        }
        var ready = false;
        var attempts: usize = 0;
        while !ready and attempts < 1000 {
            assert(actual.runtime.pause(1));
            switch actual.completed.len() {
                case .ok(count) {
                    ready = count == 1;
                }
                case .err {
                    assert(false);
                }
            }
            attempts = attempts + 1;
        }
        assert(ready);
        assert(vm.method_area.symbols.symbols.len() == 100);
    });
    assert(status == SyncStatus.ok);
    runtime.finish();
    assert(completed.destroy() == SyncStatus.ok);
}

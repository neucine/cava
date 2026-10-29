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
    const worker = thread.spawn(runtime_test_worker, request) catch (problem) {
        assert(false);
        return;
    };
    request.runtime.track(worker);
}

test "runtime shutdown also joins workers started by workers" {
    const runtime = new_runtime();
    const completed = sync.concurrent_list<usize>();
    const worker = thread.spawn(runtime_test_parent, RuntimeTestRequest {
        runtime: runtime.alias_handles(),
        completed: completed
    }) catch (problem) {
        assert(false);
        return;
    };
    runtime.track(worker);
    runtime.finish();
    const count = completed.len() catch (problem) {
        assert(false);
        return;
    };
    assert(count == 1);
    assert(completed.destroy() == SyncStatus.ok);
}

test "runtime serializes metadata access and joins all workers before cleanup" {
    const runtime = new_runtime();
    const completed = sync.concurrent_list<usize>();
    var index: usize = 0;
    while index < 6 {
        const worker = thread.spawn(runtime_test_worker, RuntimeTestRequest {
            runtime: runtime.alias_handles(),
            completed: completed
        }) catch (problem) {
            assert(false);
            return;
        };
        runtime.track(worker);
        index = index + 1;
    }
    runtime.finish();
    const count = completed.len() catch (problem) {
        assert(false);
        return;
    };
    assert(count == 6);
    assert(completed.destroy() == SyncStatus.ok);
}

test "runtime pause lets a worker enter while the calling Java thread sleeps" {
    const runtime = new_runtime();
    const completed = sync.concurrent_list<usize>();
    const request = RuntimeTestRequest {
        runtime: runtime.alias_handles(),
        completed: completed
    };
    const status = runtime.state.with<RuntimeTestRequest>(request, fn (vm: &VM, actual: RuntimeTestRequest): void {
        const worker = thread.spawn(runtime_test_worker, actual) catch (problem) {
            assert(false);
            return;
        };
        actual.runtime.track(worker);
        var ready = false;
        var attempts: usize = 0;
        while !ready and attempts < 1000 {
            assert(actual.runtime.pause(1));
            const count = actual.completed.len() catch (problem) {
                assert(false);
                return;
            };
            ready = count == 1;
            attempts = attempts + 1;
        }
        assert(ready);
        assert(vm.method_area.symbols.symbols.len() == 100);
    });
    assert(status == SyncStatus.ok);
    runtime.finish();
    assert(completed.destroy() == SyncStatus.ok);
}

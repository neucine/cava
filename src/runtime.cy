import { VM, new_vm } from .vm;
import { ArrayAccess } from .array_access;
import { ClassInitializers, new_class_initializers } from .class_initialization;
import std.sync;
import { ConcurrentList, Shared, SyncStatus } from std.sync;
import std.thread;
import { sleep_ms } from std.time;

struct RuntimeWorker {
    handle: thread.Thread;
}

pub struct Runtime {
    pub state: Shared<VM>;
    pub arrays: ArrayAccess;
    pub initializers: ClassInitializers;
    workers: ConcurrentList<RuntimeWorker>;

    pub fn alias_handles(self: &const Runtime): Runtime {
        return Runtime {
            state: self.state,
            arrays: self.arrays.alias_handle(),
            initializers: self.initializers.alias_handle(),
            workers: self.workers
        };
    }

    pub fn track(self: &const Runtime, worker: thread.Thread): void {
        assert(self.workers.push(RuntimeWorker {
            handle: worker
        }) == SyncStatus.ok);
    }

    pub fn pause(self: &const Runtime, millis: i64): bool {
        assert(self.state.unlock() == SyncStatus.ok);
        var succeeded = true;
        sleep_ms(millis) catch (err) {
            succeeded = false;
        };
        assert(self.state.lock() == SyncStatus.ok);
        return succeeded;
    }

    pub fn finish(self: &const Runtime): void {
        var draining = true;
        while draining {
            var worker: ?RuntimeWorker = none;
            worker = self.workers.with_result<i32, ?RuntimeWorker>(0, fn (workers: &List<RuntimeWorker>, ignored: i32): ?RuntimeWorker {
                if workers.len() > 0 {
                    return workers.pop();
                }
                return none;
            }) catch (err) {
                assert(false);
                return;
            };
            if worker is actual {
                switch actual.handle.join() {
                    .settled => {}
                    .retry => unreachable;
                }
            } else {
                draining = false;
            }
        }
        const cleared = self.state.with<i32>(0, fn (vm: &VM, ignored: i32): void {
            vm.destroy();
        });
        assert(cleared == SyncStatus.ok);
        assert(self.state.destroy() == SyncStatus.ok);
        assert(self.workers.destroy() == SyncStatus.ok);
        self.initializers.destroy();
    }
}

pub fn new_runtime(): Runtime {
    const vm = new_vm();
    const arrays = ArrayAccess {
        storage: vm.heap.arrays
    };
    return Runtime {
        state: sync.shared(vm),
        arrays: arrays,
        initializers: new_class_initializers(),
        workers: sync.concurrent_list<RuntimeWorker>()
    };
}

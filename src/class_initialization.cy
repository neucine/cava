import std.sync;
import std.thread;
import { ConcurrentList, SyncStatus } from std.sync;

pub enum InitializationDecision: i32 {
    run_initializer,
    recursive,
    complete,
    failed,
    waiting,
}

struct ClassInitialization {
    index: usize;
    owner: thread.ThreadId;
    complete: bool;
    failed: bool;
}

struct InitializationRequest {
    index: usize;
    owner: thread.ThreadId;
}

pub struct ClassInitializers {
    storage: ConcurrentList<ClassInitialization>;

    @syntax.copy
    pub fn clone(self: &const ClassInitializers): ClassInitializers {
        return ClassInitializers {
            storage: copy self.storage
        };
    }

    pub fn begin(self: &const ClassInitializers, index: usize): InitializationDecision {
        const request = InitializationRequest {
            index: index,
            owner: thread.current_id()
        };
        switch self.storage.with_result<InitializationRequest, InitializationDecision>(request, fn (entries: &List<ClassInitialization>, actual: InitializationRequest): InitializationDecision {
            var index: usize = 0;
            while index < entries.len() {
                const state = entries[index];
                if state.index == actual.index {
                    if state.failed {
                        return InitializationDecision.failed;
                    }
                    if state.complete {
                        return InitializationDecision.complete;
                    }
                    if state.owner.equals(actual.owner) {
                        return InitializationDecision.recursive;
                    }
                    return InitializationDecision.waiting;
                }
                index = index + 1;
            }
            entries.push(ClassInitialization {
                index: actual.index,
                owner: actual.owner,
                complete: false,
                failed: false
            });
            return InitializationDecision.run_initializer;
        }) {
            case .ok(decision) {
                return decision;
            }
            case .err {
                assert(false);
            }
        }
        return InitializationDecision.failed;
    }

    pub fn finish(self: &const ClassInitializers, index: usize, succeeded: bool): void {
        const request = ClassInitialization {
            index: index,
            owner: thread.current_id(),
            complete: true,
            failed: !succeeded
        };
        assert(self.storage.with<ClassInitialization>(request, fn (entries: &List<ClassInitialization>, actual: ClassInitialization): void {
            var index: usize = 0;
            while index < entries.len() {
                if entries[index].index == actual.index {
                    assert(entries[index].owner.equals(actual.owner));
                    entries[index] = actual;
                    return;
                }
                index = index + 1;
            }
            assert(false);
        }) == SyncStatus.ok);
    }

    pub fn destroy(self: &const ClassInitializers): void {
        assert(self.storage.destroy() == SyncStatus.ok);
    }
}

pub fn new_class_initializers(): ClassInitializers {
    return ClassInitializers {
        storage: sync.concurrent_list<ClassInitialization>()
    };
}

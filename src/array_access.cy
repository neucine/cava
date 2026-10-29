import { ArrayObject } from .heap;
import { Reference, ReferenceKind, Value } from .types;
import { ConcurrentSlotMap } from std.sync;

struct ArrayLookup {
    key: SlotMapKey;
    index: usize;
}

struct ArrayUpdate {
    lookup: ArrayLookup;
    value: Value;
}

pub struct ArrayAccess {
    pub storage: ConcurrentSlotMap<ArrayObject>;

    pub fn alias_handle(self: &const ArrayAccess): ArrayAccess {
        return ArrayAccess {
            storage: self.storage
        };
    }

    pub fn length(self: &const ArrayAccess, reference: Reference): ?usize {
        if reference.kind != ReferenceKind.array {
            return none;
        }
        if reference.slot is slot {
            const key = SlotMapKey {
                index: slot,
                generation: reference.generation
            };
            return self.storage.with_result<SlotMapKey, ?usize>(key, fn (arrays: &SlotMap<ArrayObject>, actual: SlotMapKey): ?usize {
                if arrays.contains(actual) {
                    if &arrays.slots[actual.index] is array {
                        return array.elements.len();
                    }
                }
                return none;
            }) catch (problem) {
                return none;
            };
        }
        return none;
    }

    pub fn get(self: &const ArrayAccess, reference: Reference, index: usize): ?Value {
        if reference.kind != ReferenceKind.array {
            return none;
        }
        if reference.slot is slot {
            const lookup = ArrayLookup {
                key: SlotMapKey {
                    index: slot,
                    generation: reference.generation
                },
                index: index
            };
            return self.storage.with_result<ArrayLookup, ?Value>(lookup, fn (arrays: &SlotMap<ArrayObject>, actual: ArrayLookup): ?Value {
                if arrays.contains(actual.key) {
                    if &arrays.slots[actual.key.index] is array {
                        if actual.index < array.elements.len() {
                            return array.elements[actual.index];
                        }
                    }
                }
                return none;
            }) catch (problem) {
                return none;
            };
        }
        return none;
    }

    pub fn set(self: &const ArrayAccess, reference: Reference, index: usize, value: Value): bool {
        if reference.kind != ReferenceKind.array {
            return false;
        }
        if reference.slot is slot {
            const update = ArrayUpdate {
                lookup: ArrayLookup {
                    key: SlotMapKey {
                        index: slot,
                        generation: reference.generation
                    },
                    index: index
                },
                value: value
            };
            return self.storage.with_result<ArrayUpdate, bool>(update, fn (arrays: &SlotMap<ArrayObject>, actual: ArrayUpdate): bool {
                if arrays.contains(actual.lookup.key) {
                    if take arrays.slots[actual.lookup.key.index] is taken_array {
                        var array = taken_array;
                        var updated = false;
                        if actual.lookup.index < array.elements.len() {
                            array.elements[actual.lookup.index] = actual.value;
                            updated = true;
                        }
                        arrays.slots.insert(actual.lookup.key.index, array);
                        return updated;
                    }
                }
                return false;
            }) catch (problem) {
                return false;
            };
        }
        return false;
    }
}

import { Class, Field, Method, Reference, ReferenceKind, Value, byte_buffer, class_access_flags, default_value, field_access_flags, null_ref } from .types;
import std.sync;
import { ConcurrentSlotMap, Mutex, SyncStatus } from std.sync;
import { ThreadId, current_id } from std.thread;
import { sleep_ms } from std.time;

pub struct Object {
    pub class_index: usize;
    pub fields: List<Value>;
}

pub struct ArrayObject {
    pub class_index: usize;
    pub elements: List<Value>;
}

pub struct InternedString {
    pub value: [:]u8;
    pub reference: Reference;
}

pub struct InternedStringBytes {
    pub value: [:]u8;
}

pub struct InternedMethodType {
    pub descriptor: string;
    pub reference: Reference;
}

pub struct InternedMethodHandle {
    pub reference_kind: u8;
    pub reference_index: u16;
    pub reference: Reference;
}

pub struct Monitor {
    pub reference: Reference;
    pub mutex: Mutex;
    pub owner: ?ThreadId;
    pub depth: u32;
}

pub struct JavaThreadState {
    pub reference: Reference;
    pub native_id: ?ThreadId;
    pub started: bool;
    pub alive: bool;
    pub interrupted: bool;
}

struct IndexedSlotMapKey {
    key: SlotMapKey;
    index: usize;
}

struct IndexedValueUpdate {
    key: SlotMapKey;
    index: usize;
    value: Value;
}

pub struct Heap {
    pub objects: ConcurrentSlotMap<Object>;
    pub arrays: ConcurrentSlotMap<ArrayObject>;
    pub strings: List<InternedString>;
    pub method_types: List<InternedMethodType>;
    pub method_handles: List<InternedMethodHandle>;
    pub current_thread: ?Reference;
    pub java_threads: List<JavaThreadState>;
    pub java_threads_mutex: Mutex;
    pub java_threads_active: bool;
    pub monitors: List<Monitor>;
    pub monitor_table_mutex: Mutex;
    pub monitor_table_active: bool;

    pub fn clear(self: &Heap): void {
        while self.strings.len() > 0 {
            var value = self.strings.pop();
        }
        while self.monitors.len() > 0 {
            const monitor = self.monitors.pop();
            const ignored_destroy = monitor.mutex.destroy();
        }
        const ignored_objects_clear = self.objects.with<i32>(0, fn (objects: &SlotMap<Object>, ignored: i32): void {
            const unused = ignored;
            objects.clear();
        });
        const ignored_arrays_clear = self.arrays.with<i32>(0, fn (arrays: &SlotMap<ArrayObject>, ignored: i32): void {
            const unused = ignored;
            arrays.clear();
        });
        self.method_types.clear();
        self.method_handles.clear();
        self.current_thread = none;
        self.java_threads.clear();
        if self.java_threads_active {
            const ignored_destroy_threads = self.java_threads_mutex.destroy();
            self.java_threads_active = false;
        }
        if self.monitor_table_active {
            const ignored_destroy = self.monitor_table_mutex.destroy();
            self.monitor_table_active = false;
        }
    }

    pub fn allocate_object(self: &Heap, class_index: usize, class: &Class): Reference {
        var fields: List<Value> = [];
        var index: usize = 0;
        while index < class.fields.len() {
            const field = class.fields[index];
            if !field.is_static() {
                fields.push(default_value(field.descriptor.bytes()));
            }
            index = index + 1;
        }

        const key = self.objects.insert(Object {
            class_index: class_index,
            fields: fields,
        }) catch (problem) {
            return null_ref;
        };
        return Reference {
            kind: ReferenceKind.object,
            slot: key.index,
            generation: key.generation,
        };
    }

    pub fn allocate_object_with_hierarchy(self: &Heap, class_index: usize, classes: []Class): Reference {
        var fields: List<Value> = [];
        append_hierarchy_fields(&fields, class_index, classes);

        const key = self.objects.insert(Object {
            class_index: class_index,
            fields: fields,
        }) catch (problem) {
            return null_ref;
        };
        return Reference {
            kind: ReferenceKind.object,
            slot: key.index,
            generation: key.generation,
        };
    }

    pub fn allocate_array(self: &Heap, class_index: usize, component_descriptor: []const u8, length: usize): Reference {
        var elements: List<Value> = [];
        var index: usize = 0;
        while index < length {
            elements.push(default_value(component_descriptor));
            index = index + 1;
        }

        const key = self.arrays.insert(ArrayObject {
            class_index: class_index,
            elements: elements,
        }) catch (problem) {
            return null_ref;
        };
        return Reference {
            kind: ReferenceKind.array,
            slot: key.index,
            generation: key.generation,
        };
    }

    pub fn intern_string(self: &Heap, class_index: usize, class: &Class, value: []const u8): Reference {
        var index: usize = 0;
        while index < self.strings.len() {
            if self.strings[index].value[..] == value {
                return self.strings[index].reference;
            }
            index = index + 1;
        }

        const reference = self.allocate_object(class_index, class);
        self.strings.push(InternedString {
            value: byte_buffer(value),
            reference: reference,
        });
        return reference;
    }

    pub fn intern_string_buffer(self: &Heap, class_index: usize, class: &Class, data: [:]u8): Reference {
        var bytes = data;
        var index: usize = 0;
        while index < self.strings.len() {
            if self.strings[index].value[..] == bytes[..] {
                const existing = self.strings[index].reference;
                return existing;
            }
            index = index + 1;
        }

        const reference = self.allocate_object(class_index, class);
        self.strings.push(InternedString {
            value: bytes,
            reference: reference,
        });
        return reference;
    }

    pub fn register_string_bytes(self: &Heap, reference: Reference, value: []const u8): void {
        var index: usize = 0;
        while index < self.strings.len() {
            if self.strings[index].reference.equals(reference) {
                return;
            }
            index = index + 1;
        }
        self.strings.push(InternedString {
            value: byte_buffer(value),
            reference: reference,
        });
    }

    pub fn interned_string_reference(self: &Heap, value: []const u8): ?Reference {
        var index: usize = 0;
        while index < self.strings.len() {
            if self.strings[index].value[..] == value {
                return self.strings[index].reference;
            }
            index = index + 1;
        }
        return none;
    }

    pub fn string_bytes(self: &Heap, reference: Reference): ?InternedStringBytes {
        var index: usize = 0;
        while index < self.strings.len() {
            if self.strings[index].reference.equals(reference) {
                return InternedStringBytes {
                    value: byte_buffer(self.strings[index].value[..])
                };
            }
            index = index + 1;
        }
        return none;
    }

    pub fn concat_strings(self: &Heap, class_index: usize, class: &Class, left_reference: Reference, right_reference: Reference): Reference {
        var byte_count: usize = 0;
        var left_index: ?usize = none;
        var right_index: ?usize = none;
        var index: usize = 0;
        while index < self.strings.len() {
            if self.strings[index].reference.equals(left_reference) {
                left_index = index;
                byte_count = byte_count + self.strings[index].value.len();
            }
            if self.strings[index].reference.equals(right_reference) {
                right_index = index;
                byte_count = byte_count + self.strings[index].value.len();
            }
            index = index + 1;
        }

        var bytes = [: byte_count]u8;
        if left_index is actual_left {
            var left_byte: usize = 0;
            while left_byte < self.strings[actual_left].value.len() {
                bytes.push(self.strings[actual_left].value[left_byte]);
                left_byte = left_byte + 1;
            }
        }
        if right_index is actual_right {
            var right_byte: usize = 0;
            while right_byte < self.strings[actual_right].value.len() {
                bytes.push(self.strings[actual_right].value[right_byte]);
                right_byte = right_byte + 1;
            }
        }
        return self.intern_string_buffer(class_index, class, bytes);
    }

    pub fn intern_method_type(self: &Heap, class_index: usize, class: &Class, descriptor: []const u8): Reference {
        var index: usize = 0;
        while index < self.method_types.len() {
            const method_type = &self.method_types[index];
            if method_type.descriptor.bytes() == descriptor {
                return method_type.reference;
            }
            index = index + 1;
        }

        const reference = self.allocate_object(class_index, class);
        const needle = string.from(descriptor);
        self.method_types.push(InternedMethodType {
            descriptor: needle,
            reference: reference,
        });
        return reference;
    }

    pub fn intern_method_handle(self: &Heap, class_index: usize, class: &Class, reference_kind: u8, reference_index: u16): Reference {
        var index: usize = 0;
        while index < self.method_handles.len() {
            if self.method_handles[index].reference_kind == reference_kind and self.method_handles[index].reference_index == reference_index {
                return self.method_handles[index].reference;
            }
            index = index + 1;
        }

        const reference = self.allocate_object(class_index, class);
        self.method_handles.push(InternedMethodHandle {
            reference_kind: reference_kind,
            reference_index: reference_index,
            reference: reference,
        });
        return reference;
    }

    pub fn object_index(self: &Heap, reference: Reference): ?usize {
        if reference.kind != ReferenceKind.object {
            return none;
        }
        if reference.slot is slot {
            const key = SlotMapKey {
                index: slot,
                generation: reference.generation
            };
            if self.objects.contains(key) catch (problem) {
                return none;
            }
            {
                return slot;
            }
        }
        return none;
    }

    pub fn has_object(self: &Heap, reference: Reference): bool {
        return self.object_index(reference) != none;
    }

    pub fn object_count(self: &Heap): usize {
        return self.objects.len() catch (problem) => 0;
    }

    pub fn object_class_index(self: &Heap, reference: Reference): ?usize {
        if self.object_index(reference) is object_index {
            const key = SlotMapKey {
                index: object_index,
                generation: reference.generation
            };
            return self.objects.with_result<SlotMapKey, ?usize>(key, fn (objects: &SlotMap<Object>, actual_key: SlotMapKey): ?usize {
                if &objects.slots[actual_key.index] is object {
                    return object.class_index;
                }
                return none;
            }) catch (problem) => none;
        }
        return none;
    }

    pub fn array_index(self: &Heap, reference: Reference): ?usize {
        if reference.kind != ReferenceKind.array {
            return none;
        }
        if reference.slot is slot {
            const key = SlotMapKey {
                index: slot,
                generation: reference.generation
            };
            if self.arrays.contains(key) catch (problem) {
                return none;
            }
            {
                return slot;
            }
        }
        return none;
    }

    pub fn has_array(self: &Heap, reference: Reference): bool {
        return self.array_index(reference) != none;
    }

    pub fn array_count(self: &Heap): usize {
        return self.arrays.len() catch (problem) => 0;
    }

    pub fn array_length(self: &Heap, reference: Reference): ?usize {
        if self.array_index(reference) is array_index_value {
            const key = SlotMapKey {
                index: array_index_value,
                generation: reference.generation
            };
            return self.arrays.with_result<SlotMapKey, ?usize>(key, fn (arrays: &SlotMap<ArrayObject>, actual_key: SlotMapKey): ?usize {
                if &arrays.slots[actual_key.index] is array {
                    return array.elements.len();
                }
                return none;
            }) catch (problem) => none;
        }
        return none;
    }

    pub fn array_class_index(self: &Heap, reference: Reference): ?usize {
        if self.array_index(reference) is array_index_value {
            const key = SlotMapKey {
                index: array_index_value,
                generation: reference.generation
            };
            return self.arrays.with_result<SlotMapKey, ?usize>(key, fn (arrays: &SlotMap<ArrayObject>, actual_key: SlotMapKey): ?usize {
                if &arrays.slots[actual_key.index] is array {
                    return array.class_index;
                }
                return none;
            }) catch (problem) => none;
        }
        return none;
    }

    pub fn get_element(self: &Heap, reference: Reference, index: usize): ?Value {
        if self.array_index(reference) is array_index_value {
            const lookup = IndexedSlotMapKey {
                key: SlotMapKey {
                    index: array_index_value,
                    generation: reference.generation
                },
                index: index
            };
            return self.arrays.with_result<IndexedSlotMapKey, ?Value>(lookup, fn (arrays: &SlotMap<ArrayObject>, actual: IndexedSlotMapKey): ?Value {
                if &arrays.slots[actual.key.index] is array {
                    if actual.index < array.elements.len() {
                        return array.elements[actual.index];
                    }
                }
                return none;
            }) catch (problem) => none;
        }
        return none;
    }

    pub fn set_element(self: &Heap, reference: Reference, index: usize, value: Value): bool {
        if self.array_index(reference) is array_index_value {
            const update = IndexedValueUpdate {
                key: SlotMapKey {
                    index: array_index_value,
                    generation: reference.generation
                },
                index: index,
                value: value
            };
            return self.arrays.with_result<IndexedValueUpdate, bool>(update, fn (arrays: &SlotMap<ArrayObject>, actual: IndexedValueUpdate): bool {
                if take arrays.slots[actual.key.index] is taken_array {
                    var array = taken_array;
                    if actual.index < array.elements.len() {
                        array.elements[actual.index] = actual.value;
                        arrays.slots.insert(actual.key.index, array);
                        return true;
                    }
                    arrays.slots.insert(actual.key.index, array);
                }
                return false;
            }) catch (problem) => false;
        }
        return false;
    }

    pub fn get_field(self: &Heap, reference: Reference, slot: u16): ?Value {
        if self.object_index(reference) is object_index {
            const actual_slot = slot as usize;
            const lookup = IndexedSlotMapKey {
                key: SlotMapKey {
                    index: object_index,
                    generation: reference.generation
                },
                index: actual_slot
            };
            return self.objects.with_result<IndexedSlotMapKey, ?Value>(lookup, fn (objects: &SlotMap<Object>, actual: IndexedSlotMapKey): ?Value {
                if &objects.slots[actual.key.index] is object {
                    if actual.index < object.fields.len() {
                        return object.fields[actual.index];
                    }
                }
                return none;
            }) catch (problem) => none;
        }
        return none;
    }

    pub fn set_field(self: &Heap, reference: Reference, slot: u16, value: Value): bool {
        if self.object_index(reference) is object_index {
            const actual_slot = slot as usize;
            const update = IndexedValueUpdate {
                key: SlotMapKey {
                    index: object_index,
                    generation: reference.generation
                },
                index: actual_slot,
                value: value
            };
            return self.objects.with_result<IndexedValueUpdate, bool>(update, fn (objects: &SlotMap<Object>, actual: IndexedValueUpdate): bool {
                if take objects.slots[actual.key.index] is taken_object {
                    var object = taken_object;
                    if actual.index < object.fields.len() {
                        object.fields[actual.index] = actual.value;
                        objects.slots.insert(actual.key.index, object);
                        return true;
                    }
                    objects.slots.insert(actual.key.index, object);
                }
                return false;
            }) catch (problem) => false;
        }
        return false;
    }

    pub fn current_thread_ref(self: &Heap): ?Reference {
        const current = current_monitor_owner_id();
        if !lock_ok(self.java_threads_mutex) {
            return self.current_thread;
        }
        const index = self.java_thread_index_by_id(current);
        var reference = self.current_thread;
        if index is actual_index {
            reference = self.java_threads[actual_index].reference;
        }
        if !unlock_ok(self.java_threads_mutex) {
            return self.current_thread;
        }
        return reference;
    }

    pub fn set_current_thread(self: &Heap, reference: Reference): void {
        self.current_thread = reference;
        const current = current_monitor_owner_id();
        const ignored = self.register_current_java_thread(reference, current, true, true);
    }

    pub fn register_current_java_thread(self: &Heap, reference: Reference, native_id: ThreadId, started: bool, alive: bool): bool {
        if !lock_ok(self.java_threads_mutex) {
            return false;
        }
        if self.java_thread_index(reference) is existing_index {
            var state = self.java_threads[existing_index];
            state.native_id = native_id;
            state.started = started;
            state.alive = alive;
            self.java_threads[existing_index] = state;
            const ignored_unlock_existing = unlock_ok(self.java_threads_mutex);
            return true;
        }
        self.java_threads.push(JavaThreadState {
            reference: reference,
            native_id: native_id,
            started: started,
            alive: alive,
            interrupted: false,
        });
        const ignored_unlock_new = unlock_ok(self.java_threads_mutex);
        return true;
    }

    pub fn mark_java_thread_started(self: &Heap, reference: Reference): bool {
        if !lock_ok(self.java_threads_mutex) {
            return false;
        }
        if self.java_thread_index(reference) is existing_index {
            var state = self.java_threads[existing_index];
            state.started = true;
            state.alive = true;
            self.java_threads[existing_index] = state;
        } else {
            self.java_threads.push(JavaThreadState {
                reference: reference,
                native_id: none,
                started: true,
                alive: true,
                interrupted: false,
            });
        }
        const ignored_unlock = unlock_ok(self.java_threads_mutex);
        return true;
    }

    pub fn mark_java_thread_finished(self: &Heap, reference: Reference): bool {
        if !lock_ok(self.java_threads_mutex) {
            return false;
        }
        if self.java_thread_index(reference) is existing_index {
            var state = self.java_threads[existing_index];
            state.alive = false;
            self.java_threads[existing_index] = state;
        }
        const ignored_unlock = unlock_ok(self.java_threads_mutex);
        return true;
    }

    pub fn java_thread_alive(self: &Heap, reference: Reference): bool {
        if !lock_ok(self.java_threads_mutex) {
            return false;
        }
        const index = self.java_thread_index(reference);
        var alive = false;
        if index is actual_index {
            alive = self.java_threads[actual_index].alive;
        }
        if !unlock_ok(self.java_threads_mutex) {
            return false;
        }
        return alive;
    }

    pub fn java_thread_started(self: &Heap, reference: Reference): bool {
        if !lock_ok(self.java_threads_mutex) {
            return false;
        }
        const index = self.java_thread_index(reference);
        var started = false;
        if index is actual_index {
            started = self.java_threads[actual_index].started;
        }
        if !unlock_ok(self.java_threads_mutex) {
            return false;
        }
        return started;
    }

    pub fn monitor_enter(self: &Heap, reference: Reference): bool {
        var acquired = false;
        while !acquired {
            if self.monitor_try_enter(reference) is actual {
                acquired = actual;
            } else {
                return false;
            }
            if !acquired {
                sleep_ms(1) catch (problem) {
                    return false;
                };
            }
        }
        return true;
    }

    pub fn monitor_try_enter(self: &Heap, reference: Reference): ?bool {
        if reference.is_null() {
            return none;
        }
        if !lock_ok(self.monitor_table_mutex) {
            return none;
        }
        const monitor_index = self.monitor_index_or_create(reference);
        if monitor_index is actual_index {
            const current = current_monitor_owner_id();
            var monitor = self.monitors[actual_index];
            if monitor.owner is owner {
                if owner.equals(current) {
                    monitor.depth = monitor.depth + 1;
                    self.monitors[actual_index] = monitor;
                    const ignored_unlock_reentrant = unlock_ok(self.monitor_table_mutex);
                    return true;
                }
            }
            const mutex = monitor.mutex;
            const status = mutex.try_lock();
            if status != SyncStatus.ok {
                const ignored_unlock_busy = unlock_ok(self.monitor_table_mutex);
                if status == SyncStatus.busy {
                    return false;
                }
                return none;
            }
            monitor.owner = current;
            monitor.depth = 1;
            self.monitors[actual_index] = monitor;
            const ignored_unlock_acquired = unlock_ok(self.monitor_table_mutex);
            return true;
        }
        const ignored_unlock_missing = unlock_ok(self.monitor_table_mutex);
        return none;
    }

    pub fn monitor_exit(self: &Heap, reference: Reference): bool {
        if reference.is_null() {
            return false;
        }
        const current = current_monitor_owner_id();
        if !lock_ok(self.monitor_table_mutex) {
            return false;
        }
        const monitor_index = self.monitor_index(reference);
        if !unlock_ok(self.monitor_table_mutex) {
            return false;
        }
        if monitor_index is actual_index {
            var monitor = self.monitors[actual_index];
            if monitor.owner is owner {
                if owner.equals(current) {
                    if monitor.depth > 1 {
                        monitor.depth = monitor.depth - 1;
                        self.monitors[actual_index] = monitor;
                        return true;
                    }
                    monitor.depth = 0;
                    monitor.owner = none;
                    const mutex = monitor.mutex;
                    self.monitors[actual_index] = monitor;
                    return unlock_ok(mutex);
                }
            }
        }
        return false;
    }

    pub fn monitor_held_by_current_thread(self: &Heap, reference: Reference): bool {
        if reference.is_null() {
            return false;
        }
        const current = current_monitor_owner_id();
        if !lock_ok(self.monitor_table_mutex) {
            return false;
        }
        const monitor_index = self.monitor_index(reference);
        if !unlock_ok(self.monitor_table_mutex) {
            return false;
        }
        if monitor_index is actual_index {
            if self.monitors[actual_index].owner is owner {
                if owner.equals(current) {
                    return self.monitors[actual_index].depth > 0;
                }
            }
        }
        return false;
    }

    fn monitor_index(self: &Heap, reference: Reference): ?usize {
        var index: usize = 0;
        while index < self.monitors.len() {
            if self.monitors[index].reference.equals(reference) {
                return index;
            }
            index = index + 1;
        }
        return none;
    }

    fn monitor_index_or_create(self: &Heap, reference: Reference): ?usize {
        if self.monitor_index(reference) is existing {
            return existing;
        }
        const mutex = Mutex.init();
        if !mutex.is_valid() {
            return none;
        }
        self.monitors.push(Monitor {
            reference: reference,
            mutex: mutex,
            owner: none,
            depth: 0,
        });
        return self.monitors.len() - 1;
    }

    fn java_thread_index(self: &Heap, reference: Reference): ?usize {
        var index: usize = 0;
        while index < self.java_threads.len() {
            if self.java_threads[index].reference.equals(reference) {
                return index;
            }
            index = index + 1;
        }
        return none;
    }

    fn java_thread_index_by_id(self: &Heap, native_id: ThreadId): ?usize {
        var index: usize = 0;
        while index < self.java_threads.len() {
            if self.java_threads[index].native_id is actual_id {
                if actual_id.equals(native_id) {
                    return index;
                }
            }
            index = index + 1;
        }
        return none;
    }
}

fn lock_ok(mutex: Mutex): bool {
    return mutex.lock() == SyncStatus.ok;
}

fn unlock_ok(mutex: Mutex): bool {
    return mutex.unlock() == SyncStatus.ok;
}

fn current_monitor_owner_id(): ThreadId {
    return current_id();
}

fn find_class_index(classes: []Class, name: string): ?usize {
    var index: usize = 0;
    while index < classes.len() {
        if classes[index].name == name {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn append_hierarchy_fields(fields: &List<Value>, class_index: usize, classes: []Class): void {
    if class_index >= classes.len() {
        return;
    }
    const super_name = classes[class_index].super_class;
    if super_name != "" {
        if find_class_index(classes, super_name) is super_index {
            append_hierarchy_fields(fields, super_index, classes);
        }
    }

    var field_index: usize = 0;
    while field_index < classes[class_index].fields.len() {
        const field = classes[class_index].fields[field_index];
        if !field.is_static() {
            fields.push(default_value(field.descriptor.bytes()));
        }
        field_index = field_index + 1;
    }
}

pub fn new_heap(): Heap {
    return Heap {
        objects: sync.concurrent_slot_map<Object>(),
        arrays: sync.concurrent_slot_map<ArrayObject>(),
        strings: [],
        method_types: [],
        method_handles: [],
        current_thread: none,
        java_threads: list<JavaThreadState>(),
        java_threads_mutex: Mutex.init(),
        java_threads_active: true,
        monitors: [],
        monitor_table_mutex: Mutex.init(),
        monitor_table_active: true,
    };
}

fn assert_int_value(value: Value, expected: i32): void {
    switch value {
        .int_value(actual) => assert(actual == expected);
        .byte_value => unreachable;
        .short_value => unreachable;
        .char_value => unreachable;
        .long_value => unreachable;
        .float_value => unreachable;
        .double_value => unreachable;
        .boolean_value => unreachable;
        .return_address_value => unreachable;
        .ref_value => unreachable;
    }
}

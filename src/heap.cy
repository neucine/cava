import { Class, Field, Method, Reference, ReferenceKind, Value, byte_buffer, class_access_flags, default_value, field_access_flags, null_ref } from .types;

pub struct Object {
    pub class_index: usize;
    pub fields: List<Value>;
}

pub struct ArrayObject {
    pub class_index: usize;
    pub elements: List<Value>;
}

pub struct ObjectSlot {
    pub occupied: bool;
    pub generation: u64;
    pub object: Object;
}

pub struct ArraySlot {
    pub occupied: bool;
    pub generation: u64;
    pub array: ArrayObject;
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

pub struct Heap {
    pub objects: List<ObjectSlot>;
    pub arrays: List<ArraySlot>;
    pub strings: List<InternedString>;
    pub method_types: List<InternedMethodType>;
    pub method_handles: List<InternedMethodHandle>;
    pub current_thread: ?Reference;

    pub fn clear(self: &Heap): void {
        while self.strings.len() > 0 {
            var value = self.strings.pop();
            drop value;
        }
        self.objects.clear();
        self.arrays.clear();
        self.method_types.clear();
        self.method_handles.clear();
        self.current_thread = none;
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

        const slot = self.objects.len();
        self.objects.push(ObjectSlot {
            occupied: true,
            generation: 1,
            object: Object {
                class_index: class_index,
                fields: fields,
            },
        });
        return Reference {
            kind: ReferenceKind.object,
            slot: slot,
            generation: 1,
        };
    }

    pub fn allocate_object_with_hierarchy(self: &Heap, class_index: usize, classes: []Class): Reference {
        var fields: List<Value> = [];
        append_hierarchy_fields(&fields, class_index, classes);

        const slot = self.objects.len();
        self.objects.push(ObjectSlot {
            occupied: true,
            generation: 1,
            object: Object {
                class_index: class_index,
                fields: fields,
            },
        });
        return Reference {
            kind: ReferenceKind.object,
            slot: slot,
            generation: 1,
        };
    }

    pub fn allocate_array(self: &Heap, class_index: usize, component_descriptor: []const u8, length: usize): Reference {
        var elements: List<Value> = [];
        var index: usize = 0;
        while index < length {
            elements.push(default_value(component_descriptor));
            index = index + 1;
        }

        const slot = self.arrays.len();
        self.arrays.push(ArraySlot {
            occupied: true,
            generation: 1,
            array: ArrayObject {
                class_index: class_index,
                elements: elements,
            },
        });
        return Reference {
            kind: ReferenceKind.array,
            slot: slot,
            generation: 1,
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
                drop bytes;
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
                return InternedStringBytes { value: byte_buffer(self.strings[index].value[..]) };
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
        const needle = string.from(descriptor);
        var index: usize = 0;
        while index < self.method_types.len() {
            if self.method_types[index].descriptor == needle {
                const existing = self.method_types[index].reference;
                drop needle;
                return existing;
            }
            index = index + 1;
        }

        const reference = self.allocate_object(class_index, class);
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
            if slot < self.objects.len() {
                if self.objects[slot].occupied and self.objects[slot].generation == reference.generation {
                    return slot;
                }
            }
        }
        return none;
    }

    pub fn has_object(self: &Heap, reference: Reference): bool {
        return self.object_index(reference) != none;
    }

    pub fn object_class_index(self: &Heap, reference: Reference): ?usize {
        if self.object_index(reference) is object_index {
            return self.objects[object_index].object.class_index;
        }
        return none;
    }

    pub fn array_index(self: &Heap, reference: Reference): ?usize {
        if reference.kind != ReferenceKind.array {
            return none;
        }
        if reference.slot is slot {
            if slot < self.arrays.len() {
                if self.arrays[slot].occupied and self.arrays[slot].generation == reference.generation {
                    return slot;
                }
            }
        }
        return none;
    }

    pub fn has_array(self: &Heap, reference: Reference): bool {
        return self.array_index(reference) != none;
    }

    pub fn array_length(self: &Heap, reference: Reference): ?usize {
        if self.array_index(reference) is array_index_value {
            return self.arrays[array_index_value].array.elements.len();
        }
        return none;
    }

    pub fn array_class_index(self: &Heap, reference: Reference): ?usize {
        if self.array_index(reference) is array_index_value {
            return self.arrays[array_index_value].array.class_index;
        }
        return none;
    }

    pub fn get_element(self: &Heap, reference: Reference, index: usize): ?Value {
        if self.array_index(reference) is array_index_value {
            if index < self.arrays[array_index_value].array.elements.len() {
                return self.arrays[array_index_value].array.elements[index];
            }
        }
        return none;
    }

    pub fn set_element(self: &Heap, reference: Reference, index: usize, value: Value): bool {
        if self.array_index(reference) is array_index_value {
            if index < self.arrays[array_index_value].array.elements.len() {
                self.arrays[array_index_value].array.elements[index] = value;
                return true;
            }
        }
        return false;
    }

    pub fn get_field(self: &Heap, reference: Reference, slot: u16): ?Value {
        if self.object_index(reference) is object_index {
            const actual_slot = slot as usize;
            if actual_slot < self.objects[object_index].object.fields.len() {
                return self.objects[object_index].object.fields[actual_slot];
            }
        }
        return none;
    }

    pub fn set_field(self: &Heap, reference: Reference, slot: u16, value: Value): bool {
        if self.object_index(reference) is object_index {
            const actual_slot = slot as usize;
            if actual_slot < self.objects[object_index].object.fields.len() {
                self.objects[object_index].object.fields[actual_slot] = value;
                return true;
            }
        }
        return false;
    }

    pub fn current_thread_ref(self: &Heap): ?Reference {
        return self.current_thread;
    }

    pub fn set_current_thread(self: &Heap, reference: Reference): void {
        self.current_thread = reference;
    }
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
        objects: [],
        arrays: [],
        strings: [],
        method_types: [],
        method_handles: [],
        current_thread: none,
    };
}

fn assert_int_value(value: Value, expected: i32): void {
    switch value {
    case .int_value(actual) { assert(actual == expected); }
    case .byte_value(actual) { const ignored = actual; assert(false); }
    case .short_value(actual) { const ignored = actual; assert(false); }
    case .char_value(actual) { const ignored = actual; assert(false); }
    case .long_value(actual) { const ignored = actual; assert(false); }
    case .float_value(actual) { const ignored = actual; assert(false); }
    case .double_value(actual) { const ignored = actual; assert(false); }
    case .boolean_value(actual) { const ignored = actual; assert(false); }
    case .return_address_value(actual) { const ignored = actual; assert(false); }
    case .ref_value(actual) { const ignored = actual; assert(false); }
    }
}

test "heap allocates objects with default instance fields" {
    const static_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(0x0008),
        name: "counter",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(0x0001),
        name: "value",
        descriptor: "I",
        index: 1,
        slot: 0,
    };
    var class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [static_field, instance_field],
        methods: [],
        constant_pool: [],
        instance_vars: 1,
        static_vars: [.int_value(0)],
        source_file: "Example.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };

    var heap = new_heap();
    const reference = heap.allocate_object(0, &class);
    assert(reference.non_null());
    assert(heap.has_object(reference));
    assert(heap.objects.len() == 1);
    assert(heap.objects[0].occupied);
    assert(heap.objects[0].generation == reference.generation);
    assert(heap.objects[0].object.class_index == 0);
    assert(heap.objects[0].object.fields.len() == 1);

    if heap.get_field(reference, 0) is value {
        assert_int_value(value, 0);
    } else {
        assert(false);
    }
}

test "heap updates instance fields by slot" {
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(0x0001),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [instance_field],
        methods: [],
        constant_pool: [],
        instance_vars: 1,
        static_vars: [],
        source_file: "Example.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };

    var heap = new_heap();
    const reference = heap.allocate_object(0, &class);
    assert(heap.set_field(reference, 0, .int_value(42)));
    assert(!heap.set_field(reference, 1, .int_value(1)));
    assert(!heap.set_field(Reference.init_null(), 0, .int_value(1)));

    if heap.get_field(reference, 0) is value {
        assert_int_value(value, 42);
    } else {
        assert(false);
    }
    assert(heap.get_field(reference, 1) == none);
    assert(heap.get_field(Reference.init_null(), 0) == none);
}

test "heap rejects stale object slot references" {
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(0x0001),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [instance_field],
        methods: [],
        constant_pool: [],
        instance_vars: 1,
        static_vars: [],
        source_file: "Example.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };

    var heap = new_heap();
    const reference = heap.allocate_object(0, &class);
    const stale = Reference {
        kind: ReferenceKind.object,
        slot: reference.slot,
        generation: reference.generation + 1,
    };
    assert(heap.has_object(reference));
    assert(!heap.has_object(stale));
    assert(heap.get_field(stale, 0) == none);
}

test "heap allocates primitive arrays with default elements" {
    var heap = new_heap();
    const reference = heap.allocate_array(0, "I".bytes(), 3);

    assert(reference.non_null());
    assert(heap.has_array(reference));
    assert(!heap.has_object(reference));
    if heap.array_length(reference) is length {
        assert(length == 3);
    } else {
        assert(false);
    }

    if heap.get_element(reference, 0) is value {
        assert_int_value(value, 0);
    } else {
        assert(false);
    }
    if heap.get_element(reference, 2) is value {
        assert_int_value(value, 0);
    } else {
        assert(false);
    }
    assert(heap.get_element(reference, 3) == none);
}

test "heap updates array elements by index" {
    var heap = new_heap();
    const reference = heap.allocate_array(0, "I".bytes(), 2);

    assert(heap.set_element(reference, 1, .int_value(42)));
    assert(!heap.set_element(reference, 2, .int_value(1)));
    assert(!heap.set_element(Reference.init_null(), 0, .int_value(1)));

    if heap.get_element(reference, 1) is value {
        assert_int_value(value, 42);
    } else {
        assert(false);
    }
}

test "heap allocates reference arrays with null elements" {
    var heap = new_heap();
    const reference = heap.allocate_array(0, "Ljava/lang/Object;".bytes(), 1);

    if heap.get_element(reference, 0) is value {
        switch value {
        case .ref_value(actual) { assert(actual.is_null()); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }
}

test "heap interns string objects by byte content" {
    var string_class = Class {
        name: string.from("java/lang/String".bytes()),
        descriptor: "Ljava/lang/String;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "String.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var heap = new_heap();

    const first = heap.intern_string(0, &string_class, "hello".bytes());
    const second = heap.intern_string(0, &string_class, "hello".bytes());
    const third = heap.intern_string(0, &string_class, "world".bytes());

    assert(first.equals(second));
    assert(!first.equals(third));
    assert(heap.objects.len() == 2);
    assert(heap.strings.len() == 2);
    assert(heap.strings[0].value[..] == "hello".bytes());
    assert(heap.strings[1].value[..] == "world".bytes());
}

test "heap interns method type objects by descriptor" {
    var method_type_class = Class {
        name: string.from("java/lang/invoke/MethodType".bytes()),
        descriptor: "Ljava/lang/invoke/MethodType;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "MethodType.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var heap = new_heap();

    const first = heap.intern_method_type(0, &method_type_class, "(I)V".bytes());
    const second = heap.intern_method_type(0, &method_type_class, "(I)V".bytes());
    const third = heap.intern_method_type(0, &method_type_class, "()V".bytes());

    assert(first.equals(second));
    assert(!first.equals(third));
    assert(heap.objects.len() == 2);
    assert(heap.method_types.len() == 2);
    assert(heap.method_types[0].descriptor == "(I)V");
    assert(heap.method_types[1].descriptor == "()V");
}

test "heap interns method handle objects by reference kind and index" {
    var method_handle_class = Class {
        name: string.from("java/lang/invoke/MethodHandle".bytes()),
        descriptor: "Ljava/lang/invoke/MethodHandle;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "MethodHandle.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var heap = new_heap();

    const first = heap.intern_method_handle(0, &method_handle_class, 6, 7);
    const second = heap.intern_method_handle(0, &method_handle_class, 6, 7);
    const third = heap.intern_method_handle(0, &method_handle_class, 5, 7);
    const fourth = heap.intern_method_handle(0, &method_handle_class, 6, 8);

    assert(first.equals(second));
    assert(!first.equals(third));
    assert(!first.equals(fourth));
    assert(heap.objects.len() == 3);
    assert(heap.method_handles.len() == 3);
    assert(heap.method_handles[0].reference_kind == 6);
    assert(heap.method_handles[0].reference_index == 7);
}

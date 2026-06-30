import { Class, Field, Method, Reference, ReferenceKind, Value, class_access_flags, default_value, field_access_flags, null_ref } from .types;

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

pub struct Heap {
    pub objects: List<ObjectSlot>;
    pub arrays: List<ArraySlot>;

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

    pub fn allocate_array(self: &Heap, class_index: usize, component_descriptor: string, length: usize): Reference {
        var elements: List<Value> = [];
        var index: usize = 0;
        while index < length {
            elements.push(default_value(component_descriptor.bytes()));
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
}

pub fn new_heap(): Heap {
    return Heap {
        objects: [],
        arrays: [],
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
    const reference = heap.allocate_array(0, "I", 3);

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
    const reference = heap.allocate_array(0, "I", 2);

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
    const reference = heap.allocate_array(0, "Ljava/lang/Object;", 1);

    if heap.get_element(reference, 0) is value {
        switch value {
        case .ref_value(actual) { assert(actual.is_null()); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }
}

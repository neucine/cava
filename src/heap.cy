import { Class, Field, Method, Name, Reference, Value, class_access_flags, default_value, field_access_flags, null_ref } from .types;

pub struct Object {
    pub id: u64;
    pub class_index: usize;
    pub fields: List<Value>;
}

pub struct Heap {
    pub objects: List<Object>;
    pub next_id: u64;

    pub fn allocate_object(self: &Heap, class_index: usize, class: &Class): Reference {
        const id = self.next_id;
        self.next_id = self.next_id + 1;

        var fields: List<Value> = [];
        var index: usize = 0;
        while index < class.fields.len() {
            const field = class.fields[index];
            if !field.is_static() {
                fields.push(default_value(field.descriptor));
            }
            index = index + 1;
        }

        self.objects.push(Object {
            id: id,
            class_index: class_index,
            fields: fields,
        });
        return Reference { object_id: id };
    }

    pub fn object_index(self: &Heap, reference: Reference): ?usize {
        if reference.object_id is id {
            var index: usize = 0;
            while index < self.objects.len() {
                if self.objects[index].id == id {
                    return index;
                }
                index = index + 1;
            }
        }
        return none;
    }

    pub fn has_object(self: &Heap, reference: Reference): bool {
        return self.object_index(reference) != none;
    }

    pub fn get_field(self: &Heap, reference: Reference, slot: u16): ?Value {
        if self.object_index(reference) is object_index {
            const actual_slot = slot as usize;
            if actual_slot < self.objects[object_index].fields.len() {
                return self.objects[object_index].fields[actual_slot];
            }
        }
        return none;
    }

    pub fn set_field(self: &Heap, reference: Reference, slot: u16, value: Value): bool {
        if self.object_index(reference) is object_index {
            const actual_slot = slot as usize;
            if actual_slot < self.objects[object_index].fields.len() {
                self.objects[object_index].fields[actual_slot] = value;
                return true;
            }
        }
        return false;
    }
}

pub fn new_heap(): Heap {
    return Heap {
        objects: [],
        next_id: 1,
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
        class_name: "Example".bytes(),
        access_flags: field_access_flags(0x0008),
        name: "counter".bytes(),
        descriptor: "I".bytes(),
        index: 0,
        slot: 0,
    };
    const instance_field = Field {
        class_name: "Example".bytes(),
        access_flags: field_access_flags(0x0001),
        name: "value".bytes(),
        descriptor: "I".bytes(),
        index: 1,
        slot: 0,
    };
    var class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object".bytes(),
        interfaces: [],
        fields: [static_field, instance_field],
        methods: [],
        instance_vars: 1,
        static_vars: [.int_value(0)],
        source_file: "Example.java".bytes(),
        is_array: false,
        component_type: "".bytes(),
        element_type: "".bytes(),
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
    assert(heap.objects[0].class_index == 0);
    assert(heap.objects[0].fields.len() == 1);

    if heap.get_field(reference, 0) is value {
        assert_int_value(value, 0);
    } else {
        assert(false);
    }
}

test "heap updates instance fields by slot" {
    const instance_field = Field {
        class_name: "Example".bytes(),
        access_flags: field_access_flags(0x0001),
        name: "value".bytes(),
        descriptor: "I".bytes(),
        index: 0,
        slot: 0,
    };
    var class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object".bytes(),
        interfaces: [],
        fields: [instance_field],
        methods: [],
        instance_vars: 1,
        static_vars: [],
        source_file: "Example.java".bytes(),
        is_array: false,
        component_type: "".bytes(),
        element_type: "".bytes(),
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

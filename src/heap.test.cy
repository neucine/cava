import {
    Class, Field, Method, Reference, ReferenceKind,
    Value, byte_buffer, class_access_flags, default_value, field_access_flags,
    null_ref
} from .types;
import { Mutex, SyncStatus } from std.sync;
import { ThreadId, current_id } from std.thread;
import {
    Object, ArrayObject, InternedString, InternedStringBytes, InternedMethodType,
    InternedMethodHandle, Monitor, Heap, lock_ok, unlock_ok,
    current_monitor_owner_id, find_class_index, append_hierarchy_fields, new_heap, assert_int_value
} from .heap;

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
    if heap.object_class_index(reference) is class_index {
        assert(class_index == 0);
    } else {
        assert(false);
    }

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

test "heap monitors are reentrant for current native thread" {
    var heap = new_heap();
    const reference = Reference {
        kind: ReferenceKind.object,
        slot: 1,
        generation: 0,
    };

    assert(!heap.monitor_held_by_current_thread(reference));
    assert(heap.monitor_enter(reference));
    assert(heap.monitor_held_by_current_thread(reference));
    assert(heap.monitor_enter(reference));
    assert(heap.monitor_held_by_current_thread(reference));
    assert(heap.monitor_exit(reference));
    assert(heap.monitor_held_by_current_thread(reference));
    assert(heap.monitor_exit(reference));
    assert(!heap.monitor_held_by_current_thread(reference));
    assert(!heap.monitor_exit(reference));
    heap.clear();
}

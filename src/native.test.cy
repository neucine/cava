import { Constant } from .classfile;
import { Context } from .engine;
import { execute_method_frame_with_runtime } from .engine;
import { new_frame } from .engine;
import { VM } from .vm;
import { new_vm } from .vm;
import {
    Class,
    Field,
    InstructionError,
    Method,
    MethodAccessFlags,
    Reference,
    ReferenceKind,
    Value,
    byte_buffer,
    class_access_flags,
    field_access_flags,
    java_utf16_units_from_utf8,
    null_ref,
    raw_class_access,
    raw_field_access,
    raw_method_access
} from .types;
import { monotonic_ns, now_ns, ns_to_ms, sleep_ms } from std.time;
import std.thread;
import { Runtime } from .runtime;
import {
    ref_arg,
    value_ref_or_null,
    int_arg,
    long_arg,
    float_arg,
    double_arg,
    receiver_ref,
    return_value,
    identity_hash_code,
    set_system_static_ref,
    find_native_class_index,
    load_native_class_index,
    find_or_load_native_class_index,
    find_loaded_class_index,
    find_class_object_index_in,
    native_class_index_by_name,
    native_hierarchy_instance_var_count,
    native_field_runtime_slot,
    native_class_named,
    native_reference_assignable_to,
    set_instance_field,
    set_instance_field_in,
    get_instance_field,
    get_instance_field_in,
    NativeResolvedMethod,
    JavaThreadStartPayload,
    find_native_instance_method,
    java_thread_start_worker_with_vm,
    java_thread_start_worker,
    java_string,
    java_string_bytes,
    is_primitive_class_object,
    ensure_class_object,
    descriptor_class_object,
    new_java_reflect_field,
    descriptor_end,
    new_class_array_for_method_parameters,
    new_java_reflect_constructor,
    array_descriptor_for_component,
    class_name_from_java_name,
    java_string_buffer,
    concat_java_string,
    print_java_string,
    new_thread_group,
    new_java_lang_thread,
    arraycopy,
    clone_array,
    clone_object,
    JavaLangSystem,
    JavaLangObject,
    JavaLangClass,
    JavaLangClassLoader,
    JavaLangClassLoaderNativeLibrary,
    JavaLangReflectArray,
    JavaLangPackage,
    JavaLangString,
    java_lang_string_builder_append,
    java_lang_string_builder_init,
    java_lang_string_builder_to_string,
    java_io_print_stream_println,
    JavaLangFloat,
    JavaLangDouble,
    JavaLangThread,
    JavaLangThrowable,
    JavaLangRuntime,
    JavaLangShutdown,
    JavaLangRefFinalizer,
    JavaLangRefReference,
    SunReflectReflection,
    JdkInternalReflectReflection,
    JavaSecurityAccessController,
    SunMiscVM,
    SunMiscUnsafe,
    JavaIoFileDescriptor,
    JavaIoFileInputStream,
    JavaIoFileOutputStream,
    JavaIoUnixFileSystem,
    JavaUtilConcurrentAtomicAtomicLong,
    JavaUtilZipZipFile,
    method_is,
    execute_native_method,
    seed_test_vm
} from .native;

test "native Object.clone copies instance fields" {
    const native_code: [0]u8 = [];
    const field = Field {
        class_name: "Example",
        access_flags: field_access_flags(0x0001),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var classes: [1]Class = [
        Class {
            name: "Example",
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [field],
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
        },
    ];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var vm_classes = vm.method_area.classes[..];
    const original = vm.heap.allocate_object(0, &vm_classes[0]);
    assert(vm.heap.set_field(original, 0, .int_value(42)));
    var constant_pool: [:]Constant = [: 0][];
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };

    const result = try JavaLangObject.clone(&context, &vm, original);
    if result is value {
        switch value {
            case .ref_value(clone) {
                assert(!clone.equals(original));
                if vm.heap.get_field(clone, 0) is cloned_value {
                    switch cloned_value {
                        case .int_value(actual) {
                            assert(actual == 42);
                        } else {
                            assert(false);
                        }
                    }
                } else {
                    assert(false);
                }
                assert(vm.heap.set_field(original, 0, .int_value(7)));
                if vm.heap.get_field(clone, 0) is cloned_after_original_update {
                    switch cloned_after_original_update {
                        case .int_value(actual) {
                            assert(actual == 42);
                        } else {
                            assert(false);
                        }
                    }
                } else {
                    assert(false);
                }
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

test "native Class metadata reads represented class" {
    const native_code: [0]u8 = [];
    const example_class_object = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    const object_class_object = Reference {
        kind: ReferenceKind.object,
        slot: 1,
        generation: 1,
    };
    var classes: [3]Class = [
        Class {
            name: "Example",
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Example.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: example_class_object,
        },
        Class {
            name: "java/lang/Object",
            descriptor: "Ljava/lang/Object;",
            access_flags: class_access_flags(0x0021),
            super_class: "",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Object.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: object_class_object,
        },
        Class {
            name: "java/lang/Class",
            descriptor: "Ljava/lang/Class;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Class.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var constant_pool: [:]Constant = [: 0][];
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };

    const modifiers = try JavaLangClass.getModifiers(&context, &vm, classes[0].class_object);
    if modifiers is modifiers_value {
        switch modifiers_value {
            case .int_value(actual) {
                assert(actual == 0x0021);
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }

    const super_class = try JavaLangClass.getSuperclass(&context, &vm, classes[0].class_object);
    if super_class is super_value {
        switch super_value {
            case .ref_value(actual) {
                assert(actual.equals(classes[1].class_object));
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }

    const object_super_class = try JavaLangClass.getSuperclass(&context, &vm, classes[1].class_object);
    if object_super_class is object_super_value {
        switch object_super_value {
            case .ref_value(actual) {
                assert(actual.is_null());
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

test "native bootstrap helpers return conservative values" {
    const native_code: [0]u8 = [];
    const class_object = Reference {
        kind: ReferenceKind.object,
        slot: 7,
        generation: 1,
    };
    var classes: [1]Class = [
        Class {
            name: "Example",
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0421),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Example.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: class_object,
        },
    ];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var constant_pool: [:]Constant = [: 0][];
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };

    const runtime = Reference {
        kind: ReferenceKind.object,
        slot: 8,
        generation: 1,
    };
    const free_memory = try JavaLangRuntime.freeMemory(&context, runtime);
    if free_memory is free_value {
        switch free_value {
            case .long_value(actual) {
                assert(actual > 0);
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }

    const access_flags_value = try SunReflectReflection.getClassAccessFlags(&context, &vm, class_object);
    if access_flags_value is flags_value {
        switch flags_value {
            case .int_value(actual) {
                assert(actual == 0x0421);
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }

    const path = Reference {
        kind: ReferenceKind.object,
        slot: 9,
        generation: 1,
    };
    const canonicalized = try JavaIoUnixFileSystem.canonicalize0(&context, runtime, path);
    if canonicalized is canonicalized_value {
        switch canonicalized_value {
            case .ref_value(actual) {
                assert(actual.equals(path));
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }

    const pending = try JavaLangRefReference.hasReferencePendingList(&context);
    if pending is pending_value {
        switch pending_value {
            case .boolean_value(actual) {
                assert(actual == 0);
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

test "native Thread.currentThread creates stable java thread object" {
    const native_code: [0]u8 = [];
    const thread_name_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "name",
        descriptor: "Ljava/lang/String;",
        index: 0,
        slot: 0,
    };
    const thread_tid_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "tid",
        descriptor: "J",
        index: 1,
        slot: 1,
    };
    const thread_group_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "group",
        descriptor: "Ljava/lang/ThreadGroup;",
        index: 2,
        slot: 2,
    };
    const thread_priority_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "priority",
        descriptor: "I",
        index: 3,
        slot: 3,
    };
    const group_name_field = Field {
        class_name: "java/lang/ThreadGroup",
        access_flags: field_access_flags(0x0001),
        name: "name",
        descriptor: "Ljava/lang/String;",
        index: 0,
        slot: 0,
    };
    var classes: [3]Class = [
        Class {
            name: "java/lang/Thread",
            descriptor: "Ljava/lang/Thread;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [thread_name_field, thread_tid_field, thread_group_field, thread_priority_field],
            methods: [],
            constant_pool: [],
            instance_vars: 4,
            static_vars: [],
            source_file: "Thread.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: "java/lang/ThreadGroup",
            descriptor: "Ljava/lang/ThreadGroup;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [group_name_field],
            methods: [],
            constant_pool: [],
            instance_vars: 1,
            static_vars: [],
            source_file: "ThreadGroup.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: "java/lang/String",
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
        },
    ];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var constant_pool: [:]Constant = [: 0][];
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };

    const first = try JavaLangThread.currentThread(&context, &vm);
    const second = try JavaLangThread.currentThread(&context, &vm);
    if first is first_value {
        switch first_value {
            case .ref_value(first_ref) {
                if second is second_value {
                    switch second_value {
                        case .ref_value(second_ref) {
                            assert(first_ref.equals(second_ref));
                        } else {
                            assert(false);
                        }
                    }
                } else {
                    assert(false);
                }
                if vm.heap.get_field(first_ref, 1) is tid {
                    switch tid {
                        case .long_value(actual) {
                            assert(actual == 1);
                        } else {
                            assert(false);
                        }
                    }
                } else {
                    assert(false);
                }
                if vm.heap.get_field(first_ref, 3) is priority {
                    switch priority {
                        case .int_value(actual) {
                            assert(actual == 1);
                        } else {
                            assert(false);
                        }
                    }
                } else {
                    assert(false);
                }
                if vm.heap.get_field(first_ref, 0) is name {
                    switch name {
                        case .ref_value(name_ref) {
                            assert(name_ref.equals(vm.heap.strings[0].reference));
                        } else {
                            assert(false);
                        }
                    }
                } else {
                    assert(false);
                }
                if vm.heap.get_field(first_ref, 2) is group {
                    switch group {
                        case .ref_value(group_ref) {
                            assert(group_ref.non_null());
                            if vm.heap.get_field(group_ref, 0) is group_name {
                                switch group_name {
                                    case .ref_value(group_name_ref) {
                                        assert(group_name_ref.equals(vm.heap.strings[0].reference));
                                    } else {
                                        assert(false);
                                    }
                                }
                            } else {
                                assert(false);
                            }
                        } else {
                            assert(false);
                        }
                    }
                } else {
                    assert(false);
                }
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

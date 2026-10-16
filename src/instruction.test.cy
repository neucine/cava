import { Constant, ConstantMemberRef, ConstantMethodHandle, ConstantNameAndType, ConstantWide } from .classfile;
import {
    Context,
    Frame,
    FrameResult,
    apply_method_result,
    dispatch_exception,
    execute_method_frame_with_runtime,
    execute_method_frame_with_vm,
    new_frame
} from .engine;
import {
    MethodArea,
    ResolvedMethod,
    class_matches,
    find_loaded_class_index,
    new_method_area,
    reference_assignable_to,
    runtime_field_slot
} from .method_area;
import { VM } from .vm;
import { Runtime, new_runtime } from .runtime;
import { execute_array_next } from .instruction;
import { new_vm } from .vm;
import { execute_native_method } from .native;
import {
    Class,
    Field,
    InstructionError,
    Method,
    Reference,
    ReferenceKind,
    Value,
    array_component_descriptor,
    byte_buffer,
    class_access_flags,
    field_access_flags,
    method_access_flags,
    method_argument_count,
    null_ref,
    reference_array_component_descriptor,
    reference_array_descriptor
} from .types;
import { env_get } from std.process;
import {
    Opcode,
    Instruction,
    ExecuteFn,
    constant_utf8,
    constant_class_name,
    constant_utf8_equals,
    find_class_index_by_constant,
    find_class_index,
    field_runtime_slot,
    find_field_index_by_constants,
    find_field_in_hierarchy,
    find_field_by_name_in_hierarchy,
    find_field_index,
    find_static_method_index_by_constants,
    find_instance_method_index_by_constants,
    find_static_method_index_in_hierarchy,
    find_instance_method_index_in_hierarchy,
    find_interface_method_index_in_hierarchy,
    find_instance_method_by_name_in_hierarchy,
    resolve_field,
    resolve_static_method,
    resolve_instance_method,
    resolve_interface_method,
    push_int,
    expect_int,
    expect_ref,
    expect_long,
    expect_float,
    expect_double,
    expect_return_address,
    expect_array_load,
    store_array_value,
    load_int,
    load_long,
    load_float,
    load_double,
    store_int,
    store_long,
    store_float,
    store_double,
    load_ref,
    store_ref_like,
    is_category2,
    sign_extend_u1,
    wide_bits,
    load_constant,
    load_class_constant,
    load_string_constant,
    load_method_type_constant,
    load_method_handle_constant,
    unsupported,
    nop,
    aconst_null,
    iconst_m1,
    iconst_0,
    iconst_1,
    iconst_2,
    iconst_3,
    iconst_4,
    iconst_5,
    lconst_0,
    lconst_1,
    fconst_0,
    fconst_1,
    fconst_2,
    dconst_0,
    dconst_1,
    ldc,
    ldc_w,
    ldc2_w,
    bipush,
    sipush,
    iload,
    lload,
    fload,
    dload,
    aload,
    iload_0,
    iload_1,
    iload_2,
    iload_3,
    lload_0,
    lload_1,
    lload_2,
    lload_3,
    fload_0,
    fload_1,
    fload_2,
    fload_3,
    dload_0,
    dload_1,
    dload_2,
    dload_3,
    aload_0,
    aload_1,
    aload_2,
    aload_3,
    istore,
    lstore,
    fstore,
    dstore,
    astore,
    istore_0,
    istore_1,
    istore_2,
    istore_3,
    lstore_0,
    lstore_1,
    lstore_2,
    lstore_3,
    fstore_0,
    fstore_1,
    fstore_2,
    fstore_3,
    dstore_0,
    dstore_1,
    dstore_2,
    dstore_3,
    astore_0,
    astore_1,
    astore_2,
    astore_3,
    iaload,
    laload,
    faload,
    daload,
    aaload,
    baload,
    caload,
    saload,
    pop,
    pop2,
    dup,
    dup_x1,
    dup_x2,
    dup2,
    dup2_x1,
    dup2_x2,
    swap,
    iastore,
    lastore,
    fastore,
    dastore,
    aastore,
    bastore,
    castore,
    sastore,
    iadd,
    ladd,
    fadd,
    dadd,
    isub,
    lsub,
    fsub,
    dsub,
    imul,
    lmul,
    fmul,
    dmul,
    fdiv,
    ddiv,
    idiv,
    ldiv,
    irem,
    lrem,
    ineg,
    lneg,
    fneg,
    dneg,
    ishl,
    lshl,
    ishr,
    lshr,
    iushr,
    lushr,
    iand,
    land,
    ior,
    lor,
    ixor,
    lxor,
    iinc,
    i2l,
    i2f,
    i2d,
    l2i,
    l2f,
    l2d,
    f2d,
    jvm_f2i_value,
    jvm_f2l_value,
    jvm_d2i_value,
    jvm_d2l_value,
    f2i,
    f2l,
    d2i,
    d2l,
    d2f,
    i2b,
    i2c,
    i2s,
    lcmp,
    fcmpl,
    fcmpg,
    dcmpl,
    dcmpg,
    branch,
    ifeq,
    ifne,
    iflt,
    ifge,
    ifgt,
    ifle,
    if_icmpeq,
    if_icmpne,
    if_icmplt,
    if_icmpge,
    if_icmpgt,
    if_icmple,
    if_acmpeq,
    if_acmpne,
    goto_,
    goto_w,
    jsr,
    ret,
    tableswitch,
    lookupswitch,
    jsr_w,
    ireturn,
    lreturn,
    freturn,
    dreturn,
    areturn,
    return_,
    value_local_width,
    instruction_length_for_scan,
    read_scan_i4,
    native_arguments,
    is_access_controller_do_privileged,
    execute_child_method_frame,
    invoke_privileged_action,
    invoke_instance_method_direct,
    find_class_object_index_instruction,
    get_instance_field_by_name,
    java_string_bytes_instruction,
    invoke_reflect_constructor,
    set_java_system_property,
    initialize_java_system_properties,
    invoke_static,
    invoke_special,
    invoke_virtual,
    invoke_interface,
    new_,
    getstatic,
    initialize_static_class,
    initialize_system_static_fields,
    initialize_vm_static_fields,
    putstatic,
    getfield,
    putfield,
    athrow,
    newarray,
    anewarray,
    checkcast,
    instanceof,
    monitorenter,
    monitorexit,
    allocate_multi_array,
    multianewarray,
    arraylength,
    wide,
    ifnull,
    ifnonnull,
    registry,
    fetch,
    execute_next,
    print_instruction_gap,
    instruction_error_name,
    print_instruction_error_context,
    instruction_trace_enabled,
    opcode_name,
    trace_instruction,
    execute_method,
    assert_int_result,
    assert_long_result,
    assert_float_result,
    assert_double_result,
    assert_null_ref_result,
    assert_void_result,
    assert_exception_result,
    seed_test_vm
} from .instruction;

fn check_parallel_narrow_array(runtime: Runtime, descriptor: string, store_opcode: u8, load_opcode: u8, input: i32, expected: i32): void {
    var reference = null_ref;
    switch runtime.state.with_result<string, Reference>(descriptor, fn (vm: &VM, actual: string): Reference {
        return vm.heap.allocate_array(0, actual.bytes(), 1);
    }) {
        case .ok(actual) {
            reference = actual;
        }
        case .err {
            assert(false);
        }
    }
    const code: [2]u8 = [store_opcode, load_opcode];
    const pool: List<Constant> = [];
    var context = Context {
        runtime: copy runtime,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 3),
        code: code[..],
        constant_pool: pool[..],
    };
    context.frame.push(.ref_value(reference));
    push_int(&context, 0);
    push_int(&context, input);
    switch execute_array_next(&context, "Array", "store") {
        case .ok(handled) {
            assert(handled);
        }
        case .err {
            assert(false);
        }
    }
    context.frame.push(.ref_value(reference));
    push_int(&context, 0);
    switch execute_array_next(&context, "Array", "load") {
        case .ok(handled) {
            assert(handled);
        }
        case .err {
            assert(false);
        }
    }
    assert(expect_int(context.frame.pop()) == expected);
}

test "parallel array bytecodes preserve narrow primitive conversions" {
    const runtime = new_runtime();
    check_parallel_narrow_array(copy runtime, "Z", 84, 51, 3, 1);
    check_parallel_narrow_array(copy runtime, "B", 84, 51, 255, 0 - 1);
    check_parallel_narrow_array(copy runtime, "C", 85, 52, 65537, 1);
    check_parallel_narrow_array(copy runtime, "S", 86, 53, 65535, 0 - 1);
    runtime.finish();
}

test "instruction executes iconst and ireturn" {
    const code: [2]u8 = [4, 172];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "answer",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 2,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 1);
    drop method;
}

test "instruction executes bipush sipush and ireturn" {
    const byte_code: [3]u8 = [16, 254, 172];
    const short_code: [4]u8 = [17, 1, 2, 172];
    var byte_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "byteValue",
        descriptor: "()I",
        code: byte_buffer(byte_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };
    var short_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "shortValue",
        descriptor: "()I",
        code: byte_buffer(short_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const byte_result = try execute_method(&byte_method);
    const short_result = try execute_method(&short_method);
    assert_int_result(byte_result, 0 - 2);
    assert_int_result(short_result, 258);
    drop byte_method;
    drop short_method;
}

test "instruction executes ldc numeric constants" {
    const code: [13]u8 = [
        18, 1, // ldc #1 integer
        19, 0, 2, // ldc_w #2 integer
        20, 0, 3, // ldc2_w #3 long
        18, 5, // ldc #5 float
        20, 0, 6, // ldc2_w #6 double
    ];
    const constant_pool: [8]Constant = [
        .unusable(0),
        .integer(42),
        .integer(67),
        .long(ConstantWide {
            high_bytes: 0,
            low_bytes: 42
        }),
        .unusable(0),
        .float(0x40000000),
        .double(ConstantWide {
            high_bytes: 0x40080000,
            low_bytes: 0
        }),
        .unusable(0),
    ];
    var vm = new_vm();
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 5),
        code: code[..],
        constant_pool: constant_pool[..]
    };

    var step: usize = 0;
    while step < 5 {
        const step_result = execute_next(&context, &vm);
        switch step_result {
            case .ok {}
            case .err {
                assert(false);
            }
        }
        step = step + 1;
    }

    assert_double_result(.return_value(context.frame.pop()), 3.0);
    assert_float_result(.return_value(context.frame.pop()), 2.0);
    assert_long_result(.return_value(context.frame.pop()), 42);
    assert_int_result(.return_value(context.frame.pop()), 67);
    assert_int_result(.return_value(context.frame.pop()), 42);
    drop context;
}

test "instruction caches ldc class constants" {
    const code: [4]u8 = [
        18, 2, // ldc #2 Example.class
        18, 2, // ldc #2 Example.class
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
    ];
    var example_class = Class {
        name: string.from("Example".bytes()),
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
        class_object: null_ref,
    };
    var class_class = Class {
        name: string.from("java/lang/Class".bytes()),
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
    };
    var classes: [2]Class = [example_class, class_class];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..]
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context, &vm);
        switch step_result {
            case .ok {}
            case .err {
                assert(false);
            }
        }
        step = step + 1;
    }

    var context_classes = vm.method_area.classes[..];
    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(context_classes[0].class_object.equals(first));
    assert(vm.heap.object_count() == 1);
    if vm.heap.object_class_index(first) is class_index {
        assert(class_index == 1);
    } else {
        assert(false);
    }
    drop context;
}

test "instruction interns ldc string constants" {
    const code: [4]u8 = [
        18, 2, // ldc #2 "hello"
        18, 2, // ldc #2 "hello"
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("hello"),
        .string_ref(1),
    ];
    var main_class = Class {
        name: string.from("Main".bytes()),
        descriptor: "LMain;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Main.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
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
    var classes: [2]Class = [main_class, string_class];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..]
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context, &vm);
        switch step_result {
            case .ok {}
            case .err {
                assert(false);
            }
        }
        step = step + 1;
    }

    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(vm.heap.object_count() == 1);
    if vm.heap.object_class_index(first) is class_index {
        assert(class_index == 1);
    } else {
        assert(false);
    }
    assert(vm.heap.strings.len() == 1);
    assert(vm.heap.strings[0].value[..] == "hello".bytes());
    assert(vm.heap.strings[0].reference.equals(first));
    drop context;
}

test "instruction interns ldc method type constants" {
    const code: [4]u8 = [
        18, 2, // ldc #2 (I)V
        18, 2, // ldc #2 (I)V
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("(I)V"),
        .method_type(1),
    ];
    var main_class = Class {
        name: string.from("Main".bytes()),
        descriptor: "LMain;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Main.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
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
    var classes: [2]Class = [main_class, method_type_class];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..]
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context, &vm);
        switch step_result {
            case .ok {}
            case .err {
                assert(false);
            }
        }
        step = step + 1;
    }

    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(vm.heap.object_count() == 1);
    if vm.heap.object_class_index(first) is class_index {
        assert(class_index == 1);
    } else {
        assert(false);
    }
    assert(vm.heap.method_types.len() == 1);
    assert(vm.heap.method_types[0].descriptor == "(I)V");
    assert(vm.heap.method_types[0].reference.equals(first));
    drop context;
}

test "instruction interns ldc method handle constants" {
    const code: [4]u8 = [
        18, 7, // ldc #7 REF_invokeStatic Main.run:()I
        18, 7, // ldc #7 REF_invokeStatic Main.run:()I
    ];
    const constant_pool: [8]Constant = [
        .unusable(0),
        .utf8("Main"),
        .class_ref(1),
        .utf8("run"),
        .utf8("()I"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
        .method_handle(ConstantMethodHandle {
            reference_kind: 6,
            reference_index: 6
        }),
    ];
    var main_class = Class {
        name: string.from("Main".bytes()),
        descriptor: "LMain;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Main.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
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
    var classes: [2]Class = [main_class, method_handle_class];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..]
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context, &vm);
        switch step_result {
            case .ok {}
            case .err {
                assert(false);
            }
        }
        step = step + 1;
    }

    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(vm.heap.object_count() == 1);
    if vm.heap.object_class_index(first) is class_index {
        assert(class_index == 1);
    } else {
        assert(false);
    }
    assert(vm.heap.method_handles.len() == 1);
    assert(vm.heap.method_handles[0].reference_kind == 6);
    assert(vm.heap.method_handles[0].reference_index == 6);
    assert(vm.heap.method_handles[0].reference.equals(first));
    drop context;
}

test "instruction executes field access ops" {
    const code: [12]u8 = [
        179, 0, 6, // putstatic Example.staticValue:I
        178, 0, 6, // getstatic Example.staticValue:I
        181, 0, 9, // putfield Example.instanceValue:I
        180, 0, 9, // getfield Example.instanceValue:I
    ];
    const constant_pool: [10]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
        .utf8("staticValue"),
        .utf8("I"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .field_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
        .utf8("instanceValue"),
        .name_and_type(ConstantNameAndType {
            name_index: 7,
            descriptor_index: 4
        }),
        .field_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 8
        }),
    ];
    const static_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(8),
        name: "staticValue",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(1),
        name: "instanceValue",
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
    var classes: [1]Class = [class];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 4),
        code: code[..],
        constant_pool: constant_pool[..]
    };
    var context_classes = vm.method_area.classes[..];
    const reference = vm.heap.allocate_object(0, &context_classes[0]);

    context.frame.push(.int_value(41));
    const put_static = execute_next(&context, &vm);
    switch put_static {
        case .ok {}
        case .err {
            assert(false);
        }
    }

    const get_static = execute_next(&context, &vm);
    switch get_static {
        case .ok {}
        case .err {
            assert(false);
        }
    }

    context.frame.push(.ref_value(reference));
    context.frame.push(.int_value(1));
    const put_instance = execute_next(&context, &vm);
    switch put_instance {
        case .ok {}
        case .err {
            assert(false);
        }
    }

    context.frame.push(.ref_value(reference));
    const get_instance = execute_next(&context, &vm);
    switch get_instance {
        case .ok {}
        case .err {
            assert(false);
        }
    }

    assert_int_result(.return_value(context.frame.pop()), 1);
    assert_int_result(.return_value(context.frame.pop()), 41);
    drop context;
}

test "instruction executes invokestatic int method" {
    const constant_pool: [7]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
        .utf8("add"),
        .utf8("(II)I"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
    ];
    const caller_code: [6]u8 = [
        5, // iconst_2
        6, // iconst_3
        184, 0, 6, // invokestatic Example.add:(II)I
        172, // ireturn
    ];
    const add_code: [4]u8 = [
        26, // iload_0
        27, // iload_1
        96, // iadd
        172, // ireturn
    ];
    var classes: [1]Class = [
        Class {
            name: string.from("Example".bytes()),
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 2,
                    max_locals: 0,
                    code_len: 6,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(8),
                    name: "add",
                    descriptor: "(II)I",
                    code: byte_buffer(add_code[..]),
                    max_stack: 2,
                    max_locals: 2,
                    code_len: 4,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 2,
                    return_descriptor: "I",
                },
            ],
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
            class_object: null_ref,
        },
    ];

    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, 0, 2), constant_pool[..]);
    assert_int_result(result, 5);
    drop classes;
}

test "instruction executes registerNatives native no-op" {
    const constant_pool: [7]Constant = [
        .unusable(0),
        .utf8("java/lang/System"),
        .class_ref(1),
        .utf8("registerNatives"),
        .utf8("()V"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
    ];
    const caller_code: [5]u8 = [
        184, 0, 6, // invokestatic java/lang/System.registerNatives:()V
        8, // iconst_5
        172, // ireturn
    ];
    const native_code: [0]u8 = [];
    var classes: [1]Class = [
        Class {
            name: string.from("java/lang/System".bytes()),
            descriptor: "Ljava/lang/System;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "java/lang/System",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 5,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "java/lang/System",
                    access_flags: method_access_flags(0x0108),
                    name: "registerNatives",
                    descriptor: "()V",
                    code: byte_buffer(native_code[..]),
                    max_stack: 0,
                    max_locals: 0,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "V",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "System.java",
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
    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, 0, 1), constant_pool[..]);
    assert_int_result(result, 5);
    drop classes;
}

test "instruction executes System.initProperties native" {
    const constant_pool: [7]Constant = [
        .unusable(0),
        .utf8("java/lang/System"),
        .class_ref(1),
        .utf8("initProperties"),
        .utf8("(Ljava/util/Properties;)Ljava/util/Properties;"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
    ];
    const caller_code: [5]u8 = [
        1, // aconst_null
        184, 0, 6, // invokestatic java/lang/System.initProperties:(Ljava/util/Properties;)Ljava/util/Properties;
        176, // areturn
    ];
    const native_code: [0]u8 = [];
    var classes: [1]Class = [
        Class {
            name: string.from("java/lang/System".bytes()),
            descriptor: "Ljava/lang/System;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "java/lang/System",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()Ljava/util/Properties;",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 5,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "Ljava/util/Properties;",
                },
                Method {
                    class_name: "java/lang/System",
                    access_flags: method_access_flags(0x0108),
                    name: "initProperties",
                    descriptor: "(Ljava/util/Properties;)Ljava/util/Properties;",
                    code: byte_buffer(native_code[..]),
                    max_stack: 0,
                    max_locals: 0,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "Ljava/util/Properties;",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "System.java",
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
    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, 0, 1), constant_pool[..]);
    assert_null_ref_result(result);
    drop classes;
}

test "instruction executes native AccessController.doPrivileged callback" {
    const constant_pool: [15]Constant = [
        .unusable(0),
        .utf8("Action"),
        .class_ref(1),
        .utf8("<init>"),
        .utf8("()V"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
        .utf8("java/security/AccessController"),
        .class_ref(7),
        .utf8("doPrivileged"),
        .utf8("(Ljava/security/PrivilegedAction;Ljava/security/AccessControlContext;)Ljava/lang/Object;"),
        .name_and_type(ConstantNameAndType {
            name_index: 9,
            descriptor_index: 10
        }),
        .method_ref(ConstantMemberRef {
            class_index: 8,
            name_and_type_index: 11
        }),
        .utf8("run"),
        .utf8("()Ljava/lang/Object;"),
    ];
    const caller_code: [12]u8 = [
        187, 0, 2, // new Action
        89, // dup
        183, 0, 6, // invokespecial Action.<init>:()V
        1, // aconst_null
        184, 0, 12, // invokestatic AccessController.doPrivileged:(PrivilegedAction,AccessControlContext)Object
        176, // areturn
    ];
    const init_code: [1]u8 = [
        177, // return
    ];
    const run_code: [2]u8 = [
        42, // aload_0
        176, // areturn
    ];
    const native_code: [0]u8 = [];
    var classes: [2]Class = [
        Class {
            name: "java/security/AccessController",
            descriptor: "Ljava/security/AccessController;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "java/security/AccessController",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()Ljava/lang/Object;",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 3,
                    max_locals: 0,
                    code_len: 12,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "Ljava/lang/Object;",
                },
                Method {
                    class_name: "java/security/AccessController",
                    access_flags: method_access_flags(0x0108),
                    name: "doPrivileged",
                    descriptor: "(Ljava/security/PrivilegedAction;Ljava/security/AccessControlContext;)Ljava/lang/Object;",
                    code: byte_buffer(native_code[..]),
                    max_stack: 0,
                    max_locals: 0,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 2,
                    return_descriptor: "Ljava/lang/Object;",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "AccessController.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: "Action",
            descriptor: "LAction;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: ["java/security/PrivilegedAction"],
            fields: [],
            methods: [
                Method {
                    class_name: "Action",
                    access_flags: method_access_flags(0),
                    name: "<init>",
                    descriptor: "()V",
                    code: byte_buffer(init_code[..]),
                    max_stack: 0,
                    max_locals: 1,
                    code_len: 1,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "V",
                },
                Method {
                    class_name: "Action",
                    access_flags: method_access_flags(0x0001),
                    name: "run",
                    descriptor: "()Ljava/lang/Object;",
                    code: byte_buffer(run_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "Ljava/lang/Object;",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Action.java",
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
    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, 0, 3), constant_pool[..]);
    switch result {
        case .return_value(value) {
            if value is actual {
                switch actual {
                    case .ref_value(reference) {
                        assert(reference.non_null());
                        if vm.heap.object_class_index(reference) is class_index {
                            assert(class_index == 1);
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
        }
        case .exception {
            assert(false);
        }
    }
    drop classes;
}

test "instruction executes System.arraycopy native" {
    const native_code: [0]u8 = [];
    var classes: [1]Class = [
        Class {
            name: string.from("java/lang/System".bytes()),
            descriptor: "Ljava/lang/System;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "java/lang/System",
                    access_flags: method_access_flags(0x0108),
                    name: "arraycopy",
                    descriptor: "(Ljava/lang/Object;ILjava/lang/Object;II)V",
                    code: byte_buffer(native_code[..]),
                    max_stack: 0,
                    max_locals: 0,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 5,
                    return_descriptor: "V",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "System.java",
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
    const src = vm.heap.allocate_array(0, "I".bytes(), 3);
    const dest = vm.heap.allocate_array(0, "I".bytes(), 3);
    assert(vm.heap.set_element(src, 0, .int_value(7)));
    assert(vm.heap.set_element(src, 1, .int_value(8)));
    assert(vm.heap.set_element(src, 2, .int_value(9)));
    var constant_pool: [:]Constant = [: 0][];
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };
    var arguments: List<Value> = [];
    arguments.push(.ref_value(src));
    arguments.push(.int_value(1));
    arguments.push(.ref_value(dest));
    arguments.push(.int_value(0));
    arguments.push(.int_value(2));

    const result = try execute_native_method(&context, &vm, 0, 0, none, arguments);
    assert(result == none);
    if vm.heap.get_element(dest, 0) is first {
        assert_int_result(.return_value(first), 8);
    } else {
        assert(false);
    }
    if vm.heap.get_element(dest, 1) is second {
        assert_int_result(.return_value(second), 9);
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

test "instruction executes float and double raw bit natives" {
    const native_code: [0]u8 = [];
    var classes: [2]Class = [
        Class {
            name: string.from("java/lang/Float".bytes()),
            descriptor: "Ljava/lang/Float;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "java/lang/Float",
                    access_flags: method_access_flags(0x0108),
                    name: "floatToRawIntBits",
                    descriptor: "(F)I",
                    code: byte_buffer(native_code[..]),
                    max_stack: 0,
                    max_locals: 0,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "java/lang/Float",
                    access_flags: method_access_flags(0x0108),
                    name: "intBitsToFloat",
                    descriptor: "(I)F",
                    code: byte_buffer(native_code[..]),
                    max_stack: 0,
                    max_locals: 0,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "F",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Float.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("java/lang/Double".bytes()),
            descriptor: "Ljava/lang/Double;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "java/lang/Double",
                    access_flags: method_access_flags(0x0108),
                    name: "longBitsToDouble",
                    descriptor: "(J)D",
                    code: byte_buffer(native_code[..]),
                    max_stack: 0,
                    max_locals: 0,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "D",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Double.java",
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
    var float_args: List<Value> = [];
    float_args.push(.float_value(1.0));
    const float_bits = try execute_native_method(&context, &vm, 0, 0, none, float_args);
    assert_int_result(.return_value(float_bits), 1065353216);

    var int_args: List<Value> = [];
    int_args.push(.int_value(1073741824));
    const float_value = try execute_native_method(&context, &vm, 0, 1, none, int_args);
    assert_float_result(.return_value(float_value), 2.0);

    var long_args: List<Value> = [];
    long_args.push(.long_value(4611686018427387904));
    const double_value = try execute_native_method(&context, &vm, 1, 0, none, long_args);
    assert_double_result(.return_value(double_value), 2.0);
    drop context;
    drop classes;
    drop constant_pool;
}

test "instruction executes new object allocation" {
    const code: [3]u8 = [
        187, 0, 2, // new Example
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
    ];
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(1),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var classes: [1]Class = [
        Class {
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
        },
    ];
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 1),
        code: code[..],
        constant_pool: constant_pool[..]
    };

    const execute_result = execute_next(&context, &vm);
    switch execute_result {
        case .ok {}
        case .err {
            assert(false);
        }
    }
    const reference = expect_ref(context.frame.pop());
    assert(vm.heap.has_object(reference));
    if vm.heap.get_field(reference, 0) is value {
        assert_int_result(.return_value(value), 0);
    } else {
        assert(false);
    }
    drop context;
}

test "instruction executes invokespecial constructor initialization" {
    const constant_pool: [11]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
        .utf8("value"),
        .utf8("I"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .field_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
        .utf8("<init>"),
        .utf8("(I)V"),
        .name_and_type(ConstantNameAndType {
            name_index: 7,
            descriptor_index: 8
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 9
        }),
    ];
    const caller_code: [9]u8 = [
        187, 0, 2, // new Example
        89, // dup
        8, // iconst_5
        183, 0, 10, // invokespecial Example.<init>:(I)V
        176, // areturn
    ];
    const init_code: [6]u8 = [
        42, // aload_0
        27, // iload_1
        181, 0, 6, // putfield Example.value:I
        177, // return
    ];
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(1),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var classes: [1]Class = [
        Class {
            name: string.from("Example".bytes()),
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [instance_field],
            methods: [
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()LExample;",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 3,
                    max_locals: 0,
                    code_len: 9,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "LExample;",
                },
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(0),
                    name: "<init>",
                    descriptor: "(I)V",
                    code: byte_buffer(init_code[..]),
                    max_stack: 2,
                    max_locals: 2,
                    code_len: 6,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "V",
                },
            ],
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
    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, 0, 3), constant_pool[..]);
    switch result {
        case .return_value(value) {
            if value is actual {
                const reference = expect_ref(actual);
                if vm.heap.get_field(reference, 0) is field_value {
                    assert_int_result(.return_value(field_value), 5);
                } else {
                    assert(false);
                }
            } else {
                assert(false);
            }
        }
        case .exception {
            assert(false);
        }
    }
    drop classes;
}

test "instruction executes invokevirtual override dispatch" {
    const constant_pool: [9]Constant = [
        .unusable(0),
        .utf8("Base"),
        .class_ref(1),
        .utf8("Child"),
        .class_ref(3),
        .utf8("value"),
        .utf8("()I"),
        .name_and_type(ConstantNameAndType {
            name_index: 5,
            descriptor_index: 6
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 7
        }),
    ];
    const caller_code: [7]u8 = [
        187, 0, 4, // new Child
        182, 0, 8, // invokevirtual Base.value:()I
        172, // ireturn
    ];
    const base_value_code: [2]u8 = [
        4, // iconst_1
        172, // ireturn
    ];
    const child_value_code: [2]u8 = [
        5, // iconst_2
        172, // ireturn
    ];
    var classes: [2]Class = [
        Class {
            name: string.from("Base".bytes()),
            descriptor: "LBase;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Base",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 7,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Base",
                    access_flags: method_access_flags(0),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(base_value_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Base.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Child".bytes()),
            descriptor: "LChild;",
            access_flags: class_access_flags(0x0021),
            super_class: "Base",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Child",
                    access_flags: method_access_flags(0),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(child_value_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Child.java",
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
    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, 0, 1), constant_pool[..]);
    assert_int_result(result, 2);
    drop classes;
}

test "instruction executes invokeinterface implementation dispatch" {
    const constant_pool: [9]Constant = [
        .unusable(0),
        .utf8("Iface"),
        .class_ref(1),
        .utf8("Impl"),
        .class_ref(3),
        .utf8("value"),
        .utf8("()I"),
        .name_and_type(ConstantNameAndType {
            name_index: 5,
            descriptor_index: 6
        }),
        .interface_method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 7
        }),
    ];
    const caller_code: [9]u8 = [
        187, 0, 4, // new Impl
        185, 0, 8, 1, 0, // invokeinterface Iface.value:()I
        172, // ireturn
    ];
    const impl_value_code: [2]u8 = [
        6, // iconst_3
        172, // ireturn
    ];
    const interface_code: [0]u8 = [];
    var classes: [2]Class = [
        Class {
            name: string.from("Iface".bytes()),
            descriptor: "LIface;",
            access_flags: class_access_flags(0x0601),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Iface",
                    access_flags: method_access_flags(0x0401),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(interface_code[..]),
                    max_stack: 0,
                    max_locals: 1,
                    code_len: 0,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Iface.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Impl".bytes()),
            descriptor: "LImpl;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: ["Iface"],
            fields: [],
            methods: [
                Method {
                    class_name: "Impl",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 9,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Impl",
                    access_flags: method_access_flags(0),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(impl_value_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Impl.java",
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
    const result = try execute_method_frame_with_vm(&vm, 1, 0, new_frame(1, 0, 0, 1), constant_pool[..]);
    assert_int_result(result, 3);
    drop classes;
}

test "instruction executes int local shorthand load store and add" {
    const code: [9]u8 = [
        5, // iconst_2
        59, // istore_0
        16, 40, // bipush 40
        60, // istore_1
        26, // iload_0
        27, // iload_1
        96, // iadd
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "sumShortForms",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 2,
        code_len: 9,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes int local operand load store and add" {
    const code: [13]u8 = [
        16, 41, // bipush 41
        54, 2, // istore 2
        4, // iconst_1
        54, 3, // istore 3
        21, 2, // iload 2
        21, 3, // iload 3
        96, // iadd
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "sumOperandForms",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 4,
        code_len: 13,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes int subtract multiply and negate" {
    const code: [10]u8 = [
        16, 50, // bipush 50
        16, 8, // bipush 8
        100, // isub
        4, // iconst_1
        104, // imul
        116, // ineg
        116, // ineg
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intArithmetic",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes float load store arithmetic and return" {
    const code: [14]u8 = [
        13, // fconst_2
        67, // fstore_0
        34, // fload_0
        12, // fconst_1
        98, // fadd
        13, // fconst_2
        106, // fmul
        12, // fconst_1
        102, // fsub
        12, // fconst_1
        110, // fdiv
        118, // fneg
        118, // fneg
        174, // freturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "floatArithmetic",
        descriptor: "()F",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const result = try execute_method(&method);
    assert_float_result(result, 5.0);
    drop method;
}

test "instruction executes double load store arithmetic and return" {
    const code: [18]u8 = [
        15, // dconst_1
        57, 2, // dstore 2
        24, 2, // dload 2
        15, // dconst_1
        99, // dadd
        15, // dconst_1
        99, // dadd
        15, // dconst_1
        103, // dsub
        15, // dconst_1
        107, // dmul
        15, // dconst_1
        111, // ddiv
        119, // dneg
        119, // dneg
        175, // dreturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "doubleArithmetic",
        descriptor: "()D",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 4,
        code_len: 18,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const result = try execute_method(&method);
    assert_double_result(result, 2.0);
    drop method;
}

test "instruction executes integer division and remainder normal paths" {
    const code: [13]u8 = [
        16, 43, // bipush 43
        5, // iconst_2
        108, // idiv
        16, 43, // bipush 43
        5, // iconst_2
        112, // irem
        96, // iadd
        16, 10, // bipush 10
        96, // iadd
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intDivRem",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 3,
        max_locals: 0,
        code_len: 13,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 32);
    drop method;
}

test "instruction executes long division and remainder normal paths" {
    const code: [14]u8 = [
        16, 42, // bipush 42
        133, // i2l
        5, // iconst_2
        133, // i2l
        109, // ldiv
        16, 43, // bipush 43
        133, // i2l
        5, // iconst_2
        133, // i2l
        113, // lrem
        97, // ladd
        173, // lreturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longDivRem",
        descriptor: "()J",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const result = try execute_method(&method);
    assert_long_result(result, 22);
    drop method;
}

test "instruction executes stack manipulation ops" {
    const first_code: [7]u8 = [
        16, 41, // bipush 41
        4, // iconst_1
        90, // dup_x1
        87, // pop
        96, // iadd
        172, // ireturn
    ];
    var first_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDupX1",
        descriptor: "()I",
        code: byte_buffer(first_code[..]),
        max_stack: 3,
        max_locals: 0,
        code_len: 7,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const first_result = try execute_method(&first_method);
    assert_int_result(first_result, 42);
    drop first_method;

    const second_code: [11]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        89, // dup
        87, // pop
        95, // swap
        100, // isub
        116, // ineg
        7, // iconst_4
        96, // iadd
        172, // ireturn
    ];
    var second_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDupSwap",
        descriptor: "()I",
        code: byte_buffer(second_code[..]),
        max_stack: 3,
        max_locals: 0,
        code_len: 11,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const second_result = try execute_method(&second_method);
    assert_int_result(second_result, 42);
    drop second_method;

    const third_code: [6]u8 = [
        4, // iconst_1
        5, // iconst_2
        88, // pop2
        16, 42, // bipush 42
        172, // ireturn
    ];
    var third_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackPop2",
        descriptor: "()I",
        code: byte_buffer(third_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 6,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const third_result = try execute_method(&third_method);
    assert_int_result(third_result, 42);
    drop third_method;

    const fourth_code: [8]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        3, // iconst_0
        91, // dup_x2
        87, // pop
        96, // iadd
        172, // ireturn
    ];
    var fourth_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDupX2",
        descriptor: "()I",
        code: byte_buffer(fourth_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const fourth_result = try execute_method(&fourth_method);
    assert_int_result(fourth_result, 42);
    drop fourth_method;

    const fifth_code: [8]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        92, // dup2
        96, // iadd
        96, // iadd
        96, // iadd
        172, // ireturn
    ];
    var fifth_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDup2",
        descriptor: "()I",
        code: byte_buffer(fifth_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const fifth_result = try execute_method(&fifth_method);
    assert_int_result(fifth_result, 84);
    drop fifth_method;

    const sixth_code: [10]u8 = [
        16, 40, // bipush 40
        3, // iconst_0
        5, // iconst_2
        93, // dup2_x1
        87, // pop
        87, // pop
        95, // swap
        96, // iadd
        172, // ireturn
    ];
    var sixth_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDup2X1",
        descriptor: "()I",
        code: byte_buffer(sixth_code[..]),
        max_stack: 5,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const sixth_result = try execute_method(&sixth_method);
    assert_int_result(sixth_result, 42);
    drop sixth_method;

    const seventh_code: [10]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        3, // iconst_0
        3, // iconst_0
        94, // dup2_x2
        87, // pop
        87, // pop
        96, // iadd
        172, // ireturn
    ];
    var seventh_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDup2X2",
        descriptor: "()I",
        code: byte_buffer(seventh_code[..]),
        max_stack: 6,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const seventh_result = try execute_method(&seventh_method);
    assert_int_result(seventh_result, 42);
    drop seventh_method;
}

test "instruction executes iinc shifts and bitwise int ops" {
    const code: [24]u8 = [
        16, 50, // bipush 50
        59, // istore_0
        132, 0, 248, // iinc 0, -8
        26, // iload_0
        4, // iconst_1
        120, // ishl
        4, // iconst_1
        122, // ishr
        16, 63, // bipush 63
        126, // iand
        16, 10, // bipush 10
        128, // ior
        16, 15, // bipush 15
        130, // ixor
        16, 15, // bipush 15
        130, // ixor
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intBitwise",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 1,
        code_len: 24,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes wide local access and iinc" {
    const code: [17]u8 = [
        16, 40, // bipush 40
        196, 54, 1, 4, // wide istore 260
        196, 132, 1, 4, 0, 2, // wide iinc 260, 2
        196, 21, 1, 4, // wide iload 260
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "wideLocals",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 261,
        code_len: 17,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes logical right shifts" {
    const int_code: [4]u8 = [
        2, // iconst_m1
        4, // iconst_1
        124, // iushr
        172, // ireturn
    ];
    var int_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intLogicalRightShift",
        descriptor: "()I",
        code: byte_buffer(int_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const int_result = try execute_method(&int_method);
    assert_int_result(int_result, 2147483647);
    drop int_method;

    const long_code: [7]u8 = [
        9, // lconst_0
        10, // lconst_1
        101, // lsub
        16, 63, // bipush 63
        125, // lushr
        173, // lreturn
    ];
    var long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longLogicalRightShift",
        descriptor: "()J",
        code: byte_buffer(long_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 7,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const long_result = try execute_method(&long_method);
    assert_long_result(long_result, 1);
    drop long_method;
}

test "instruction executes int and long conversions" {
    const int_to_long_code: [3]u8 = [
        2, // iconst_m1
        133, // i2l
        173, // lreturn
    ];
    var int_to_long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToLong",
        descriptor: "()J",
        code: byte_buffer(int_to_long_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const int_to_long_result = try execute_method(&int_to_long_method);
    assert_long_result(int_to_long_result, 0 - 1);
    drop int_to_long_method;

    const long_to_int_code: [8]u8 = [
        10, // lconst_1
        16, 32, // bipush 32
        121, // lshl
        10, // lconst_1
        129, // lor
        136, // l2i
        172, // ireturn
    ];
    var long_to_int_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longToInt",
        descriptor: "()I",
        code: byte_buffer(long_to_int_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const long_to_int_result = try execute_method(&long_to_int_method);
    assert_int_result(long_to_int_result, 1);
    drop long_to_int_method;
}

test "instruction executes integer to float and double conversions" {
    const int_to_float_code: [4]u8 = [
        16, 42, // bipush 42
        134, // i2f
        174, // freturn
    ];
    var int_to_float_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToFloat",
        descriptor: "()F",
        code: byte_buffer(int_to_float_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const int_to_float_result = try execute_method(&int_to_float_method);
    assert_float_result(int_to_float_result, 42.0);
    drop int_to_float_method;

    const int_to_double_code: [4]u8 = [
        16, 42, // bipush 42
        135, // i2d
        175, // dreturn
    ];
    var int_to_double_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToDouble",
        descriptor: "()D",
        code: byte_buffer(int_to_double_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const int_to_double_result = try execute_method(&int_to_double_method);
    assert_double_result(int_to_double_result, 42.0);
    drop int_to_double_method;

    const long_to_float_code: [5]u8 = [
        16, 42, // bipush 42
        133, // i2l
        137, // l2f
        174, // freturn
    ];
    var long_to_float_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longToFloat",
        descriptor: "()F",
        code: byte_buffer(long_to_float_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 5,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const long_to_float_result = try execute_method(&long_to_float_method);
    assert_float_result(long_to_float_result, 42.0);
    drop long_to_float_method;

    const long_to_double_code: [5]u8 = [
        16, 42, // bipush 42
        133, // i2l
        138, // l2d
        175, // dreturn
    ];
    var long_to_double_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longToDouble",
        descriptor: "()D",
        code: byte_buffer(long_to_double_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 5,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const long_to_double_result = try execute_method(&long_to_double_method);
    assert_double_result(long_to_double_result, 42.0);
    drop long_to_double_method;
}

test "instruction executes float and double conversions" {
    const float_to_int_code: [3]u8 = [
        13, // fconst_2
        139, // f2i
        172, // ireturn
    ];
    var float_to_int_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "floatToInt",
        descriptor: "()I",
        code: byte_buffer(float_to_int_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const float_to_int_result = try execute_method(&float_to_int_method);
    assert_int_result(float_to_int_result, 2);
    drop float_to_int_method;

    const float_to_long_code: [3]u8 = [
        13, // fconst_2
        140, // f2l
        173, // lreturn
    ];
    var float_to_long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "floatToLong",
        descriptor: "()J",
        code: byte_buffer(float_to_long_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const float_to_long_result = try execute_method(&float_to_long_method);
    assert_long_result(float_to_long_result, 2);
    drop float_to_long_method;

    const float_to_double_code: [3]u8 = [
        13, // fconst_2
        141, // f2d
        175, // dreturn
    ];
    var float_to_double_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "floatToDouble",
        descriptor: "()D",
        code: byte_buffer(float_to_double_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const float_to_double_result = try execute_method(&float_to_double_method);
    assert_double_result(float_to_double_result, 2.0);
    drop float_to_double_method;

    const double_to_int_code: [3]u8 = [
        15, // dconst_1
        142, // d2i
        172, // ireturn
    ];
    var double_to_int_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "doubleToInt",
        descriptor: "()I",
        code: byte_buffer(double_to_int_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const double_to_int_result = try execute_method(&double_to_int_method);
    assert_int_result(double_to_int_result, 1);
    drop double_to_int_method;

    const double_to_long_code: [3]u8 = [
        15, // dconst_1
        143, // d2l
        173, // lreturn
    ];
    var double_to_long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "doubleToLong",
        descriptor: "()J",
        code: byte_buffer(double_to_long_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const double_to_long_result = try execute_method(&double_to_long_method);
    assert_long_result(double_to_long_result, 1);
    drop double_to_long_method;

    const double_to_float_code: [3]u8 = [
        15, // dconst_1
        144, // d2f
        174, // freturn
    ];
    var double_to_float_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "doubleToFloat",
        descriptor: "()F",
        code: byte_buffer(double_to_float_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const double_to_float_result = try execute_method(&double_to_float_method);
    assert_float_result(double_to_float_result, 1.0);
    drop double_to_float_method;
}

test "instruction executes int byte char and short conversions" {
    const byte_code: [5]u8 = [
        17, 0, 128, // sipush 128
        145, // i2b
        172, // ireturn
    ];
    var byte_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToByte",
        descriptor: "()I",
        code: byte_buffer(byte_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 5,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const byte_result = try execute_method(&byte_method);
    assert_int_result(byte_result, 0 - 128);
    drop byte_method;

    const char_code: [3]u8 = [
        2, // iconst_m1
        146, // i2c
        172, // ireturn
    ];
    var char_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToChar",
        descriptor: "()I",
        code: byte_buffer(char_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const char_result = try execute_method(&char_method);
    assert_int_result(char_result, 65535);
    drop char_method;

    const short_code: [6]u8 = [
        4, // iconst_1
        16, 15, // bipush 15
        120, // ishl
        147, // i2s
        172, // ireturn
    ];
    var short_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToShort",
        descriptor: "()I",
        code: byte_buffer(short_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 6,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const short_result = try execute_method(&short_method);
    assert_int_result(short_result, 0 - 32768);
    drop short_method;
}

test "instruction executes unary int branches" {
    const code: [45]u8 = [
        3, // iconst_0
        153, 0, 6, // ifeq ok1
        16, 0, // bipush 0
        172, // ireturn
        4, // iconst_1
        154, 0, 6, // ifne ok2
        16, 0, // bipush 0
        172, // ireturn
        2, // iconst_m1
        155, 0, 6, // iflt ok3
        16, 0, // bipush 0
        172, // ireturn
        3, // iconst_0
        156, 0, 6, // ifge ok4
        16, 0, // bipush 0
        172, // ireturn
        4, // iconst_1
        157, 0, 6, // ifgt ok5
        16, 0, // bipush 0
        172, // ireturn
        3, // iconst_0
        158, 0, 6, // ifle ok6
        16, 0, // bipush 0
        172, // ireturn
        16, 42, // bipush 42
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "unaryBranches",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 45,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes int compare branches and goto loop" {
    const code: [31]u8 = [
        3, // iconst_0
        59, // istore_0
        3, // iconst_0
        60, // istore_1
        26, // iload_0
        16, 7, // bipush 7
        162, 0, 13, // if_icmpge end
        27, // iload_1
        26, // iload_0
        96, // iadd
        60, // istore_1
        132, 0, 1, // iinc 0, 1
        167, 255, 243, // goto loop
        27, // iload_1
        16, 21, // bipush 21
        160, 0, 6, // if_icmpne fail
        16, 42, // bipush 42
        172, // ireturn
        3, // iconst_0
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "compareLoop",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 2,
        code_len: 31,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes table and lookup switches" {
    const table_code: [40]u8 = [
        4, // iconst_1
        170, // tableswitch
        0, 0, // padding
        0, 0, 0, 27, // default
        0, 0, 0, 0, // low
        0, 0, 0, 2, // high
        0, 0, 0, 30, // case 0
        0, 0, 0, 33, // case 1
        0, 0, 0, 36, // case 2
        16, 0, 172, // default: return 0
        16, 10, 172, // case 0: return 10
        16, 42, 172, // case 1: return 42
        16, 7, 172, // case 2: return 7
    ];
    var table_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "tableSwitch",
        descriptor: "()I",
        code: byte_buffer(table_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 40,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const table_result = try execute_method(&table_method);
    assert_int_result(table_result, 42);
    drop table_method;

    const lookup_code: [37]u8 = [
        5, // iconst_2
        171, // lookupswitch
        0, 0, // padding
        0, 0, 0, 27, // default
        0, 0, 0, 2, // npairs
        255, 255, 255, 255, // match -1
        0, 0, 0, 30, // case -1
        0, 0, 0, 2, // match 2
        0, 0, 0, 33, // case 2
        16, 0, 172, // default: return 0
        16, 10, 172, // case -1: return 10
        16, 42, 172, // case 2: return 42
    ];
    var lookup_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "lookupSwitch",
        descriptor: "()I",
        code: byte_buffer(lookup_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 37,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const lookup_result = try execute_method(&lookup_method);
    assert_int_result(lookup_result, 42);
    drop lookup_method;
}

test "instruction executes jsr ret and jsr_w subroutines" {
    const jsr_code: [9]u8 = [
        168, 0, 6, // jsr subroutine
        16, 42, // bipush 42
        172, // ireturn
        75, // astore_0
        169, 0, // ret 0
    ];
    var jsr_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "jsrRet",
        descriptor: "()I",
        code: byte_buffer(jsr_code[..]),
        max_stack: 1,
        max_locals: 1,
        code_len: 9,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const jsr_result = try execute_method(&jsr_method);
    assert_int_result(jsr_result, 42);
    drop jsr_method;

    const wide_ret_code: [14]u8 = [
        168, 0, 6, // jsr subroutine
        16, 42, // bipush 42
        172, // ireturn
        196, 58, 1, 4, // wide astore 260
        196, 169, 1, 4, // wide ret 260
    ];
    var wide_ret_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "wideRet",
        descriptor: "()I",
        code: byte_buffer(wide_ret_code[..]),
        max_stack: 1,
        max_locals: 261,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const wide_ret_result = try execute_method(&wide_ret_method);
    assert_int_result(wide_ret_result, 42);
    drop wide_ret_method;

    const jsr_w_code: [11]u8 = [
        201, 0, 0, 0, 8, // jsr_w subroutine
        16, 42, // bipush 42
        172, // ireturn
        75, // astore_0
        169, 0, // ret 0
    ];
    var jsr_w_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "jsrWide",
        descriptor: "()I",
        code: byte_buffer(jsr_w_code[..]),
        max_stack: 1,
        max_locals: 1,
        code_len: 11,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const jsr_w_result = try execute_method(&jsr_w_method);
    assert_int_result(jsr_w_result, 42);
    drop jsr_w_method;
}

test "instruction executes nop and goto_w" {
    const code: [12]u8 = [
        0, // nop
        200, 0, 0, 0, 8, // goto_w target
        16, 0, // bipush skipped
        172, // ireturn skipped
        16, 42, // bipush target
        172, // ireturn target
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "nopGotoWide",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes reference load store and returns" {
    const ref_code: [4]u8 = [
        1, // aconst_null
        76, // astore_1
        43, // aload_1
        176, // areturn
    ];
    var ref_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "returnNull",
        descriptor: "()Ljava/lang/Object;",
        code: byte_buffer(ref_code[..]),
        max_stack: 1,
        max_locals: 2,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "Ljava/lang/Object;",
    };

    const ref_result = try execute_method(&ref_method);
    assert_null_ref_result(ref_result);
    drop ref_method;

    const void_code: [1]u8 = [
        177, // return
    ];
    var void_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "returnVoid",
        descriptor: "()V",
        code: byte_buffer(void_code[..]),
        max_stack: 0,
        max_locals: 0,
        code_len: 1,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "V",
    };

    const void_result = try execute_method(&void_method);
    assert_void_result(void_result);
    drop void_method;
}

test "instruction executes athrow with existing exception reference" {
    const code: [1]u8 = [191];
    var constant_pool: [:]Constant = [: 0][];
    var vm = new_vm();
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 1),
        code: code[..],
        constant_pool: constant_pool[..]
    };
    const exception = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    context.frame.push(.ref_value(exception));

    const execute_result = execute_next(&context, &vm);
    switch execute_result {
        case .ok {}
        case .err {
            assert(false);
        }
    }

    if context.frame.result is result {
        assert_exception_result(result, exception);
    } else {
        assert(false);
    }
    drop context;
}

test "instruction dispatches local exception handler" {
    const code: [5]u8 = [
        42, // aload_0
        191, // athrow
        76, // astore_1 handler
        8, // iconst_5
        172, // ireturn
    ];
    var constant_pool: [:]Constant = [: 0][];
    const handler = ExceptionHandler {
        start_pc: 0,
        end_pc: 2,
        handle_pc: 2,
        catch_type: 0,
    };
    var classes: [2]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(8),
                    name: "catchLocal",
                    descriptor: "(Ljava/lang/Throwable;)I",
                    code: byte_buffer(code[..]),
                    max_stack: 1,
                    max_locals: 2,
                    code_len: 5,
                    exception_count: 1,
                    exception_handlers: [handler],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Throwable".bytes()),
            descriptor: "LThrowable;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Throwable.java",
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
    var frame = new_frame(0, 0, 2, 1);
    const exception = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    frame.store(0, .ref_value(exception));

    const result = try execute_method_frame_with_vm(&vm, 0, 0, frame, constant_pool[..]);
    assert_int_result(result, 5);
    drop classes;
}

test "instruction dispatches propagated call exception handler" {
    const constant_pool: [7]Constant = [
        .unusable(0),
        .utf8("Helper"),
        .class_ref(1),
        .utf8("throwIt"),
        .utf8("(Ljava/lang/Throwable;)I"),
        .name_and_type(ConstantNameAndType {
            name_index: 3,
            descriptor_index: 4
        }),
        .method_ref(ConstantMemberRef {
            class_index: 2,
            name_and_type_index: 5
        }),
    ];
    const caller_code: [7]u8 = [
        42, // aload_0
        184, 0, 6, // invokestatic Helper.throwIt
        76, // astore_1 handler
        6, // iconst_3
        172, // ireturn
    ];
    const callee_code: [2]u8 = [
        42, // aload_0
        191, // athrow
    ];
    const caller_handler = ExceptionHandler {
        start_pc: 1,
        end_pc: 4,
        handle_pc: 4,
        catch_type: 0,
    };
    var classes: [3]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(8),
                    name: "catchCall",
                    descriptor: "(Ljava/lang/Throwable;)I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 2,
                    code_len: 7,
                    exception_count: 1,
                    exception_handlers: [caller_handler],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Helper".bytes()),
            descriptor: "LHelper;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Helper",
                    access_flags: method_access_flags(8),
                    name: "throwIt",
                    descriptor: "(Ljava/lang/Throwable;)I",
                    code: byte_buffer(callee_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Helper.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Throwable".bytes()),
            descriptor: "LThrowable;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Throwable.java",
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
    var frame = new_frame(0, 0, 2, 1);
    const exception = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    frame.store(0, .ref_value(exception));

    const result = try execute_method_frame_with_vm(&vm, 0, 0, frame, constant_pool[..]);
    assert_int_result(result, 3);
    drop classes;
}

test "instruction executes int array creation load store and length" {
    const code: [18]u8 = [
        6, // iconst_3
        188, 10, // newarray int
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        16, 41, // bipush 41
        79, // iastore
        42, // aload_0
        4, // iconst_1
        46, // iaload
        42, // aload_0
        190, // arraylength
        96, // iadd
        5, // iconst_2
        100, // isub
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intArray",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 18,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes anewarray reference array creation" {
    const code: [8]u8 = [
        5, // iconst_2
        189, 0, 2, // anewarray java/lang/Object
        75, // astore_0
        42, // aload_0
        190, // arraylength
        172, // ireturn
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("java/lang/Object"),
        .class_ref(1),
    ];
    var classes: [1]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "referenceArray",
                    descriptor: "()I",
                    code: byte_buffer(code[..]),
                    max_stack: 2,
                    max_locals: 1,
                    code_len: 8,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
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

    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, classes[0].methods[0].max_locals, classes[0].methods[0].max_stack), constant_pool[..]);
    assert_int_result(result, 2);
    if vm.heap.get_element(Reference {
        kind: ReferenceKind.array,
        slot: 0,
        generation: 0
    }, 0) is value {
        switch value {
            case .ref_value(reference) {
                assert(reference.is_null());
            } else {
                assert(false);
            }
        }
    } else {
        assert(false);
    }
    vm.clear();
    drop classes;
}

test "instruction executes checkcast and instanceof normal paths" {
    const pass_code: [10]u8 = [
        187, 0, 2, // new Child
        192, 0, 4, // checkcast Base
        193, 0, 6, // instanceof Iface
        172, // ireturn
    ];
    const null_code: [5]u8 = [
        1, // aconst_null
        193, 0, 4, // instanceof Base
        172, // ireturn
    ];
    const miss_code: [7]u8 = [
        187, 0, 8, // new Other
        193, 0, 6, // instanceof Iface
        172, // ireturn
    ];
    const constant_pool: [9]Constant = [
        .unusable(0),
        .utf8("Child"),
        .class_ref(1),
        .utf8("Base"),
        .class_ref(3),
        .utf8("Iface"),
        .class_ref(5),
        .utf8("Other"),
        .class_ref(7),
    ];
    var classes: [5]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "pass",
                    descriptor: "()I",
                    code: byte_buffer(pass_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 10,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "nullCheck",
                    descriptor: "()I",
                    code: byte_buffer(null_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 5,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "miss",
                    descriptor: "()I",
                    code: byte_buffer(miss_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 7,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Base".bytes()),
            descriptor: "LBase;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Base.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Child".bytes()),
            descriptor: "LChild;",
            access_flags: class_access_flags(0x0021),
            super_class: "Base",
            interfaces: ["Iface"],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Child.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Iface".bytes()),
            descriptor: "LIface;",
            access_flags: class_access_flags(0x0601),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Iface.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Other".bytes()),
            descriptor: "LOther;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Other.java",
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

    const pass_result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, classes[0].methods[0].max_locals, classes[0].methods[0].max_stack), constant_pool[..]);
    const null_result = try execute_method_frame_with_vm(&vm, 0, 1, new_frame(0, 1, classes[0].methods[1].max_locals, classes[0].methods[1].max_stack), constant_pool[..]);
    const miss_result = try execute_method_frame_with_vm(&vm, 0, 2, new_frame(0, 2, classes[0].methods[2].max_locals, classes[0].methods[2].max_stack), constant_pool[..]);
    assert_int_result(pass_result, 1);
    assert_int_result(null_result, 0);
    assert_int_result(miss_result, 0);
    drop classes;
}

test "instruction executes monitorenter and monitorexit normal paths" {
    const code: [8]u8 = [
        187, 0, 2, // new Main
        89, // dup
        194, // monitorenter
        195, // monitorexit
        4, // iconst_1
        172, // ireturn
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("Main"),
        .class_ref(1),
    ];
    var classes: [1]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "monitor",
                    descriptor: "()I",
                    code: byte_buffer(code[..]),
                    max_stack: 2,
                    max_locals: 0,
                    code_len: 8,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
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

    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, classes[0].methods[0].max_locals, classes[0].methods[0].max_stack), constant_pool[..]);
    assert_int_result(result, 1);
    assert(vm.heap.object_count() == 1);
    drop classes;
}

test "instruction executes multianewarray normal path" {
    const code: [8]u8 = [
        5, // iconst_2 outer length
        6, // iconst_3 inner length
        197, 0, 2, 2, // multianewarray [[I, 2 dimensions
        190, // arraylength
        172, // ireturn
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("[[I"),
        .class_ref(1),
    ];
    var classes: [1]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "multiArray",
                    descriptor: "()I",
                    code: byte_buffer(code[..]),
                    max_stack: 2,
                    max_locals: 0,
                    code_len: 8,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
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

    const result = try execute_method_frame_with_vm(&vm, 0, 0, new_frame(0, 0, classes[0].methods[0].max_locals, classes[0].methods[0].max_stack), constant_pool[..]);
    assert_int_result(result, 2);
    assert(vm.heap.array_count() == 3);
    if vm.heap.get_element(Reference {
        kind: ReferenceKind.array,
        slot: 0,
        generation: 0
    }, 0) is value {
        switch value {
            case .ref_value(reference) {
                if vm.heap.array_length(reference) is length {
                    assert(length == 3);
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
    drop classes;
}

test "instruction executes wide and floating array load store ops" {
    const long_code: [14]u8 = [
        5, // iconst_2
        188, 11, // newarray long
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        16, 42, // bipush 42
        133, // i2l
        80, // lastore
        42, // aload_0
        4, // iconst_1
        47, // laload
        173, // lreturn
    ];
    var long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longArray",
        descriptor: "()J",
        code: byte_buffer(long_code[..]),
        max_stack: 4,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const long_result = try execute_method(&long_method);
    assert_long_result(long_result, 42);
    drop long_method;

    const float_code: [12]u8 = [
        5, // iconst_2
        188, 6, // newarray float
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        13, // fconst_2
        81, // fastore
        42, // aload_0
        4, // iconst_1
        48, // faload
        174, // freturn
    ];
    var float_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "floatArray",
        descriptor: "()F",
        code: byte_buffer(float_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const float_result = try execute_method(&float_method);
    assert_float_result(float_result, 2.0);
    drop float_method;

    const double_code: [12]u8 = [
        5, // iconst_2
        188, 7, // newarray double
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        15, // dconst_1
        82, // dastore
        42, // aload_0
        4, // iconst_1
        49, // daload
        175, // dreturn
    ];
    var double_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "doubleArray",
        descriptor: "()D",
        code: byte_buffer(double_code[..]),
        max_stack: 4,
        max_locals: 1,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const double_result = try execute_method(&double_method);
    assert_double_result(double_result, 1.0);
    drop double_method;
}

test "instruction executes narrow array load store ops" {
    const byte_code: [14]u8 = [
        4, // iconst_1
        188, 8, // newarray byte
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        17, 0, 255, // sipush 255
        84, // bastore
        42, // aload_0
        3, // iconst_0
        51, // baload
        172, // ireturn
    ];
    var byte_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "byteArray",
        descriptor: "()I",
        code: byte_buffer(byte_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const byte_result = try execute_method(&byte_method);
    assert_int_result(byte_result, 0 - 1);
    drop byte_method;

    const char_code: [14]u8 = [
        4, // iconst_1
        188, 5, // newarray char
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        17, 0, 255, // sipush 255
        85, // castore
        42, // aload_0
        3, // iconst_0
        52, // caload
        172, // ireturn
    ];
    var char_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "charArray",
        descriptor: "()I",
        code: byte_buffer(char_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const char_result = try execute_method(&char_method);
    assert_int_result(char_result, 255);
    drop char_method;

    const short_code: [14]u8 = [
        4, // iconst_1
        188, 9, // newarray short
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        17, 128, 0, // sipush -32768
        86, // sastore
        42, // aload_0
        3, // iconst_0
        53, // saload
        172, // ireturn
    ];
    var short_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "shortArray",
        descriptor: "()I",
        code: byte_buffer(short_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const short_result = try execute_method(&short_method);
    assert_int_result(short_result, 0 - 32768);
    drop short_method;

    const boolean_code: [12]u8 = [
        4, // iconst_1
        188, 4, // newarray boolean
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        4, // iconst_1
        84, // bastore
        42, // aload_0
        3, // iconst_0
        51, // baload
        172, // ireturn
    ];
    var boolean_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "booleanArray",
        descriptor: "()I",
        code: byte_buffer(boolean_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const boolean_result = try execute_method(&boolean_method);
    assert_int_result(boolean_result, 1);
    drop boolean_method;
}

test "instruction executes reference array load store ops" {
    const store_code: [1]u8 = [83];
    var constant_pool: [:]Constant = [: 0][];
    var vm = new_vm();
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 3),
        code: store_code[..],
        constant_pool: constant_pool[..]
    };
    const reference = vm.heap.allocate_array(0, "Ljava/lang/Object;".bytes(), 1);

    context.frame.push(.ref_value(reference));
    push_int(&context, 0);
    context.frame.push(.ref_value(null_ref));
    const store_result = execute_next(&context, &vm);
    switch store_result {
        case .ok {}
        case .err {
            assert(false);
        }
    }

    const load_code: [1]u8 = [50];
    context.frame.clear();
    context.frame.pc = 0;
    context.frame.offset = 1;
    context.code = load_code[..];
    context.frame.push(.ref_value(reference));
    push_int(&context, 0);
    const load_result = execute_next(&context, &vm);
    switch load_result {
        case .ok {}
        case .err {
            assert(false);
        }
    }

    const loaded = expect_ref(context.frame.pop());
    assert(loaded.is_null());
    drop context;
}

test "instruction executes reference comparison and null branches" {
    const code: [29]u8 = [
        1, // aconst_null
        75, // astore_0
        42, // aload_0
        198, 0, 5, // ifnull ok1
        3, // iconst_0
        172, // ireturn
        42, // aload_0
        199, 0, 18, // ifnonnull fail
        1, // aconst_null
        42, // aload_0
        165, 0, 5, // if_acmpeq ok2
        3, // iconst_0
        172, // ireturn
        42, // aload_0
        1, // aconst_null
        166, 0, 6, // if_acmpne fail
        16, 42, // bipush 42
        172, // ireturn
        3, // iconst_0
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "refBranches",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 1,
        code_len: 29,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes long local arithmetic and return" {
    const code: [12]u8 = [
        10, // lconst_1
        64, // lstore_1
        31, // lload_1
        31, // lload_1
        97, // ladd
        31, // lload_1
        101, // lsub
        31, // lload_1
        105, // lmul
        117, // lneg
        117, // lneg
        173, // lreturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longArithmetic",
        descriptor: "()J",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 3,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const result = try execute_method(&method);
    assert_long_result(result, 1);
    drop method;
}

test "instruction executes long shifts and bitwise ops" {
    const shift_code: [8]u8 = [
        10, // lconst_1
        16, 6, // bipush 6
        121, // lshl
        16, 1, // bipush 1
        123, // lshr
        173, // lreturn
    ];
    var shift_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longBitwise",
        descriptor: "()J",
        code: byte_buffer(shift_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const shift_result = try execute_method(&shift_method);
    assert_long_result(shift_result, 32);
    drop shift_method;

    const bitwise_code: [10]u8 = [
        10, // lconst_1
        9, // lconst_0
        127, // land
        10, // lconst_1
        129, // lor
        10, // lconst_1
        131, // lxor
        10, // lconst_1
        131, // lxor
        173, // lreturn
    ];
    var bitwise_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longBitwise",
        descriptor: "()J",
        code: byte_buffer(bitwise_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const bitwise_result = try execute_method(&bitwise_method);
    assert_long_result(bitwise_result, 1);
    drop bitwise_method;
}

test "instruction executes long operand load store and compare" {
    const code: [17]u8 = [
        10, // lconst_1
        55, 2, // lstore 2
        22, 2, // lload 2
        10, // lconst_1
        148, // lcmp
        153, 0, 5, // ifeq ok1
        3, // iconst_0
        172, // ireturn
        9, // lconst_0
        22, 2, // lload 2
        148, // lcmp
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longCompare",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 4,
        code_len: 17,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 0 - 1);
    drop method;
}

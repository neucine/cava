import { Constant } from .classfile;
import {
    byte,
    short,
    char,
    int,
    long,
    float,
    double,
    boolean,
    return_address,
    ReferenceKind,
    Reference,
    Value,
    true_value,
    false_value,
    InstructionError,
    ObjectRef,
    ArrayRef,
    JavaLangClass,
    JavaLangString,
    JavaLangThread,
    JavaLangThrowable,
    JavaLangClassLoader,
    JavaLangReflectField,
    JavaLangReflectConstructor,
    null_ref,
    descriptor_tag,
    default_value,
    is_primitive_descriptor,
    method_argument_count,
    reference_array_component_descriptor,
    reference_array_descriptor,
    array_component_descriptor,
    ClassAccessFlags,
    FieldAccessFlags,
    MethodAccessFlags,
    class_access_flags,
    field_access_flags,
    method_access_flags,
    raw_class_access,
    raw_field_access,
    raw_method_access,
    ExceptionHandler,
    Field,
    Method,
    byte_buffer,
    java_utf16_units_from_utf8,
    LocalVariable,
    LineNumber,
    Class,
    fail_unexpected_value
} from .types;

test "copy duplicates method bytecode and handler storage" {
    const original = Method {
        class_name: "Example",
        access_flags: method_access_flags(0x0001),
        name: "run",
        descriptor: "()V",
        code: [0xb1],
        max_stack: 1,
        max_locals: 1,
        code_len: 1,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "V",
    };
    var duplicated = copy original;
    duplicated.code[0] = 0;
    assert(original.code[0] == 0xb1);
    assert(duplicated.code[0] == 0);
    assert(original.name == "run");
    assert(original.is_static() == false);
}

test "types decodes UTF-8 bytes to Java UTF-16 units" {
    const raw: [4]u8 = [0x37, 0xE4, 0xA0, 0x80];
    const units = java_utf16_units_from_utf8(raw[..]);
    assert(units.len() == 2);
    assert(units[0] == 55);
    assert(units[1] == 0x4800);
    drop units;
}

test "null reference equality" {
    const first = null_ref;
    const second = Reference.init_null();
    assert(first.is_null());
    assert(first.equals(second));
}

test "primitive descriptor defaults" {
    switch default_value("I".bytes()) {
        case .int_value(value) {
            assert(value == 0);
        }
        case .byte_value(value) {
            fail_unexpected_value(.byte_value(value));
        }
        case .short_value(value) {
            fail_unexpected_value(.short_value(value));
        }
        case .char_value(value) {
            fail_unexpected_value(.char_value(value));
        }
        case .long_value(value) {
            fail_unexpected_value(.long_value(value));
        }
        case .float_value(value) {
            fail_unexpected_value(.float_value(value));
        }
        case .double_value(value) {
            fail_unexpected_value(.double_value(value));
        }
        case .boolean_value(value) {
            fail_unexpected_value(.boolean_value(value));
        }
        case .return_address_value(value) {
            fail_unexpected_value(.return_address_value(value));
        }
        case .ref_value(value) {
            fail_unexpected_value(.ref_value(value));
        }
    }

    switch default_value("Z".bytes()) {
        case .boolean_value(value) {
            assert(value == false_value);
        }
        case .byte_value(value) {
            fail_unexpected_value(.byte_value(value));
        }
        case .short_value(value) {
            fail_unexpected_value(.short_value(value));
        }
        case .char_value(value) {
            fail_unexpected_value(.char_value(value));
        }
        case .int_value(value) {
            fail_unexpected_value(.int_value(value));
        }
        case .long_value(value) {
            fail_unexpected_value(.long_value(value));
        }
        case .float_value(value) {
            fail_unexpected_value(.float_value(value));
        }
        case .double_value(value) {
            fail_unexpected_value(.double_value(value));
        }
        case .return_address_value(value) {
            fail_unexpected_value(.return_address_value(value));
        }
        case .ref_value(value) {
            fail_unexpected_value(.ref_value(value));
        }
    }
}

test "reference descriptor default" {
    switch default_value("Ljava/lang/Object;".bytes()) {
        case .ref_value(reference) {
            assert(reference.is_null());
        }
        case .byte_value(value) {
            fail_unexpected_value(.byte_value(value));
        }
        case .short_value(value) {
            fail_unexpected_value(.short_value(value));
        }
        case .char_value(value) {
            fail_unexpected_value(.char_value(value));
        }
        case .int_value(value) {
            fail_unexpected_value(.int_value(value));
        }
        case .long_value(value) {
            fail_unexpected_value(.long_value(value));
        }
        case .float_value(value) {
            fail_unexpected_value(.float_value(value));
        }
        case .double_value(value) {
            fail_unexpected_value(.double_value(value));
        }
        case .boolean_value(value) {
            fail_unexpected_value(.boolean_value(value));
        }
        case .return_address_value(value) {
            fail_unexpected_value(.return_address_value(value));
        }
    }
}

test "primitive descriptor detection" {
    assert(is_primitive_descriptor("I".bytes()));
    assert(is_primitive_descriptor("Z".bytes()));
    assert(!is_primitive_descriptor("[I".bytes()));
    assert(!is_primitive_descriptor("Ljava/lang/Object;".bytes()));
}

test "access flags decode raw JVM bits" {
    const class_flags = class_access_flags(0x0421);
    assert(ClassAccessFlags.public in class_flags);
    assert(ClassAccessFlags.super_flag in class_flags);
    assert(ClassAccessFlags.abstract in class_flags);
    assert(raw_class_access(class_flags) == 0x0421);

    const field_flags = field_access_flags(0x0019);
    assert(FieldAccessFlags.public in field_flags);
    assert(FieldAccessFlags.static_flag in field_flags);
    assert(FieldAccessFlags.final in field_flags);
    assert(raw_field_access(field_flags) == 0x0019);

    const method_flags = method_access_flags(0x0109);
    assert(MethodAccessFlags.public in method_flags);
    assert(MethodAccessFlags.static_flag in method_flags);
    assert(MethodAccessFlags.native in method_flags);
    assert(raw_method_access(method_flags) == 0x0109);
}

test "class metadata supports field and method lookup" {
    const field = Field {
        class_name: "Example",
        access_flags: field_access_flags(0x0008),
        name: "answer",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    const method = Method {
        class_name: "Example",
        access_flags: method_access_flags(0x0009),
        name: "main",
        descriptor: "([Ljava/lang/String;)V",
        code: byte_buffer("A".bytes()),
        max_stack: 2,
        max_locals: 1,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 1,
        return_descriptor: "V",
    };
    const class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [field],
        methods: [method],
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

    const found_field = class.field_index("answer", "I", true);
    if found_field is value {
        assert(value == 0);
    } else {
        assert(false);
    }

    const found_method = class.method_index("main", "([Ljava/lang/String;)V", true);
    if found_method is value {
        assert(value == 0);
        assert(class.methods[value as usize].max_stack == 2);
        assert(class.methods[value as usize].parameter_count == 1);
    } else {
        assert(false);
    }

    assert(!class.has_field("answer", "I", false));
    assert(!class.has_method("missing", "()V", true));
}

import {
    AttributeInfo,
    ByteReader,
    ClassFile,
    ClassfileError,
    Constant,
    ConstantMemberRef,
    ConstantNameAndType,
    MemberInfo,
    new_classfile,
    parse_classfile
} from .classfile;
import {
    Class,
    ExceptionHandler,
    Field,
    Method,
    Reference,
    Value,
    byte_buffer,
    class_access_flags,
    default_value,
    field_access_flags,
    method_access_flags,
    null_ref
} from .types;
import { FsError, read_file } from std.fs;
import { index_of } from std.mem;
import {
    MethodAreaError,
    method_area_error_from_fs,
    SymbolPool,
    new_symbol_pool,
    ResolvedMethod,
    find_loaded_class_index,
    class_matches,
    class_named,
    reference_assignable_to,
    class_index_by_name,
    class_instance_var_count,
    hierarchy_instance_var_count,
    field_slot_offset,
    runtime_field_slot,
    contains_class_index,
    project_root_from_example_class_path,
    MethodArea,
    duplicate_loaded_class,
    new_method_area,
    empty_code,
    owned_text,
    builtin_field,
    builtin_method,
    builtin_object_class,
    builtin_print_stream_class,
    builtin_system_class,
    builtin_string_builder_class,
    builtin_class,
    array_descriptor_from_class_name,
    descriptor_array_end,
    class_file_path,
    ResolvedFieldRef,
    ResolvedMethodRef,
    first_type_bytes,
    method_parameter_count,
    method_return_descriptor,
    array_component_type,
    array_element_type,
    array_dimensions,
    class_descriptor_from_name,
    derive_array_class,
    CodeInfo,
    empty_code_info,
    apply_code_attribute_info,
    code_info_from_attribute,
    member_code_info,
    derive_interfaces_into,
    derive_fields,
    derive_static_vars,
    instance_var_count,
    derive_source_file,
    derive_methods,
    derive_class
} from .method_area;

test "method descriptor parser extracts parameter count and return type" {
    const descriptor = "([Ljava/lang/String;I)Ljava/lang/Object;";
    const descriptor_bytes = descriptor.bytes();
    const first = first_type_bytes(descriptor_bytes[1..descriptor_bytes.len()]);
    assert(first.len() == 19);
    assert(first[0] == '[');
    assert(first[18] == ';');
    assert(method_parameter_count(descriptor) == 2);

    const ret = method_return_descriptor(descriptor);
    assert(ret.len() == 18);
    assert(ret.bytes()[0] == 'L');
    assert(ret.bytes()[17] == ';');
    drop ret;
}

test "method area parses array class descriptor metadata" {
    const name = "[[Ljava/lang/String;";
    var class = derive_array_class(name);

    assert(class.is_array);
    assert(class.name.len() == 20);
    assert(class.descriptor.len() == 20);
    assert(class.super_class.len() == 16);
    assert(class.interfaces.len() == 2);
    const component_type = class.component_type.bytes();
    const element_type = class.element_type.bytes();
    assert(component_type[0] == '[');
    assert(element_type[0] == 'L');
    assert(class.dimensions == 2);
    assert(class.fields.len() == 0);
    assert(class.methods.len() == 0);
}

test "symbol pool deduplicates byte names" {
    var pool = new_symbol_pool();
    pool.add("abc".bytes());
    pool.add("abc".bytes());
    assert(pool.contains("abc".bytes()));
    assert(!pool.contains("xyz".bytes()));
    assert(pool.symbols.len() == 1);
    pool.clear();
    drop pool;
}

test "method area defines parsed classes once" {
    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main"),
            .class_ref(1)
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 0,
        interfaces: [],
        fields: [],
        methods: [],
        attributes: [],
    };

    var area = new_method_area();
    const first = try area.define_class(&classfile);
    const second = try area.define_class(&classfile);

    assert(first == 0);
    assert(second == 0);
    assert(area.classes.len() == 1);
    assert(area.has_class("Main"));
    assert(area.symbols.symbols.len() == 1);
}

test "method area synthesizes array classes once" {
    var area = new_method_area();
    const first = area.define_array_class("[I");
    const second = area.define_array_class("[I");

    assert(first == 0);
    assert(second == 0);
    assert(area.classes.len() == 1);
    assert(area.classes[0].is_array);
    const component_type = area.classes[0].component_type.bytes();
    assert(component_type[0] == 'I');
    assert(area.has_class("[I"));
}

test "method area loads class from bytes" {
    var data: [:]u8 = [
        0xCA, 0xFE, 0xBA, 0xBE, // magic
        0, 0, 0, 52, // minor, major
        0, 3, // constant_pool_count
        1, 0, 4, 77, 97, 105, 110, // #1 utf8 Main
        7, 0, 1, // #2 class Main
        0, 33, // access_flags
        0, 2, // this_class
        0, 0, // super_class
        0, 0, // interfaces_count
        0, 0, // fields_count
        0, 0, // methods_count
        0, 0 // attributes_count
    ];

    var area = new_method_area();
    const index = try area.load_class_from_bytes(data[..]);
    assert(index == 0);
    assert(area.has_class("Main"));
    assert(area.classes[0].descriptor.len() == 6);
}

test "method area resolves class field and method refs" {
    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main"),
            .class_ref(1),
            .utf8("answer"),
            .utf8("I"),
            .name_and_type(ConstantNameAndType {
                name_index: 3,
                descriptor_index: 4
            }),
            .field_ref(ConstantMemberRef {
                class_index: 2,
                name_and_type_index: 5
            }),
            .utf8("run"),
            .utf8("()I"),
            .name_and_type(ConstantNameAndType {
                name_index: 7,
                descriptor_index: 8
            }),
            .method_ref(ConstantMemberRef {
                class_index: 2,
                name_and_type_index: 9
            })
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 0,
        interfaces: [],
        fields: [MemberInfo {
            access_flags: 8,
            name_index: 3,
            descriptor_index: 4,
            attributes: []
        }],
        methods: [MemberInfo {
            access_flags: 9,
            name_index: 7,
            descriptor_index: 8,
            attributes: []
        }],
        attributes: [],
    };

    var area = new_method_area();
    const class_index = try area.define_class(&classfile);
    const resolved_class = try area.resolve_class_ref(&classfile, 2);
    const resolved_field = try area.resolve_field_ref(&classfile, 6);
    const resolved_method = try area.resolve_method_ref(&classfile, 10);

    assert(class_index == 0);
    assert(resolved_class == 0);
    assert(resolved_field.class_index == 0);
    assert(resolved_field.field_index == 0);
    assert(resolved_method.class_index == 0);
    assert(resolved_method.method_index == 0);
}

test "class file path builds classpath-relative paths" {
    var relative = class_file_path("classes", "java/lang/Object");
    assert(relative == "classes/java/lang/Object.class");

    var rooted = class_file_path("classes/", "Main");
    assert(rooted == "classes/Main.class");

    var bare = class_file_path("", "Main");
    assert(bare == "Main.class");

    drop relative;
    drop rooted;
    drop bare;
}

test "method area derives class metadata from classfile" {
    var code_raw: [:]u8 = [
        0, 2, // max_stack
        0, 1, // max_locals
        0, 0, 0, 2, // code_length
        4, 172, // iconst_1, ireturn
        0, 0, // exception_table_length
        0, 2, // attributes_count
        0, 15, // LineNumberTable name_index
        0, 0, 0, 6, // LineNumberTable length
        0, 1, // line_number_table_length
        0, 0, // start_pc
        0, 42, // line_number
        0, 16, // LocalVariableTable name_index
        0, 0, 0, 12, // LocalVariableTable length
        0, 1, // local_variable_table_length
        0, 0, // start_pc
        0, 2, // length
        0, 10, // name_index
        0, 8, // descriptor_index
        0, 0 // index
    ];

    var source_raw: [:]u8 = [0, 14];

    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main"),
            .class_ref(1),
            .utf8("java/lang/Object"),
            .class_ref(3),
            .utf8("Runnable"),
            .class_ref(5),
            .utf8("answer"),
            .utf8("I"),
            .utf8("value"),
            .utf8("run"),
            .utf8("()I"),
            .utf8("Code"),
            .utf8("SourceFile"),
            .utf8("Main.java"),
            .utf8("LineNumberTable"),
            .utf8("LocalVariableTable")
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 4,
        interfaces: [6],
        fields: [MemberInfo {
            access_flags: 8,
            name_index: 7,
            descriptor_index: 8,
            attributes: []
        }, MemberInfo {
            access_flags: 1,
            name_index: 9,
            descriptor_index: 8,
            attributes: []
        }],
        methods: [MemberInfo {
            access_flags: 9,
            name_index: 10,
            descriptor_index: 11,
            attributes: [AttributeInfo {
                name_index: 12,
                length: 44,
                raw: byte_buffer(code_raw[..])
            }]
        }],
        attributes: [AttributeInfo {
            name_index: 13,
            length: 2,
            raw: byte_buffer(source_raw[..])
        }],
    };

    var class = try derive_class(&classfile);
    assert(class.name.bytes()[0] == 77);
    assert(class.descriptor.len() == 6);
    assert(class.descriptor.bytes()[0] == 'L');
    assert(class.super_class.bytes()[0] == 106);
    assert(class.source_file.bytes()[0] == 77);
    assert(class.source_file.bytes().len() == 9);
    assert(class.interfaces.len() == 1);
    assert(class.interfaces[0].bytes()[0] == 82);
    assert(class.fields.len() == 2);
    assert(class.fields[0].is_static());
    assert(class.fields[0].slot == 0);
    assert(!class.fields[1].is_static());
    assert(class.fields[1].slot == 0);
    assert(class.instance_vars == 1);
    assert(class.static_vars.len() == 1);
    switch class.static_vars[0] {
        case .int_value(value) {
            assert(value == 0);
        }
        case .byte_value {
            assert(false);
        }
        case .short_value {
            assert(false);
        }
        case .char_value {
            assert(false);
        }
        case .long_value {
            assert(false);
        }
        case .float_value {
            assert(false);
        }
        case .double_value {
            assert(false);
        }
        case .boolean_value {
            assert(false);
        }
        case .return_address_value {
            assert(false);
        }
        case .ref_value {
            assert(false);
        }
    }
    assert(class.methods.len() == 1);
    assert(class.methods[0].max_stack == 2);
    assert(class.methods[0].max_locals == 1);
    assert(class.methods[0].code_len == 2);
    assert(class.methods[0].code[0] == 4);
    assert(class.methods[0].code[1] == 172);
    assert(class.methods[0].line_number_count == 1);
    assert(class.methods[0].local_var_count == 1);
    assert(class.methods[0].parameter_count == 0);
    assert(class.methods[0].return_descriptor.bytes()[0] == 'I');
    class.clear();
    drop class;
    classfile.clear();
    drop classfile;
}

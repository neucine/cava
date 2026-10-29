import {
    ClassfileError,
    ByteReader,
    ConstantTag,
    parse_constant_tag,
    constant_tag_slot_width,
    fixed_constant_payload_len,
    byte_buffer,
    ConstantMemberRef,
    ConstantNameAndType,
    ConstantMethodHandle,
    ConstantDynamicRef,
    ResolvedNameAndType,
    ResolvedMemberRef,
    ConstantWide,
    Constant,
    read_member_ref,
    read_name_and_type,
    read_dynamic_ref,
    read_wide,
    read_constant,
    read_constant_pool_entry,
    read_constant_pool,
    AttributeInfo,
    MemberInfo,
    new_member_info,
    ClassFile,
    new_classfile,
    read_attribute_info,
    read_attributes,
    read_member_info,
    read_members,
    read_interfaces,
    ClassHeader,
    read_class_header,
    parse_class_header,
    read_classfile,
    parse_classfile,
    sample_header_bytes
} from .classfile;
import { TestError } from std.testing;

test "clone duplicates nested member attribute storage" {
    const original = MemberInfo {
        access_flags: 1,
        name_index: 2,
        descriptor_index: 3,
        attributes: [AttributeInfo {
            name_index: 4,
            length: 2,
            raw: [7, 8]
        }],
    };
    var duplicated = original.clone();
    duplicated.attributes[0].raw[0] = 42;
    assert(original.attributes[0].raw[0] == 7);
    assert(duplicated.attributes[0].raw[0] == 42);
    assert(original.attributes[0].name_index == 4);
}

test "byte reader reads big endian primitives" {
    var data: [:]u8 = [0xCA, 0xFE, 0xBA, 0xBE, 0, 52, 7];

    var reader = ByteReader.init(data[..]);
    assert((reader.read_u1() catch (problem) {
        assert(false);
        return;
    }) == 0xCA);
    assert((reader.read_u2() catch (problem) {
        assert(false);
        return;
    }) == 0xFEBA);
    assert((reader.read_u4() catch (problem) {
        assert(false);
        return;
    }) == 0xBE003407);
    assert(reader.remaining() == 0);
}

test "classfile header parser reads magic version and constant pool count" {
    const data = sample_header_bytes();
    var reader = ByteReader.init(data[..]);
    const header = (read_class_header(&reader) catch (problem) {
        assert(false);
        return;
    });
    assert(header.minor_version == 0);
    assert(header.major_version == 52);
    assert(header.constant_pool_count == 3);
    assert(reader.offset == 10);
}

test "classfile header parser rejects invalid magic" {
    var data = sample_header_bytes();
    data[0] = 0;
    if true {
        const _ = parse_class_header(data[..]) catch (err) {
            assert(err == ClassfileError.invalid_magic);
            return;
        };
        assert(false);
    }
}

test "constant pool tags decode raw JVM tags" {
    assert((parse_constant_tag(1) catch (problem) {
        assert(false);
        return;
    }) == ConstantTag.utf8);
    assert((parse_constant_tag(10) catch (problem) {
        assert(false);
        return;
    }) == ConstantTag.method_ref);
    assert((parse_constant_tag(18) catch (problem) {
        assert(false);
        return;
    }) == ConstantTag.invoke_dynamic);
    assert(constant_tag_slot_width(ConstantTag.long) == 2);
    assert(constant_tag_slot_width(ConstantTag.double) == 2);
    assert(constant_tag_slot_width(ConstantTag.utf8) == 1);

    const field_len = fixed_constant_payload_len(ConstantTag.field_ref);
    if field_len is value {
        assert(value == 4);
    } else {
        assert(false);
    }

    assert(fixed_constant_payload_len(ConstantTag.utf8) == none);
}

test "constant reader parses utf8 class and member refs" {
    var data: [:]u8 = [
        1, 0, 4, 77, 97, 105, 110,
        7, 0, 1,
        12, 0, 1, 0, 1,
        10, 0, 2, 0, 3
    ];

    var reader = ByteReader.init(data[..]);
    var first: Constant = .unusable(0);
    if true {
        read_constant(&reader, &first) catch (err) {
            assert(false);
            return;
        };
    }
    switch first {
        .utf8 => {}
        _ => {
            assert(false);
        }
    }

    var second: Constant = .unusable(0);
    if true {
        read_constant(&reader, &second) catch (err) {
            assert(false);
            return;
        };
    }
    switch second {
        .class_ref(name_index) => {
            assert(name_index == 1);
        }
        _ => {
            assert(false);
        }
    }

    var third: Constant = .unusable(0);
    if true {
        read_constant(&reader, &third) catch (err) {
            assert(false);
            return;
        };
    }
    switch third {
        .name_and_type(pair) => {
            assert(pair.name_index == 1);
            assert(pair.descriptor_index == 1);
        }
        _ => {
            assert(false);
        }
    }

    var fourth: Constant = .unusable(0);
    if true {
        read_constant(&reader, &fourth) catch (err) {
            assert(false);
            return;
        };
    }
    switch fourth {
        .method_ref(member) => {
            assert(member.class_index == 2);
            assert(member.name_and_type_index == 3);
        }
        _ => {
            assert(false);
        }
    }

    assert(reader.remaining() == 0);
}

test "constant pool preserves raw JVM indexes and wide unusable slots" {
    var data: [:]u8 = [
        1, 0, 1, 88,
        5, 0, 0, 0, 0, 0, 0, 0, 42,
        7, 0, 1
    ];

    var reader = ByteReader.init(data[..]);
    var constants: List<Constant> = [];
    if true {
        read_constant_pool(&reader, 5, &constants) catch (err) {
            assert(false);
            return;
        };
    }
    assert(constants.len() == 5);

    switch constants[0] {
        .unusable => {}
        _ => {
            assert(false);
        }
    }

    switch constants[2] {
        .long(value) => {
            assert(value.high_bytes == 0);
            assert(value.low_bytes == 42);
        }
        _ => {
            assert(false);
        }
    }

    switch constants[3] {
        .unusable => {}
        _ => {
            assert(false);
        }
    }

    switch constants[4] {
        .class_ref(name_index) => {
            assert(name_index == 1);
        }
        _ => {
            assert(false);
        }
    }
}

test "classfile parser reads class identity members and raw attributes" {
    var data: [:]u8 = [
        0xCA, 0xFE, 0xBA, 0xBE, // magic
        0, 0, 0, 52, // minor, major
        0, 5, // constant_pool_count
        1, 0, 4, 77, 97, 105, 110, // #1 utf8 Main
        7, 0, 1, // #2 class Main
        1, 0, 4, 67, 111, 100, 101, // #3 utf8 Code
        1, 0, 10, 83, 111, 117, 114, 99, 101, 70, 105, 108, 101, // #4 utf8 SourceFile
        0, 33, // access_flags
        0, 2, // this_class
        0, 0, // super_class
        0, 1, // interfaces_count
        0, 2, // interface[0]
        0, 1, // fields_count
        0, 1, // field access_flags
        0, 1, // field name_index
        0, 1, // field descriptor_index
        0, 1, // field attributes_count
        0, 4, // field attribute name_index
        0, 0, 0, 2, // field attribute length
        0, 1, // field attribute raw
        0, 1, // methods_count
        0, 1, // method access_flags
        0, 1, // method name_index
        0, 1, // method descriptor_index
        0, 1, // method attributes_count
        0, 3, // method attribute name_index
        0, 0, 0, 4, // method attribute length
        0xDE, 0xAD, 0xBE, 0xEF, // method attribute raw
        0, 1, // attributes_count
        0, 4, // class attribute name_index
        0, 0, 0, 2, // class attribute length
        0, 1 // class attribute raw
    ];

    var reader = ByteReader.init(data[..]);
    var classfile = new_classfile();
    if true {
        read_classfile(&reader, &classfile) catch (err) {
            assert(false);
            return;
        };
    }
    assert(classfile.major_version == 52);
    assert(classfile.constant_pool.len() == 5);
    assert(classfile.access_flags == 33);
    assert(classfile.this_class == 2);
    assert(classfile.super_class == 0);
    assert(classfile.interfaces.len() == 1);
    assert(classfile.interfaces[0] == 2);
    assert(classfile.fields.len() == 1);
    assert(classfile.fields[0].access_flags == 1);
    assert(classfile.fields[0].name_index == 1);
    assert(classfile.fields[0].descriptor_index == 1);
    assert(classfile.fields[0].attributes.len() == 1);
    assert(classfile.fields[0].attributes[0].name_index == 4);
    assert(classfile.fields[0].attributes[0].length == 2);
    assert(classfile.fields[0].attributes[0].raw[1] == 1);
    assert(classfile.methods.len() == 1);
    assert(classfile.methods[0].attributes.len() == 1);
    assert(classfile.methods[0].attributes[0].name_index == 3);
    assert(classfile.methods[0].attributes[0].length == 4);
    assert(classfile.methods[0].attributes[0].raw[0] == 0xDE);
    assert(classfile.methods[0].attributes[0].raw[3] == 0xEF);
    assert(classfile.attributes.len() == 1);
    assert(classfile.attributes[0].name_index == 4);
    assert(reader.remaining() == 0);

    drop classfile;
    drop reader;
    drop data;
}

test "classfile resolves constant pool symbolic references" {
    var data: [:]u8 = [
        0xCA, 0xFE, 0xBA, 0xBE, // magic
        0, 0, 0, 52, // minor, major
        0, 7, // constant_pool_count
        1, 0, 4, 77, 97, 105, 110, // #1 utf8 Main
        7, 0, 1, // #2 class Main
        1, 0, 6, 97, 110, 115, 119, 101, 114, // #3 utf8 answer
        1, 0, 1, 73, // #4 utf8 I
        12, 0, 3, 0, 4, // #5 name_and_type answer:I
        9, 0, 2, 0, 5, // #6 field_ref Main.answer:I
        0, 33, // access_flags
        0, 2, // this_class
        0, 0, // super_class
        0, 0, // interfaces_count
        0, 0, // fields_count
        0, 0, // methods_count
        0, 0 // attributes_count
    ];

    var reader = ByteReader.init(data[..]);
    var classfile = new_classfile();
    if true {
        read_classfile(&reader, &classfile) catch (err) {
            assert(false);
            return;
        };
    }
    const class_name = (classfile.class_name(2) catch (problem) {
        assert(false);
        return;
    });
    assert(class_name.bytes().len() == 4);
    assert(class_name.bytes()[0] == 77);
    assert(class_name.bytes()[3] == 110);
    drop class_name;

    const pair = (classfile.name_and_type(5) catch (problem) {
        assert(false);
        return;
    });
    assert(pair.name.bytes().len() == 6);
    assert(pair.name.bytes()[0] == 97);
    assert(pair.name.bytes()[5] == 114);
    assert(pair.descriptor.bytes().len() == 1);
    assert(pair.descriptor.bytes()[0] == 'I');
    drop pair;

    const member = (classfile.member_ref(6) catch (problem) {
        assert(false);
        return;
    });
    assert(member.class_name.bytes()[0] == 77);
    assert(member.name.bytes()[0] == 97);
    assert(member.descriptor.bytes()[0] == 'I');
    drop member;

    const value = classfile.utf8(2) catch (err) {
        assert(err == ClassfileError.invalid_constant_kind);
        drop classfile;
        drop reader;
        drop data;
        return;
    };
    drop value;
    assert(false);

    drop classfile;
    drop reader;
    drop data;
}

test "classfile resolved constants compare with string equality" {
    var data: [:]u8 = [
        0xCA, 0xFE, 0xBA, 0xBE, // magic
        0, 0, 0, 52, // minor, major
        0, 7, // constant_pool_count
        1, 0, 4, 77, 97, 105, 110, // #1 utf8 Main
        7, 0, 1, // #2 class Main
        1, 0, 6, 97, 110, 115, 119, 101, 114, // #3 utf8 answer
        1, 0, 1, 73, // #4 utf8 I
        12, 0, 3, 0, 4, // #5 name_and_type answer:I
        9, 0, 2, 0, 5, // #6 field_ref Main.answer:I
        0, 33, // access_flags
        0, 2, // this_class
        0, 0, // super_class
        0, 0, // interfaces_count
        0, 0, // fields_count
        0, 0, // methods_count
        0, 0 // attributes_count
    ];

    var reader = ByteReader.init(data[..]);
    var classfile = new_classfile();
    if true {
        read_classfile(&reader, &classfile) catch (problem) {
            assert(false);
            return;
        };
    }

    if true {
        const value = classfile.class_name(2) catch (problem) {
            assert(false);
            return;
        };
        assert(value == "Main");
        drop value;
    }
    if true {
        const value = classfile.name_and_type(5) catch (problem) {
            assert(false);
            return;
        };
        assert(value.name == "answer");
        assert(value.descriptor == "I");
        drop value;
    }
    if true {
        const value = classfile.member_ref(6) catch (problem) {
            assert(false);
            return;
        };
        assert(value.class_name == "Main");
        assert(value.name == "answer");
        assert(value.descriptor == "I");
        drop value;
    }
    if true {
        const value = classfile.member_ref(6) catch (problem) {
            assert(false);
            return;
        };
        assert(value.class_name != "Other");
        assert(value.name == "answer");
        assert(value.descriptor == "I");
        drop value;
    }

    drop classfile;
    drop reader;
    drop data;
}

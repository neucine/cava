pub enum ClassfileError: i32 {
    unexpected_eof = 0,
    invalid_magic,
    invalid_constant_tag,
    invalid_constant_index,
    invalid_constant_kind,
}

pub struct ByteReader {
    pub data: [:]u8;
    pub offset: usize;

    pub fn init(data: []const u8): ByteReader {
        return ByteReader {
            data: byte_buffer(data),
            offset: 0,
        };
    }

    pub fn remaining(self: &const ByteReader): usize {
        return self.data.len() - self.offset;
    }

    pub fn can_read(self: &const ByteReader, count: usize): bool {
        return count <= self.remaining();
    }

    pub fn read_u1(self: &ByteReader): u8 ! ClassfileError {
        if !self.can_read(1) {
            throw ClassfileError.unexpected_eof;
        }
        const value = self.data[self.offset];
        self.offset = self.offset + 1;
        return value;
    }

    pub fn read_u2(self: &ByteReader): u16 ! ClassfileError {
        const high = try self.read_u1();
        const low = try self.read_u1();
        return (high as u16) * 256 + (low as u16);
    }

    pub fn read_u4(self: &ByteReader): u32 ! ClassfileError {
        const first = try self.read_u1();
        const second = try self.read_u1();
        const third = try self.read_u1();
        const fourth = try self.read_u1();
        const value =
        (first as u32) * 16777216 +
        (second as u32) * 65536 +
        (third as u32) * 256 +
        (fourth as u32);
        return value;
    }

    pub fn skip(self: &ByteReader, count: usize): void ! ClassfileError {
        if !self.can_read(count) {
            throw ClassfileError.unexpected_eof;
        }
        self.offset = self.offset + count;
        return;
    }

    pub fn read_bytes(self: &ByteReader, count: usize): [:]u8 ! ClassfileError {
        if !self.can_read(count) {
            throw ClassfileError.unexpected_eof;
        }
        const start = self.offset;
        self.offset = self.offset + count;
        return byte_buffer(self.data[start..self.offset]);
    }
}

pub enum ConstantTag: i32 {
    utf8 = 1,
    integer = 3,
    float = 4,
    long = 5,
    double = 6,
    class_ref = 7,
    string_ref = 8,
    field_ref = 9,
    method_ref = 10,
    interface_method_ref = 11,
    name_and_type = 12,
    method_handle = 15,
    method_type = 16,
    dynamic = 17,
    invoke_dynamic = 18,
    module_ref = 19,
    package_ref = 20,
}

pub fn parse_constant_tag(raw: u8): ConstantTag ! ClassfileError {
    return switch raw {
        1 => .utf8;
        3 => .integer;
        4 => .float;
        5 => .long;
        6 => .double;
        7 => .class_ref;
        8 => .string_ref;
        9 => .field_ref;
        10 => .method_ref;
        11 => .interface_method_ref;
        12 => .name_and_type;
        15 => .method_handle;
        16 => .method_type;
        17 => .dynamic;
        18 => .invoke_dynamic;
        19 => .module_ref;
        20 => .package_ref;
        _ => throw ClassfileError.invalid_constant_tag;
    };
}

pub fn constant_tag_slot_width(tag: ConstantTag): u8 {
    return switch tag {
        .long => 2;
        .double => 2;
        _ => 1;
    };
}

pub fn fixed_constant_payload_len(tag: ConstantTag): ?u16 {
    return switch tag {
        .utf8 => none;
        .integer => 4;
        .float => 4;
        .long => 8;
        .double => 8;
        .class_ref => 2;
        .string_ref => 2;
        .field_ref => 4;
        .method_ref => 4;
        .interface_method_ref => 4;
        .name_and_type => 4;
        .method_handle => 3;
        .method_type => 2;
        .dynamic => 4;
        .invoke_dynamic => 4;
        .module_ref => 2;
        .package_ref => 2;
    };
}

fn byte_buffer(source: []const u8): [:]u8 {
    var out = [: source.len()]u8;
    var index: usize = 0;
    while index < source.len() {
        out.push(source[index]);
        index = index + 1;
    }
    return out;
}

pub struct ConstantMemberRef {
    pub class_index: u16;
    pub name_and_type_index: u16;
}

pub struct ConstantNameAndType {
    pub name_index: u16;
    pub descriptor_index: u16;
}

pub struct ConstantMethodHandle {
    pub reference_kind: u8;
    pub reference_index: u16;
}

pub struct ConstantDynamicRef {
    pub bootstrap_method_attr_index: u16;
    pub name_and_type_index: u16;
}

pub struct ResolvedNameAndType {
    pub name: string;
    pub descriptor: string;
}

pub struct ResolvedMemberRef {
    pub class_name: string;
    pub name: string;
    pub descriptor: string;
}

pub struct ConstantWide {
    pub high_bytes: u32;
    pub low_bytes: u32;
}

pub union Constant {
    unusable: u8;
    utf8: string;
    integer: u32;
    float: u32;
    long: ConstantWide;
    double: ConstantWide;
    class_ref: u16;
    string_ref: u16;
    field_ref: ConstantMemberRef;
    method_ref: ConstantMemberRef;
    interface_method_ref: ConstantMemberRef;
    name_and_type: ConstantNameAndType;
    method_handle: ConstantMethodHandle;
    method_type: u16;
    dynamic: ConstantDynamicRef;
    invoke_dynamic: ConstantDynamicRef;
    module_ref: u16;
    package_ref: u16;

}

fn read_member_ref(reader: &ByteReader): ConstantMemberRef ! ClassfileError {
    const class_index = try reader.read_u2();
    const name_and_type_index = try reader.read_u2();
    return ConstantMemberRef {
        class_index: class_index,
        name_and_type_index: name_and_type_index,
    };
}

fn read_name_and_type(reader: &ByteReader): ConstantNameAndType ! ClassfileError {
    const name_index = try reader.read_u2();
    const descriptor_index = try reader.read_u2();
    return ConstantNameAndType {
        name_index: name_index,
        descriptor_index: descriptor_index,
    };
}

fn read_dynamic_ref(reader: &ByteReader): ConstantDynamicRef ! ClassfileError {
    const bootstrap_method_attr_index = try reader.read_u2();
    const name_and_type_index = try reader.read_u2();
    return ConstantDynamicRef {
        bootstrap_method_attr_index: bootstrap_method_attr_index,
        name_and_type_index: name_and_type_index,
    };
}

fn read_wide(reader: &ByteReader): ConstantWide ! ClassfileError {
    const high_bytes = try reader.read_u4();
    const low_bytes = try reader.read_u4();
    return ConstantWide {
        high_bytes: high_bytes,
        low_bytes: low_bytes,
    };
}

fn read_constant_payload(reader: &ByteReader, tag: ConstantTag): Constant ! ClassfileError {
    return switch tag {
        .utf8 => {
            const length = try reader.read_u2();
            const bytes = try reader.read_bytes(length as usize);
            const value = string.from(bytes[..]);
            yield .utf8(value);
        }
        .integer => .integer(try reader.read_u4());
        .float => .float(try reader.read_u4());
        .long => .long(try read_wide(reader));
        .double => .double(try read_wide(reader));
        .class_ref => .class_ref(try reader.read_u2());
        .string_ref => .string_ref(try reader.read_u2());
        .field_ref => .field_ref(try read_member_ref(reader));
        .method_ref => .method_ref(try read_member_ref(reader));
        .interface_method_ref => .interface_method_ref(try read_member_ref(reader));
        .name_and_type => .name_and_type(try read_name_and_type(reader));
        .method_handle => .method_handle(ConstantMethodHandle {
            reference_kind: try reader.read_u1(),
            reference_index: try reader.read_u2(),
        });
        .method_type => .method_type(try reader.read_u2());
        .dynamic => .dynamic(try read_dynamic_ref(reader));
        .invoke_dynamic => .invoke_dynamic(try read_dynamic_ref(reader));
        .module_ref => .module_ref(try reader.read_u2());
        .package_ref => .package_ref(try reader.read_u2());
    };
}

pub fn read_constant(reader: &ByteReader, out: &Constant): void ! ClassfileError {
    const tag = try parse_constant_tag(try reader.read_u1());
    out = try read_constant_payload(reader, tag);
    return;
}

fn read_constant_pool_entry(reader: &ByteReader, constants: &List<Constant>): u16 ! ClassfileError {
    const tag = try parse_constant_tag(try reader.read_u1());
    constants.push(try read_constant_payload(reader, tag));
    return constant_tag_slot_width(tag) as u16;
}

pub fn read_constant_pool(reader: &ByteReader, constant_pool_count: u16, constants: &List<Constant>): void ! ClassfileError {
    constants.push(.unusable(0));

    var index: u16 = 1;
    while index < constant_pool_count {
        const slots = try read_constant_pool_entry(reader, constants);
        if slots == 2 {
            constants.push(.unusable(0));
        }
        index = index + slots;
    }

    return;
}

pub struct AttributeInfo {
    pub name_index: u16;
    pub length: u32;
    pub raw: [:]u8;

    pub fn clone(self: &const AttributeInfo): AttributeInfo {
        return AttributeInfo {
            name_index: self.name_index,
            length: self.length,
            raw: self.raw.clone(),
        };
    }
}

pub struct MemberInfo {
    pub access_flags: u16;
    pub name_index: u16;
    pub descriptor_index: u16;
    pub attributes: List<AttributeInfo>;

    pub fn clear(self: &MemberInfo): void {
        self.attributes.clear();
    }

    pub fn read(self: &MemberInfo, reader: &ByteReader): void ! ClassfileError {
        self.access_flags = try reader.read_u2();
        self.name_index = try reader.read_u2();
        self.descriptor_index = try reader.read_u2();
        const attributes_count = try reader.read_u2();
        var attributes: List<AttributeInfo> = [];
        try read_attributes(reader, attributes_count, &attributes);
        self.attributes = attributes;
        return;
    }

    pub fn clone(self: &const MemberInfo): MemberInfo {
        var attributes: List<AttributeInfo> = [];
        var index: usize = 0;
        while index < self.attributes.len() {
            attributes.push(self.attributes[index].clone());
            index = index + 1;
        }
        return MemberInfo {
            access_flags: self.access_flags,
            name_index: self.name_index,
            descriptor_index: self.descriptor_index,
            attributes: attributes,
        };
    }
}

pub fn new_member_info(): MemberInfo {
    return MemberInfo {
        access_flags: 0,
        name_index: 0,
        descriptor_index: 0,
        attributes: [],
    };
}

pub struct ClassFile {
    pub minor_version: u16;
    pub major_version: u16;
    pub constant_pool: List<Constant>;
    pub access_flags: u16;
    pub this_class: u16;
    pub super_class: u16;
    pub interfaces: List<u16>;
    pub fields: List<MemberInfo>;
    pub methods: List<MemberInfo>;
    pub attributes: List<AttributeInfo>;

    pub fn clear(self: &ClassFile): void {
        self.constant_pool.clear();
        self.interfaces.clear();
        self.fields.clear();
        self.methods.clear();
        self.attributes.clear();
    }

    pub fn read(self: &ClassFile, reader: &ByteReader): void ! ClassfileError {
        const header = try read_class_header(reader);
        var constant_pool: List<Constant> = [];
        try read_constant_pool(reader, header.constant_pool_count, &constant_pool);
        self.access_flags = try reader.read_u2();
        self.this_class = try reader.read_u2();
        self.super_class = try reader.read_u2();
        const interfaces_count = try reader.read_u2();
        var interfaces: List<u16> = [];
        try read_interfaces(reader, interfaces_count, &interfaces);
        const fields_count = try reader.read_u2();
        var fields: List<MemberInfo> = [];
        try read_members(reader, fields_count, &fields);
        const methods_count = try reader.read_u2();
        var methods: List<MemberInfo> = [];
        try read_members(reader, methods_count, &methods);
        const attributes_count = try reader.read_u2();
        var attributes: List<AttributeInfo> = [];
        try read_attributes(reader, attributes_count, &attributes);
        self.minor_version = header.minor_version;
        self.major_version = header.major_version;
        self.constant_pool = constant_pool;
        self.interfaces = interfaces;
        self.fields = fields;
        self.methods = methods;
        self.attributes = attributes;
        return;
    }

    fn valid_constant_index(self: &const ClassFile, index: u16): bool {
        const actual = index as usize;
        return actual != 0 and actual < self.constant_pool.len();
    }

    pub fn utf8(self: &const ClassFile, index: u16): string ! ClassfileError {
        if !self.valid_constant_index(index) {
            throw ClassfileError.invalid_constant_index;
        }

        return switch self.constant_pool[index] {
            .utf8(value) => value;
            _ => throw ClassfileError.invalid_constant_kind;
        };
    }

    pub fn class_name(self: &const ClassFile, index: u16): string ! ClassfileError {
        if !self.valid_constant_index(index) {
            throw ClassfileError.invalid_constant_index;
        }

        return switch self.constant_pool[index] {
            .class_ref(name_index) => try self.utf8(name_index);
            _ => throw ClassfileError.invalid_constant_kind;
        };
    }

    pub fn name_and_type(self: &const ClassFile, index: u16): ResolvedNameAndType ! ClassfileError {
        if !self.valid_constant_index(index) {
            throw ClassfileError.invalid_constant_index;
        }

        return switch self.constant_pool[index] {
            .name_and_type(pair) => ResolvedNameAndType {
                name: try self.utf8(pair.name_index),
                descriptor: try self.utf8(pair.descriptor_index),
            };
            _ => throw ClassfileError.invalid_constant_kind;
        };
    }

    pub fn member_ref(self: &const ClassFile, index: u16): ResolvedMemberRef ! ClassfileError {
        if !self.valid_constant_index(index) {
            throw ClassfileError.invalid_constant_index;
        }

        const raw = switch self.constant_pool[index] {
            .field_ref(member) => member;
            .method_ref(member) => member;
            .interface_method_ref(member) => member;
            _ => throw ClassfileError.invalid_constant_kind;
        };

        if !self.valid_constant_index(raw.name_and_type_index) {
            throw ClassfileError.invalid_constant_index;
        }

        const pair = switch self.constant_pool[raw.name_and_type_index] {
            .name_and_type(actual) => actual;
            _ => throw ClassfileError.invalid_constant_kind;
        };

        const class_name = try self.class_name(raw.class_index);
        const name = try self.utf8(pair.name_index);
        const descriptor = try self.utf8(pair.descriptor_index);
        const out = ResolvedMemberRef {
            class_name: class_name,
            name: name,
            descriptor: descriptor,
        };
        return out;
    }

    pub fn clone_constant_pool(self: &const ClassFile): List<Constant> {
        var out: List<Constant> = [];
        var index: usize = 0;
        while index < self.constant_pool.len() {
            const cloned: Constant = switch self.constant_pool[index] {
                .unusable(value) => .unusable(value);
                .utf8(value) => .utf8(value.clone());
                .integer(value) => .integer(value);
                .float(value) => .float(value);
                .long(value) => .long(value);
                .double(value) => .double(value);
                .class_ref(value) => .class_ref(value);
                .string_ref(value) => .string_ref(value);
                .field_ref(value) => .field_ref(value);
                .method_ref(value) => .method_ref(value);
                .interface_method_ref(value) => .interface_method_ref(value);
                .name_and_type(value) => .name_and_type(value);
                .method_handle(value) => .method_handle(value);
                .method_type(value) => .method_type(value);
                .dynamic(value) => .dynamic(value);
                .invoke_dynamic(value) => .invoke_dynamic(value);
                .module_ref(value) => .module_ref(value);
                .package_ref(value) => .package_ref(value);
            };
            out.push(cloned);
            index = index + 1;
        }
        return out;
    }
}

pub fn new_classfile(): ClassFile {
    return ClassFile {
        minor_version: 0,
        major_version: 0,
        constant_pool: [],
        access_flags: 0,
        this_class: 0,
        super_class: 0,
        interfaces: [],
        fields: [],
        methods: [],
        attributes: [],
    };
}

pub fn read_attribute_info(reader: &ByteReader): AttributeInfo ! ClassfileError {
    const name_index = try reader.read_u2();
    const length = try reader.read_u4();
    return AttributeInfo {
        name_index: name_index,
        length: length,
        raw: try reader.read_bytes(length as usize),
    };
}

pub fn read_attributes(reader: &ByteReader, count: u16, attributes: &List<AttributeInfo>): void ! ClassfileError {
    var index: u16 = 0;
    while index < count {
        attributes.push(try read_attribute_info(reader));
        index = index + 1;
    }
    return;
}

pub fn read_member_info(reader: &ByteReader, out: &MemberInfo): void ! ClassfileError {
    return out.read(reader);
}

pub fn read_members(reader: &ByteReader, count: u16, members: &List<MemberInfo>): void ! ClassfileError {
    var index: u16 = 0;
    while index < count {
        var member = new_member_info();
        try read_member_info(reader, &member);
        members.push(member);
        index = index + 1;
    }
    return;
}

pub fn read_interfaces(reader: &ByteReader, count: u16, interfaces: &List<u16>): void ! ClassfileError {
    var index: u16 = 0;
    while index < count {
        interfaces.push(try reader.read_u2());
        index = index + 1;
    }
    return;
}

pub struct ClassHeader {
    pub minor_version: u16;
    pub major_version: u16;
    pub constant_pool_count: u16;
}

pub fn read_class_header(reader: &ByteReader): ClassHeader ! ClassfileError {
    const magic = try reader.read_u4();
    if magic != 0xCAFEBABE {
        throw ClassfileError.invalid_magic;
    }

    const minor = try reader.read_u2();
    const major = try reader.read_u2();
    const constant_pool_count = try reader.read_u2();
    return ClassHeader {
        minor_version: minor,
        major_version: major,
        constant_pool_count: constant_pool_count,
    };
}

pub fn parse_class_header(data: []const u8): ClassHeader ! ClassfileError {
    var reader = ByteReader.init(data);
    const header = read_class_header(&reader);
    return header;
}

pub fn read_classfile(reader: &ByteReader, out: &ClassFile): void ! ClassfileError {
    return out.read(reader);
}

pub fn parse_classfile(data: []const u8, out: &ClassFile): void ! ClassfileError {
    var reader = ByteReader.init(data);
    const parsed = out.read(&reader);
    return parsed;
}

fn sample_header_bytes(): [:]u8 {
    return [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 52, 0, 3];
}

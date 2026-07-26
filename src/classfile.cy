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

    pub fn remaining(self: &ByteReader): usize {
        return self.data.len() - self.offset;
    }

    pub fn can_read(self: &ByteReader, count: usize): bool {
        return count <= self.remaining();
    }

    pub fn read_u1(self: &ByteReader): result<u8, ClassfileError> {
        if !self.can_read(1) {
            return .err(ClassfileError.unexpected_eof);
        }
        const value = self.data[self.offset];
        self.offset = self.offset + 1;
        return .ok(value);
    }

    pub fn read_u2(self: &ByteReader): result<u16, ClassfileError> {
        const high = try self.read_u1();
        const low = try self.read_u1();
        return .ok((high as u16) * 256 + (low as u16));
    }

    pub fn read_u4(self: &ByteReader): result<u32, ClassfileError> {
        const first = try self.read_u1();
        const second = try self.read_u1();
        const third = try self.read_u1();
        const fourth = try self.read_u1();
        const value =
            (first as u32) * 16777216 +
            (second as u32) * 65536 +
            (third as u32) * 256 +
            (fourth as u32);
        return .ok(value);
    }

    pub fn skip(self: &ByteReader, count: usize): result<void, ClassfileError> {
        if !self.can_read(count) {
            return .err(ClassfileError.unexpected_eof);
        }
        self.offset = self.offset + count;
        return .ok();
    }

    pub fn read_bytes(self: &ByteReader, count: usize): result<[:]u8, ClassfileError> {
        if !self.can_read(count) {
            return .err(ClassfileError.unexpected_eof);
        }
        const start = self.offset;
        self.offset = self.offset + count;
        return .ok(byte_buffer(self.data[start..self.offset]));
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

pub fn parse_constant_tag(raw: u8): result<ConstantTag, ClassfileError> {
    if raw == 1 { return .ok(ConstantTag.utf8); }
    if raw == 3 { return .ok(ConstantTag.integer); }
    if raw == 4 { return .ok(ConstantTag.float); }
    if raw == 5 { return .ok(ConstantTag.long); }
    if raw == 6 { return .ok(ConstantTag.double); }
    if raw == 7 { return .ok(ConstantTag.class_ref); }
    if raw == 8 { return .ok(ConstantTag.string_ref); }
    if raw == 9 { return .ok(ConstantTag.field_ref); }
    if raw == 10 { return .ok(ConstantTag.method_ref); }
    if raw == 11 { return .ok(ConstantTag.interface_method_ref); }
    if raw == 12 { return .ok(ConstantTag.name_and_type); }
    if raw == 15 { return .ok(ConstantTag.method_handle); }
    if raw == 16 { return .ok(ConstantTag.method_type); }
    if raw == 17 { return .ok(ConstantTag.dynamic); }
    if raw == 18 { return .ok(ConstantTag.invoke_dynamic); }
    if raw == 19 { return .ok(ConstantTag.module_ref); }
    if raw == 20 { return .ok(ConstantTag.package_ref); }
    return .err(ClassfileError.invalid_constant_tag);
}

pub fn constant_tag_slot_width(tag: ConstantTag): u8 {
    if tag == ConstantTag.long or tag == ConstantTag.double {
        return 2;
    }
    return 1;
}

pub fn fixed_constant_payload_len(tag: ConstantTag): ?u16 {
    if tag == ConstantTag.integer or tag == ConstantTag.float {
        return 4;
    }
    if tag == ConstantTag.long or tag == ConstantTag.double {
        return 8;
    }
    if tag == ConstantTag.class_ref or tag == ConstantTag.string_ref or tag == ConstantTag.method_type or tag == ConstantTag.module_ref or tag == ConstantTag.package_ref {
        return 2;
    }
    if tag == ConstantTag.field_ref or tag == ConstantTag.method_ref or tag == ConstantTag.interface_method_ref or tag == ConstantTag.name_and_type or tag == ConstantTag.dynamic or tag == ConstantTag.invoke_dynamic {
        return 4;
    }
    if tag == ConstantTag.method_handle {
        return 3;
    }
    return none;
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

fn read_member_ref(reader: &ByteReader): result<ConstantMemberRef, ClassfileError> {
    const class_index = try reader.read_u2();
    const name_and_type_index = try reader.read_u2();
    return .ok(ConstantMemberRef {
        class_index: class_index,
        name_and_type_index: name_and_type_index,
    });
}

fn read_name_and_type(reader: &ByteReader): result<ConstantNameAndType, ClassfileError> {
    const name_index = try reader.read_u2();
    const descriptor_index = try reader.read_u2();
    return .ok(ConstantNameAndType {
        name_index: name_index,
        descriptor_index: descriptor_index,
    });
}

fn read_dynamic_ref(reader: &ByteReader): result<ConstantDynamicRef, ClassfileError> {
    const bootstrap_method_attr_index = try reader.read_u2();
    const name_and_type_index = try reader.read_u2();
    return .ok(ConstantDynamicRef {
        bootstrap_method_attr_index: bootstrap_method_attr_index,
        name_and_type_index: name_and_type_index,
    });
}

fn read_wide(reader: &ByteReader): result<ConstantWide, ClassfileError> {
    const high_bytes = try reader.read_u4();
    const low_bytes = try reader.read_u4();
    return .ok(ConstantWide {
        high_bytes: high_bytes,
        low_bytes: low_bytes,
    });
}

pub fn read_constant(reader: &ByteReader, out: &Constant): result<void, ClassfileError> {
    const tag = try parse_constant_tag(try reader.read_u1());
    if tag == ConstantTag.utf8 {
        const length = try reader.read_u2();
        const bytes = try reader.read_bytes(length as usize);
        const value = string.from(bytes[..]);
        drop bytes;
        out = .utf8(value);
        return .ok();
    }
    if tag == ConstantTag.integer {
        out = .integer(try reader.read_u4());
        return .ok();
    }
    if tag == ConstantTag.float {
        out = .float(try reader.read_u4());
        return .ok();
    }
    if tag == ConstantTag.long {
        out = .long(try read_wide(reader));
        return .ok();
    }
    if tag == ConstantTag.double {
        out = .double(try read_wide(reader));
        return .ok();
    }
    if tag == ConstantTag.class_ref {
        out = .class_ref(try reader.read_u2());
        return .ok();
    }
    if tag == ConstantTag.string_ref {
        out = .string_ref(try reader.read_u2());
        return .ok();
    }
    if tag == ConstantTag.field_ref {
        out = .field_ref(try read_member_ref(reader));
        return .ok();
    }
    if tag == ConstantTag.method_ref {
        out = .method_ref(try read_member_ref(reader));
        return .ok();
    }
    if tag == ConstantTag.interface_method_ref {
        out = .interface_method_ref(try read_member_ref(reader));
        return .ok();
    }
    if tag == ConstantTag.name_and_type {
        out = .name_and_type(try read_name_and_type(reader));
        return .ok();
    }
    if tag == ConstantTag.method_handle {
        const reference_kind = try reader.read_u1();
        const reference_index = try reader.read_u2();
        out = .method_handle(ConstantMethodHandle {
            reference_kind: reference_kind,
            reference_index: reference_index,
        });
        return .ok();
    }
    if tag == ConstantTag.method_type {
        out = .method_type(try reader.read_u2());
        return .ok();
    }
    if tag == ConstantTag.dynamic {
        out = .dynamic(try read_dynamic_ref(reader));
        return .ok();
    }
    if tag == ConstantTag.invoke_dynamic {
        out = .invoke_dynamic(try read_dynamic_ref(reader));
        return .ok();
    }
    if tag == ConstantTag.module_ref {
        out = .module_ref(try reader.read_u2());
        return .ok();
    }
    out = .package_ref(try reader.read_u2());
    return .ok();
}

fn read_constant_pool_entry(reader: &ByteReader, constants: &List<Constant>): result<u16, ClassfileError> {
    const tag = try parse_constant_tag(try reader.read_u1());
    if tag == ConstantTag.utf8 {
        const length = try reader.read_u2();
        const bytes = try reader.read_bytes(length as usize);
        const value = string.from(bytes[..]);
        drop bytes;
        constants.push(.utf8(value));
        return .ok(1);
    }
    if tag == ConstantTag.integer {
        constants.push(.integer(try reader.read_u4()));
        return .ok(1);
    }
    if tag == ConstantTag.float {
        constants.push(.float(try reader.read_u4()));
        return .ok(1);
    }
    if tag == ConstantTag.long {
        constants.push(.long(try read_wide(reader)));
        return .ok(2);
    }
    if tag == ConstantTag.double {
        constants.push(.double(try read_wide(reader)));
        return .ok(2);
    }
    if tag == ConstantTag.class_ref {
        constants.push(.class_ref(try reader.read_u2()));
        return .ok(1);
    }
    if tag == ConstantTag.string_ref {
        constants.push(.string_ref(try reader.read_u2()));
        return .ok(1);
    }
    if tag == ConstantTag.field_ref {
        constants.push(.field_ref(try read_member_ref(reader)));
        return .ok(1);
    }
    if tag == ConstantTag.method_ref {
        constants.push(.method_ref(try read_member_ref(reader)));
        return .ok(1);
    }
    if tag == ConstantTag.interface_method_ref {
        constants.push(.interface_method_ref(try read_member_ref(reader)));
        return .ok(1);
    }
    if tag == ConstantTag.name_and_type {
        constants.push(.name_and_type(try read_name_and_type(reader)));
        return .ok(1);
    }
    if tag == ConstantTag.method_handle {
        const reference_kind = try reader.read_u1();
        const reference_index = try reader.read_u2();
        constants.push(.method_handle(ConstantMethodHandle {
            reference_kind: reference_kind,
            reference_index: reference_index,
        }));
        return .ok(1);
    }
    if tag == ConstantTag.method_type {
        constants.push(.method_type(try reader.read_u2()));
        return .ok(1);
    }
    if tag == ConstantTag.dynamic {
        constants.push(.dynamic(try read_dynamic_ref(reader)));
        return .ok(1);
    }
    if tag == ConstantTag.invoke_dynamic {
        constants.push(.invoke_dynamic(try read_dynamic_ref(reader)));
        return .ok(1);
    }
    if tag == ConstantTag.module_ref {
        constants.push(.module_ref(try reader.read_u2()));
        return .ok(1);
    }
    constants.push(.package_ref(try reader.read_u2()));
    return .ok(1);
}

pub fn read_constant_pool(reader: &ByteReader, constant_pool_count: u16, constants: &List<Constant>): result<void, ClassfileError> {
    constants.push(.unusable(0));

    var index: u16 = 1;
    while index < constant_pool_count {
        const slots = try read_constant_pool_entry(reader, constants);
        if slots == 2 {
            constants.push(.unusable(0));
        }
        index = index + slots;
    }

    return .ok();
}

pub struct AttributeInfo {
    pub name_index: u16;
    pub length: u32;
    pub raw: [:]u8;

    pub fn __copy(self: &AttributeInfo): AttributeInfo {
        return AttributeInfo {
            name_index: self.name_index,
            length: self.length,
            raw: copy self.raw,
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

    pub fn read(self: &MemberInfo, reader: &ByteReader): result<void, ClassfileError> {
        self.access_flags = try reader.read_u2();
        self.name_index = try reader.read_u2();
        self.descriptor_index = try reader.read_u2();
        const attributes_count = try reader.read_u2();
        var attributes: List<AttributeInfo> = [];
        try read_attributes(reader, attributes_count, &attributes);
        self.attributes = attributes;
        return .ok();
    }

    pub fn __copy(self: &MemberInfo): MemberInfo {
        return MemberInfo {
            access_flags: self.access_flags,
            name_index: self.name_index,
            descriptor_index: self.descriptor_index,
            attributes: copy self.attributes,
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

    pub fn read(self: &ClassFile, reader: &ByteReader): result<void, ClassfileError> {
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
        return .ok();
    }

    fn valid_constant_index(self: &ClassFile, index: u16): bool {
        const actual = index as usize;
        return actual != 0 and actual < self.constant_pool.len();
    }

    pub fn utf8(self: &ClassFile, index: u16): result<string, ClassfileError> {
        if !self.valid_constant_index(index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        switch self.constant_pool[index as usize] {
        case .utf8(value) { return .ok(string.from(value.bytes())); }
        else { return .err(ClassfileError.invalid_constant_kind); }
        }
    }

    pub fn class_name(self: &ClassFile, index: u16): result<string, ClassfileError> {
        if !self.valid_constant_index(index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        switch self.constant_pool[index as usize] {
        case .class_ref(name_index) {
            return self.utf8(name_index);
        }
        else { return .err(ClassfileError.invalid_constant_kind); }
        }
    }

    pub fn name_and_type(self: &ClassFile, index: u16): result<ResolvedNameAndType, ClassfileError> {
        if !self.valid_constant_index(index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        switch self.constant_pool[index as usize] {
        case .name_and_type(pair) {
            return .ok(ResolvedNameAndType {
                name: try self.utf8(pair.name_index),
                descriptor: try self.utf8(pair.descriptor_index),
            });
        }
        else { return .err(ClassfileError.invalid_constant_kind); }
        }
    }

    pub fn member_ref(self: &ClassFile, index: u16): result<ResolvedMemberRef, ClassfileError> {
        if !self.valid_constant_index(index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        var raw = ConstantMemberRef {
            class_index: 0,
            name_and_type_index: 0,
        };

        switch self.constant_pool[index as usize] {
        case .field_ref(member) { raw = member; }
        case .method_ref(member) { raw = member; }
        case .interface_method_ref(member) { raw = member; }
        else { return .err(ClassfileError.invalid_constant_kind); }
        }

        if !self.valid_constant_index(raw.name_and_type_index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        var pair = ConstantNameAndType {
            name_index: 0,
            descriptor_index: 0,
        };
        switch self.constant_pool[raw.name_and_type_index as usize] {
        case .name_and_type(actual) { pair = actual; }
        else { return .err(ClassfileError.invalid_constant_kind); }
        }

        const class_name = try self.class_name(raw.class_index);
        const name = try self.utf8(pair.name_index);
        const descriptor = try self.utf8(pair.descriptor_index);
        const out = ResolvedMemberRef {
            class_name: string.from(class_name.bytes()),
            name: string.from(name.bytes()),
            descriptor: string.from(descriptor.bytes()),
        };
        drop descriptor;
        drop name;
        drop class_name;
        return .ok(out);
    }

    pub fn clone_constant_pool(self: &ClassFile): List<Constant> {
        var out: List<Constant> = [];
        var index: usize = 0;
        while index < self.constant_pool.len() {
            switch self.constant_pool[index] {
            case .unusable(value) { out.push(.unusable(value)); }
            case .utf8(value) { out.push(.utf8(value)); }
            case .integer(value) { out.push(.integer(value)); }
            case .float(value) { out.push(.float(value)); }
            case .long(value) { out.push(.long(value)); }
            case .double(value) { out.push(.double(value)); }
            case .class_ref(value) { out.push(.class_ref(value)); }
            case .string_ref(value) { out.push(.string_ref(value)); }
            case .field_ref(value) { out.push(.field_ref(value)); }
            case .method_ref(value) { out.push(.method_ref(value)); }
            case .interface_method_ref(value) { out.push(.interface_method_ref(value)); }
            case .name_and_type(value) { out.push(.name_and_type(value)); }
            case .method_handle(value) { out.push(.method_handle(value)); }
            case .method_type(value) { out.push(.method_type(value)); }
            case .dynamic(value) { out.push(.dynamic(value)); }
            case .invoke_dynamic(value) { out.push(.invoke_dynamic(value)); }
            case .module_ref(value) { out.push(.module_ref(value)); }
            case .package_ref(value) { out.push(.package_ref(value)); }
            }
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

pub fn read_attribute_info(reader: &ByteReader): result<AttributeInfo, ClassfileError> {
    const name_index = try reader.read_u2();
    const length = try reader.read_u4();
    return .ok(AttributeInfo {
        name_index: name_index,
        length: length,
        raw: try reader.read_bytes(length as usize),
    });
}

pub fn read_attributes(reader: &ByteReader, count: u16, attributes: &List<AttributeInfo>): result<void, ClassfileError> {
    var index: u16 = 0;
    while index < count {
        attributes.push(try read_attribute_info(reader));
        index = index + 1;
    }
    return .ok();
}

pub fn read_member_info(reader: &ByteReader, out: &MemberInfo): result<void, ClassfileError> {
    return out.read(reader);
}

pub fn read_members(reader: &ByteReader, count: u16, members: &List<MemberInfo>): result<void, ClassfileError> {
    var index: u16 = 0;
    while index < count {
        var member = new_member_info();
        try read_member_info(reader, &member);
        members.push(member);
        index = index + 1;
    }
    return .ok();
}

pub fn read_interfaces(reader: &ByteReader, count: u16, interfaces: &List<u16>): result<void, ClassfileError> {
    var index: u16 = 0;
    while index < count {
        interfaces.push(try reader.read_u2());
        index = index + 1;
    }
    return .ok();
}

pub struct ClassHeader {
    pub minor_version: u16;
    pub major_version: u16;
    pub constant_pool_count: u16;
}

pub fn read_class_header(reader: &ByteReader): result<ClassHeader, ClassfileError> {
    const magic = try reader.read_u4();
    if magic != 0xCAFEBABE {
        return .err(ClassfileError.invalid_magic);
    }

    const minor = try reader.read_u2();
    const major = try reader.read_u2();
    const constant_pool_count = try reader.read_u2();
    return .ok(ClassHeader {
        minor_version: minor,
        major_version: major,
        constant_pool_count: constant_pool_count,
    });
}

pub fn parse_class_header(data: []const u8): result<ClassHeader, ClassfileError> {
    var reader = ByteReader.init(data);
    const header = read_class_header(&reader);
    drop reader;
    return header;
}

pub fn read_classfile(reader: &ByteReader, out: &ClassFile): result<void, ClassfileError> {
    return out.read(reader);
}

pub fn parse_classfile(data: string, out: &ClassFile): result<void, ClassfileError> {
    var reader = ByteReader.init(data.bytes());
    const parsed = out.read(&reader);
    drop reader;
    return parsed;
}

fn sample_header_bytes(): [:]u8 {
    return [:]u8 [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 52, 0, 3];
}

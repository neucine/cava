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

    fn bytes_equal(left: []const u8, right: []const u8): bool {
        if left.len() != right.len() {
            return false;
        }
        var i: usize = 0;
        while i < left.len() {
            if left[i] != right[i] {
                return false;
            }
            i = i + 1;
        }
        return true;
    }

    pub fn utf8_equals(self: &ClassFile, index: u16, expected: []const u8): result<bool, ClassfileError> {
        if !self.valid_constant_index(index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        switch self.constant_pool[index as usize] {
        case .utf8(value) { return .ok(ClassFile.bytes_equal(value.bytes(), expected)); }
        else { return .err(ClassfileError.invalid_constant_kind); }
        }
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

    pub fn class_name_equals(self: &ClassFile, index: u16, expected: []const u8): result<bool, ClassfileError> {
        if !self.valid_constant_index(index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        switch self.constant_pool[index as usize] {
        case .class_ref(name_index) {
            return self.utf8_equals(name_index, expected);
        }
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

    pub fn name_and_type_equals(self: &ClassFile, index: u16, expected_name: []const u8, expected_descriptor: []const u8): result<bool, ClassfileError> {
        if !self.valid_constant_index(index) {
            return .err(ClassfileError.invalid_constant_index);
        }

        switch self.constant_pool[index as usize] {
        case .name_and_type(pair) {
            const name_matched = try self.utf8_equals(pair.name_index, expected_name);
            if !name_matched {
                return .ok(false);
            }
            return self.utf8_equals(pair.descriptor_index, expected_descriptor);
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

    pub fn member_ref_equals(self: &ClassFile, index: u16, expected_class: []const u8, expected_name: []const u8, expected_descriptor: []const u8): result<bool, ClassfileError> {
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

        switch self.class_name_equals(raw.class_index, expected_class) {
        case .ok(class_matched) {
            if !class_matched {
                return .ok(false);
            }
        }
        case .err(err) { return .err(err); }
        }

        switch self.name_and_type_equals(raw.name_and_type_index, expected_name, expected_descriptor) {
        case .ok(matched) {
            return .ok(matched);
        }
        case .err(err) { return .err(err); }
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
    return read_class_header(&reader);
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

test "byte reader reads big endian primitives" {
    var data: [:]u8 = [0xCA, 0xFE, 0xBA, 0xBE, 0, 52, 7];

    var reader = ByteReader.init(data[..]);
    assert(try reader.read_u1() == 0xCA);
    assert(try reader.read_u2() == 0xFEBA);
    assert(try reader.read_u4() == 0xBE003407);
    assert(reader.remaining() == 0);
}

test "classfile header parser reads magic version and constant pool count" {
    const data = sample_header_bytes();
    var reader = ByteReader.init(data[..]);
    const header = try read_class_header(&reader);
    assert(header.minor_version == 0);
    assert(header.major_version == 52);
    assert(header.constant_pool_count == 3);
    assert(reader.offset == 10);
}

test "classfile header parser rejects invalid magic" {
    var data = sample_header_bytes();
    data[0] = 0;
    switch parse_class_header(data[..]) {
    case .ok(header) {
        assert(false);
    }
    case .err(err) {
        assert(err == ClassfileError.invalid_magic);
    }
    }
}

test "constant pool tags decode raw JVM tags" {
    assert(try parse_constant_tag(1) == ConstantTag.utf8);
    assert(try parse_constant_tag(10) == ConstantTag.method_ref);
    assert(try parse_constant_tag(18) == ConstantTag.invoke_dynamic);
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
    switch read_constant(&reader, &first) {
    case .ok {}
    case .err(err) { assert(false); }
    }
    switch first {
    case .utf8 {}
    else { assert(false); }
    }

    var second: Constant = .unusable(0);
    switch read_constant(&reader, &second) {
    case .ok {}
    case .err(err) { assert(false); }
    }
    switch second {
    case .class_ref(name_index) {
        assert(name_index == 1);
    }
    else { assert(false); }
    }

    var third: Constant = .unusable(0);
    switch read_constant(&reader, &third) {
    case .ok {}
    case .err(err) { assert(false); }
    }
    switch third {
    case .name_and_type(pair) {
        assert(pair.name_index == 1);
        assert(pair.descriptor_index == 1);
    }
    else { assert(false); }
    }

    var fourth: Constant = .unusable(0);
    switch read_constant(&reader, &fourth) {
    case .ok {}
    case .err(err) { assert(false); }
    }
    switch fourth {
    case .method_ref(member) {
        assert(member.class_index == 2);
        assert(member.name_and_type_index == 3);
    }
    else { assert(false); }
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
    switch read_constant_pool(&reader, 5, &constants) {
    case .ok {}
    case .err(err) {
        assert(false);
    }
    }
    assert(constants.len() == 5);

    switch constants[0] {
    case .unusable {}
    else { assert(false); }
    }

    switch constants[2] {
    case .long(value) {
        assert(value.high_bytes == 0);
        assert(value.low_bytes == 42);
    }
    else { assert(false); }
    }

    switch constants[3] {
    case .unusable {}
    else { assert(false); }
    }

    switch constants[4] {
    case .class_ref(name_index) {
        assert(name_index == 1);
    }
    else { assert(false); }
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
    switch read_classfile(&reader, &classfile) {
    case .ok {}
    case .err(err) {
        assert(false);
    }
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
    switch read_classfile(&reader, &classfile) {
    case .ok {}
    case .err(err) {
        assert(false);
    }
    }
    const class_name = try classfile.class_name(2);
    assert(class_name.bytes().len() == 4);
    assert(class_name.bytes()[0] == 77);
    assert(class_name.bytes()[3] == 110);
    drop class_name;

    const pair = try classfile.name_and_type(5);
    assert(pair.name.bytes().len() == 6);
    assert(pair.name.bytes()[0] == 97);
    assert(pair.name.bytes()[5] == 114);
    assert(pair.descriptor.bytes().len() == 1);
    assert(pair.descriptor.bytes()[0] == 73);
    drop pair;

    const member = try classfile.member_ref(6);
    assert(member.class_name.bytes()[0] == 77);
    assert(member.name.bytes()[0] == 97);
    assert(member.descriptor.bytes()[0] == 73);
    drop member;

    switch classfile.utf8_equals(2, "Main".bytes()) {
    case .ok(value) {
        assert(false);
    }
    case .err(err) {
        assert(err == ClassfileError.invalid_constant_kind);
    }
    }

    drop classfile;
    drop reader;
    drop data;
}

test "classfile symbolic equality helpers compare resolved constants" {
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
    switch read_classfile(&reader, &classfile) {
    case .ok {}
    case .err(err) {
        const ignored = err;
        assert(false);
    }
    }

    switch classfile.class_name_equals(2, "Main".bytes()) {
    case .ok(value) { assert(value); }
    case .err(err) {
        const ignored = err;
        assert(false);
    }
    }
    switch classfile.name_and_type_equals(5, "answer".bytes(), "I".bytes()) {
    case .ok(value) { assert(value); }
    case .err(err) {
        const ignored = err;
        assert(false);
    }
    }
    switch classfile.member_ref_equals(6, "Main".bytes(), "answer".bytes(), "I".bytes()) {
    case .ok(value) { assert(value); }
    case .err(err) {
        const ignored = err;
        assert(false);
    }
    }
    switch classfile.member_ref_equals(6, "Other".bytes(), "answer".bytes(), "I".bytes()) {
    case .ok(value) { assert(!value); }
    case .err(err) {
        const ignored = err;
        assert(false);
    }
    }

    drop classfile;
    drop reader;
    drop data;
}

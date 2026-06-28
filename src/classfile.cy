pub enum ClassfileError: i32 {
    unexpected_eof = 0,
    invalid_magic,
    invalid_constant_tag,
}

pub struct ByteReader {
    pub data: []const u8;
    pub offset: usize;

    pub fn init(data: []const u8): ByteReader {
        return ByteReader {
            data: data,
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

    pub fn read_slice(self: &ByteReader, count: usize): result<[]const u8, ClassfileError> {
        if !self.can_read(count) {
            return .err(ClassfileError.unexpected_eof);
        }
        const start = self.offset;
        self.offset = self.offset + count;
        return .ok(self.data[start..self.offset]);
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

pub struct ConstantWide {
    pub high_bytes: u32;
    pub low_bytes: u32;
}

pub union Constant {
    unusable: u8;
    utf8: []const u8;
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

pub fn read_constant(reader: &ByteReader): result<Constant, ClassfileError> {
    const tag = try parse_constant_tag(try reader.read_u1());
    if tag == ConstantTag.utf8 {
        const length = try reader.read_u2();
        return .ok(.utf8(try reader.read_slice(length as usize)));
    }
    if tag == ConstantTag.integer {
        return .ok(.integer(try reader.read_u4()));
    }
    if tag == ConstantTag.float {
        return .ok(.float(try reader.read_u4()));
    }
    if tag == ConstantTag.long {
        return .ok(.long(try read_wide(reader)));
    }
    if tag == ConstantTag.double {
        return .ok(.double(try read_wide(reader)));
    }
    if tag == ConstantTag.class_ref {
        return .ok(.class_ref(try reader.read_u2()));
    }
    if tag == ConstantTag.string_ref {
        return .ok(.string_ref(try reader.read_u2()));
    }
    if tag == ConstantTag.field_ref {
        return .ok(.field_ref(try read_member_ref(reader)));
    }
    if tag == ConstantTag.method_ref {
        return .ok(.method_ref(try read_member_ref(reader)));
    }
    if tag == ConstantTag.interface_method_ref {
        return .ok(.interface_method_ref(try read_member_ref(reader)));
    }
    if tag == ConstantTag.name_and_type {
        return .ok(.name_and_type(try read_name_and_type(reader)));
    }
    if tag == ConstantTag.method_handle {
        const reference_kind = try reader.read_u1();
        const reference_index = try reader.read_u2();
        return .ok(.method_handle(ConstantMethodHandle {
            reference_kind: reference_kind,
            reference_index: reference_index,
        }));
    }
    if tag == ConstantTag.method_type {
        return .ok(.method_type(try reader.read_u2()));
    }
    if tag == ConstantTag.dynamic {
        return .ok(.dynamic(try read_dynamic_ref(reader)));
    }
    if tag == ConstantTag.invoke_dynamic {
        return .ok(.invoke_dynamic(try read_dynamic_ref(reader)));
    }
    if tag == ConstantTag.module_ref {
        return .ok(.module_ref(try reader.read_u2()));
    }
    return .ok(.package_ref(try reader.read_u2()));
}

pub fn read_constant_pool(reader: &ByteReader, constant_pool_count: u16): result<List<Constant>, ClassfileError> {
    var constants: List<Constant> = [];
    constants.push(.unusable(0));

    var index: u16 = 1;
    while index < constant_pool_count {
        const constant = try read_constant(reader);
        constants.push(constant);

        switch constant {
        case .long(value) {
            const ignored = value;
            constants.push(.unusable(0));
            index = index + 2;
        }
        case .double(value) {
            const ignored = value;
            constants.push(.unusable(0));
            index = index + 2;
        }
        case .unusable(value) { const ignored = value; index = index + 1; }
        case .utf8(value) { const ignored = value; index = index + 1; }
        case .integer(value) { const ignored = value; index = index + 1; }
        case .float(value) { const ignored = value; index = index + 1; }
        case .class_ref(value) { const ignored = value; index = index + 1; }
        case .string_ref(value) { const ignored = value; index = index + 1; }
        case .field_ref(value) { const ignored = value; index = index + 1; }
        case .method_ref(value) { const ignored = value; index = index + 1; }
        case .interface_method_ref(value) { const ignored = value; index = index + 1; }
        case .name_and_type(value) { const ignored = value; index = index + 1; }
        case .method_handle(value) { const ignored = value; index = index + 1; }
        case .method_type(value) { const ignored = value; index = index + 1; }
        case .dynamic(value) { const ignored = value; index = index + 1; }
        case .invoke_dynamic(value) { const ignored = value; index = index + 1; }
        case .module_ref(value) { const ignored = value; index = index + 1; }
        case .package_ref(value) { const ignored = value; index = index + 1; }
        }
    }

    return .ok(constants);
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

fn sample_header_bytes(): [:]u8 {
    var data = [: 10]u8;
    data.push(0xCA);
    data.push(0xFE);
    data.push(0xBA);
    data.push(0xBE);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(52);
    data.push(0);
    data.push(3);
    return data;
}

test "byte reader reads big endian primitives" {
    var data = [: 7]u8;
    data.push(0xCA);
    data.push(0xFE);
    data.push(0xBA);
    data.push(0xBE);
    data.push(0);
    data.push(52);
    data.push(7);

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
        const ignored = header;
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
    var data = [: 19]u8;
    data.push(1);
    data.push(0);
    data.push(4);
    data.push(77);
    data.push(97);
    data.push(105);
    data.push(110);
    data.push(7);
    data.push(0);
    data.push(1);
    data.push(12);
    data.push(0);
    data.push(1);
    data.push(0);
    data.push(1);
    data.push(10);
    data.push(0);
    data.push(2);
    data.push(0);
    data.push(3);

    var reader = ByteReader.init(data[..]);
    const first = try read_constant(&reader);
    switch first {
    case .utf8(bytes) {
        assert(bytes.len() == 4);
        assert(bytes[0] == 77);
        assert(bytes[3] == 110);
    }
    case .unusable(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .long(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .class_ref(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .method_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .name_and_type(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    const second = try read_constant(&reader);
    switch second {
    case .class_ref(name_index) {
        assert(name_index == 1);
    }
    case .unusable(value) { const ignored = value; assert(false); }
    case .utf8(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .long(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .method_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .name_and_type(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    const third = try read_constant(&reader);
    switch third {
    case .name_and_type(pair) {
        assert(pair.name_index == 1);
        assert(pair.descriptor_index == 1);
    }
    case .unusable(value) { const ignored = value; assert(false); }
    case .utf8(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .long(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .class_ref(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .method_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    const fourth = try read_constant(&reader);
    switch fourth {
    case .method_ref(member) {
        assert(member.class_index == 2);
        assert(member.name_and_type_index == 3);
    }
    case .unusable(value) { const ignored = value; assert(false); }
    case .utf8(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .long(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .class_ref(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .name_and_type(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    assert(reader.remaining() == 0);
}

test "constant pool preserves raw JVM indexes and wide unusable slots" {
    var data = [: 16]u8;
    data.push(1);
    data.push(0);
    data.push(1);
    data.push(88);
    data.push(5);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(42);
    data.push(7);
    data.push(0);
    data.push(1);

    var reader = ByteReader.init(data[..]);
    var constants: List<Constant> = [];
    switch read_constant_pool(&reader, 5) {
    case .ok(value) {
        constants = value;
    }
    case .err(err) {
        const ignored = err;
        assert(false);
    }
    }
    assert(constants.len() == 5);

    switch constants[0] {
    case .unusable(value) { const ignored = value; }
    case .utf8(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .long(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .class_ref(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .method_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .name_and_type(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    switch constants[2] {
    case .long(value) {
        assert(value.high_bytes == 0);
        assert(value.low_bytes == 42);
    }
    case .unusable(value) { const ignored = value; assert(false); }
    case .utf8(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .class_ref(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .method_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .name_and_type(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    switch constants[3] {
    case .unusable(value) { const ignored = value; }
    case .utf8(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .long(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .class_ref(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .method_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .name_and_type(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    switch constants[4] {
    case .class_ref(name_index) {
        assert(name_index == 1);
    }
    case .unusable(value) { const ignored = value; assert(false); }
    case .utf8(value) { const ignored = value; assert(false); }
    case .integer(value) { const ignored = value; assert(false); }
    case .float(value) { const ignored = value; assert(false); }
    case .long(value) { const ignored = value; assert(false); }
    case .double(value) { const ignored = value; assert(false); }
    case .string_ref(value) { const ignored = value; assert(false); }
    case .field_ref(value) { const ignored = value; assert(false); }
    case .method_ref(value) { const ignored = value; assert(false); }
    case .interface_method_ref(value) { const ignored = value; assert(false); }
    case .name_and_type(value) { const ignored = value; assert(false); }
    case .method_handle(value) { const ignored = value; assert(false); }
    case .method_type(value) { const ignored = value; assert(false); }
    case .dynamic(value) { const ignored = value; assert(false); }
    case .invoke_dynamic(value) { const ignored = value; assert(false); }
    case .module_ref(value) { const ignored = value; assert(false); }
    case .package_ref(value) { const ignored = value; assert(false); }
    }

    drop constants;
}

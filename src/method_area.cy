import { AttributeInfo, ByteReader, ClassFile, ClassfileError, Constant, ConstantMemberRef, ConstantNameAndType, MemberInfo, parse_classfile } from .classfile;
import { Class, Field, Method, Name, Value, class_access_flags, default_value, field_access_flags, method_access_flags, null_ref } from .types;
import { FsError, read_file } from std.fs;

pub enum MethodAreaError: i32 {
    classfile = 0,
    not_found,
    permission_denied,
    already_exists,
    invalid_path,
    io_error,
}

fn method_area_error_from_fs(err: FsError): MethodAreaError {
    if err == FsError.not_found {
        return MethodAreaError.not_found;
    }
    if err == FsError.permission_denied {
        return MethodAreaError.permission_denied;
    }
    if err == FsError.already_exists {
        return MethodAreaError.already_exists;
    }
    if err == FsError.invalid_path {
        return MethodAreaError.invalid_path;
    }
    return MethodAreaError.io_error;
}

pub struct SymbolPool {
    pub symbols: List<Name>;

    fn bytes_equal(left: []const u8, right: []const u8): bool {
        if left.len() != right.len() {
            return false;
        }
        var index: usize = 0;
        while index < left.len() {
            if left[index] != right[index] {
                return false;
            }
            index = index + 1;
        }
        return true;
    }

    pub fn contains(self: &SymbolPool, value: []const u8): bool {
        var index: usize = 0;
        while index < self.symbols.len() {
            const symbol = self.symbols[index];
            if SymbolPool.bytes_equal(symbol.value, value) {
                return true;
            }
            index = index + 1;
        }
        return false;
    }

    pub fn add(self: &SymbolPool, value: []const u8): void {
        if self.contains(value) {
            return;
        }
        self.symbols.push(Name { value: value });
    }
}

pub fn new_symbol_pool(): SymbolPool {
    return SymbolPool {
        symbols: [],
    };
}

pub struct MethodArea {
    pub classes: List<Class>;
    pub symbols: SymbolPool;
    pub class_sources: List<string>;

    pub fn find_class_index(self: &MethodArea, name: []const u8): ?usize {
        var index: usize = 0;
        while index < self.classes.len() {
            const class_name = self.classes[index].name.bytes();
            if bytes_equal(class_name, name) {
                return index;
            }
            index = index + 1;
        }
        return none;
    }

    pub fn has_class(self: &MethodArea, name: []const u8): bool {
        return self.find_class_index(name) != none;
    }

    pub fn field_index(self: &MethodArea, class_index: usize, name: []const u8, descriptor: []const u8): ?i32 {
        if class_index >= self.classes.len() {
            return none;
        }

        var index: usize = 0;
        while index < self.classes[class_index].fields.len() {
            const field = self.classes[class_index].fields[index];
            if bytes_equal(field.name, name) and bytes_equal(field.descriptor, descriptor) {
                return index as i32;
            }
            index = index + 1;
        }
        return none;
    }

    pub fn method_index(self: &MethodArea, class_index: usize, name: []const u8, descriptor: []const u8): ?i32 {
        if class_index >= self.classes.len() {
            return none;
        }

        var index: usize = 0;
        while index < self.classes[class_index].methods.len() {
            const method = self.classes[class_index].methods[index];
            if bytes_equal(method.name, name) and bytes_equal(method.descriptor, descriptor) {
                return index as i32;
            }
            index = index + 1;
        }
        return none;
    }

    pub fn resolve_class_ref(self: &MethodArea, classfile: &ClassFile, constant_index: u16): result<usize, ClassfileError> {
        const name = try classfile.class_name(constant_index);
        if name.len() > 0 and name[0] == 91 {
            return .ok(self.define_array_class(name));
        }
        if self.find_class_index(name) is existing {
            return .ok(existing);
        }
        return .err(ClassfileError.invalid_constant_index);
    }

    pub fn resolve_field_ref(self: &MethodArea, classfile: &ClassFile, constant_index: u16): result<ResolvedFieldRef, ClassfileError> {
        const member = try classfile.member_ref(constant_index);
        if self.find_class_index(member.class_name) is class_index {
            if self.field_index(class_index, member.name, member.descriptor) is field_index {
                return .ok(ResolvedFieldRef {
                    class_index: class_index,
                    field_index: field_index,
                });
            }
        }
        return .err(ClassfileError.invalid_constant_index);
    }

    pub fn resolve_method_ref(self: &MethodArea, classfile: &ClassFile, constant_index: u16): result<ResolvedMethodRef, ClassfileError> {
        const member = try classfile.member_ref(constant_index);
        if self.find_class_index(member.class_name) is class_index {
            if self.method_index(class_index, member.name, member.descriptor) is method_index_value {
                return .ok(ResolvedMethodRef {
                    class_index: class_index,
                    method_index: method_index_value,
                });
            }
        }
        return .err(ClassfileError.invalid_constant_index);
    }

    pub fn define_array_class(self: &MethodArea, name: []const u8): usize {
        if self.find_class_index(name) is existing {
            return existing;
        }

        self.symbols.add(name);
        self.classes.push(derive_array_class(name));
        return self.classes.len() - 1;
    }

    pub fn define_class(self: &MethodArea, classfile: &ClassFile): result<usize, ClassfileError> {
        const name = try classfile.class_name(classfile.this_class);
        if self.find_class_index(name) is existing {
            return .ok(existing);
        }

        self.symbols.add(name);
        self.classes.push(try derive_class(classfile));
        return .ok(self.classes.len() - 1);
    }

    pub fn load_class_from_bytes(self: &MethodArea, data: []const u8): result<usize, ClassfileError> {
        var classfile = try parse_classfile(data);
        return self.define_class(&classfile);
    }

    pub fn load_class_from_source(self: &MethodArea, source: string): result<usize, ClassfileError> {
        var classfile = try parse_classfile(source.bytes());
        const name = try classfile.class_name(classfile.this_class);
        if self.find_class_index(name) is existing {
            return .ok(existing);
        }

        self.symbols.add(name);
        self.classes.push(try derive_class(&classfile));
        self.class_sources.push(source);
        return .ok(self.classes.len() - 1);
    }

    pub fn load_class_from_path(self: &MethodArea, root: string, class_name: []const u8): result<usize, MethodAreaError> {
        if self.find_class_index(class_name) is existing {
            return .ok(existing);
        }

        var path = class_file_path(root, class_name);
        const read_result = read_file(path);
        drop path;

        switch read_result {
        case .ok(source) {
            const loaded = self.load_class_from_source(source);
            switch loaded {
            case .ok(index) { return .ok(index); }
            case .err(err) {
                const ignored = err;
                return .err(MethodAreaError.classfile);
            }
            }
        }
        case .err(err) {
            return .err(method_area_error_from_fs(err));
        }
        }
    }
}

pub fn new_method_area(): MethodArea {
    return MethodArea {
        classes: [],
        symbols: new_symbol_pool(),
        class_sources: [],
    };
}

pub fn class_file_path(root: string, class_name: []const u8): string {
    const root_bytes = root.bytes();
    var separator_len: usize = 1;
    if root_bytes.len() == 0 or root_bytes[root_bytes.len() - 1] == 47 {
        separator_len = 0;
    }

    var bytes = [: root_bytes.len() + separator_len + class_name.len() + 6]u8;
    var index: usize = 0;
    while index < root_bytes.len() {
        bytes.push(root_bytes[index]);
        index = index + 1;
    }
    if separator_len == 1 {
        bytes.push(47);
    }
    index = 0;
    while index < class_name.len() {
        bytes.push(class_name[index]);
        index = index + 1;
    }
    bytes.push(46);
    bytes.push(99);
    bytes.push(108);
    bytes.push(97);
    bytes.push(115);
    bytes.push(115);
    const out = string.from(bytes[..]);
    drop bytes;
    return out;
}

pub struct ResolvedFieldRef {
    pub class_index: usize;
    pub field_index: i32;
}

pub struct ResolvedMethodRef {
    pub class_index: usize;
    pub method_index: i32;
}

fn bytes_equal(left: []const u8, right: []const u8): bool {
    if left.len() != right.len() {
        return false;
    }
    var index: usize = 0;
    while index < left.len() {
        if left[index] != right[index] {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn first_type(descriptor: []const u8): []const u8 {
    if descriptor.len() == 0 {
        return descriptor;
    }

    const tag = descriptor[0];
    if tag == 66 or tag == 67 or tag == 68 or tag == 70 or tag == 73 or tag == 74 or tag == 83 or tag == 90 or tag == 86 {
        return descriptor[0..1];
    }
    if tag == 76 {
        var index: usize = 1;
        while index < descriptor.len() {
            if descriptor[index] == 59 {
                return descriptor[0..index + 1];
            }
            index = index + 1;
        }
        return descriptor[0..0];
    }
    if tag == 91 {
        const component = first_type(descriptor[1..descriptor.len()]);
        if component.len() == 0 {
            return component;
        }
        return descriptor[0..component.len() + 1];
    }
    return descriptor[0..0];
}

pub fn method_parameter_count(descriptor: []const u8): usize {
    if descriptor.len() == 0 or descriptor[0] != 40 {
        return 0;
    }

    var index: usize = 1;
    var count: usize = 0;
    while index < descriptor.len() and descriptor[index] != 41 {
        const param = first_type(descriptor[index..descriptor.len()]);
        if param.len() == 0 {
            return count;
        }
        count = count + 1;
        index = index + param.len();
    }
    return count;
}

pub fn method_return_descriptor(descriptor: []const u8): []const u8 {
    var index: usize = 0;
    while index < descriptor.len() {
        if descriptor[index] == 41 {
            return descriptor[index + 1..descriptor.len()];
        }
        index = index + 1;
    }
    return descriptor[0..0];
}

pub fn array_component_type(name: []const u8): []const u8 {
    if name.len() == 0 or name[0] != 91 {
        return name[0..0];
    }
    return name[1..name.len()];
}

pub fn array_element_type(name: []const u8): []const u8 {
    if name.len() == 0 or name[0] != 91 {
        return name[0..0];
    }
    var index: usize = 0;
    while index < name.len() {
        if name[index] != 91 {
            return name[index..name.len()];
        }
        index = index + 1;
    }
    return name[0..0];
}

pub fn array_dimensions(name: []const u8): u32 {
    var dimensions: u32 = 1;
    var index: usize = 1;
    if name.len() == 0 or name[0] != 91 {
        return 0;
    }
    while index < name.len() {
        if name[index] == 91 {
            dimensions = dimensions + 1;
        }
        index = index + 1;
    }
    return dimensions;
}

fn class_descriptor_from_name(name: []const u8): string {
    var bytes = [: name.len() + 2]u8;
    bytes.push(76);
    var index: usize = 0;
    while index < name.len() {
        bytes.push(name[index]);
        index = index + 1;
    }
    bytes.push(59);
    return string.from(bytes[..]);
}

pub fn derive_array_class(name: []const u8): Class {
    var fields: List<Field> = [];
    var methods: List<Method> = [];
    var static_vars: List<Value> = [];
    return Class {
        name: string.from(name),
        descriptor: string.from(name),
        access_flags: class_access_flags(0x0001),
        super_class: "java/lang/Object".bytes(),
        interfaces: [Name { value: "java/io/Serializable".bytes() }, Name { value: "java/lang/Cloneable".bytes() }],
        fields: fields,
        methods: methods,
        instance_vars: 0,
        static_vars: static_vars,
        source_file: "".bytes(),
        is_array: true,
        component_type: array_component_type(name),
        element_type: array_element_type(name),
        dimensions: array_dimensions(name),
        defined: true,
        linked: false,
        class_object: null_ref,
    };
}

struct CodeInfo {
    code: []const u8;
    max_stack: u16;
    max_locals: u16;
    code_len: u32;
    exception_count: u32;
    local_var_count: u32;
    line_number_count: u32;
}

fn empty_code_info(): CodeInfo {
    return CodeInfo {
        code: "".bytes(),
        max_stack: 0,
        max_locals: 0,
        code_len: 0,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
    };
}

fn apply_code_attribute_info(classfile: &ClassFile, name_index: u16, raw: []const u8, info: &CodeInfo): result<void, ClassfileError> {
    const name = try classfile.utf8(name_index);
    var reader = ByteReader.init(raw);
    if bytes_equal(name, "LineNumberTable".bytes()) {
        const count = try reader.read_u2();
        info.line_number_count = info.line_number_count + (count as u32);
        try reader.skip((count as usize) * 4);
        return .ok();
    }
    if bytes_equal(name, "LocalVariableTable".bytes()) {
        const count = try reader.read_u2();
        info.local_var_count = info.local_var_count + (count as u32);
        try reader.skip((count as usize) * 10);
        return .ok();
    }
    return .ok();
}

fn code_info_from_attribute(classfile: &ClassFile, name_index: u16, raw: []const u8): result<CodeInfo, ClassfileError> {
    const name = try classfile.utf8(name_index);
    if !bytes_equal(name, "Code".bytes()) {
        return .ok(empty_code_info());
    }

    var reader = ByteReader.init(raw);
    const max_stack = try reader.read_u2();
    const max_locals = try reader.read_u2();
    const code_len = try reader.read_u4();
    const code_start = reader.offset;
    const code = raw[code_start..code_start + (code_len as usize)];
    try reader.skip(code_len as usize);
    const exception_count = try reader.read_u2();
    try reader.skip((exception_count as usize) * 8);
    var out = CodeInfo {
        code: code,
        max_stack: max_stack,
        max_locals: max_locals,
        code_len: code_len,
        exception_count: exception_count as u32,
        local_var_count: 0,
        line_number_count: 0,
    };
    const attributes_count = try reader.read_u2();
    var index: usize = 0;
    while index < attributes_count as usize {
        const nested_name_index = try reader.read_u2();
        const nested_length = try reader.read_u4();
        const nested_raw = try reader.read_slice(nested_length as usize);
        try apply_code_attribute_info(classfile, nested_name_index, nested_raw, &out);
        index = index + 1;
    }
    return .ok(out);
}

fn member_code_info(classfile: &ClassFile, attributes: []AttributeInfo): result<CodeInfo, ClassfileError> {
    var out = empty_code_info();
    var index: usize = 0;
    while index < attributes.len() {
        const current = try code_info_from_attribute(classfile, attributes[index].name_index, attributes[index].raw);
        if current.code_len != 0 or current.max_stack != 0 or current.max_locals != 0 {
            out = current;
        }
        index = index + 1;
    }
    return .ok(out);
}

fn derive_interfaces(classfile: &ClassFile): result<List<Name>, ClassfileError> {
    var interfaces: List<Name> = [];
    const raw_interfaces = classfile.interfaces[..];
    var index: usize = 0;
    while index < raw_interfaces.len() {
        interfaces.push(Name { value: try classfile.class_name(raw_interfaces[index]) });
        index = index + 1;
    }
    return .ok(interfaces);
}

fn derive_fields(classfile: &ClassFile, class_name: []const u8): result<List<Field>, ClassfileError> {
    var fields: List<Field> = [];
    var static_slot: u16 = 0;
    var instance_slot: u16 = 0;
    const field_infos = classfile.fields[..];
    var index: usize = 0;
    while index < field_infos.len() {
        const descriptor = try classfile.utf8(field_infos[index].descriptor_index);
        const access_flags = field_infos[index].access_flags;
        const is_static = (access_flags & 8) != 0;
        var slot: u16 = instance_slot;
        if is_static {
            slot = static_slot;
            static_slot = static_slot + 1;
        } else {
            instance_slot = instance_slot + 1;
        }
        fields.push(Field {
            class_name: class_name,
            access_flags: field_access_flags(access_flags),
            name: try classfile.utf8(field_infos[index].name_index),
            descriptor: descriptor,
            index: index as u16,
            slot: slot,
        });
        index = index + 1;
    }
    return .ok(fields);
}

fn derive_static_vars(fields: &List<Field>): List<Value> {
    var values: List<Value> = [];
    var index: usize = 0;
    while index < fields.len() {
        const field = fields[index];
        if field.is_static() {
            values.push(default_value(field.descriptor));
        }
        index = index + 1;
    }
    return values;
}

fn instance_var_count(fields: &List<Field>): u16 {
    var count: u16 = 0;
    var index: usize = 0;
    while index < fields.len() {
        const field = fields[index];
        if !field.is_static() {
            count = count + 1;
        }
        index = index + 1;
    }
    return count;
}

fn derive_source_file(classfile: &ClassFile): result<[]const u8, ClassfileError> {
    const attributes = classfile.attributes[..];
    var index: usize = 0;
    while index < attributes.len() {
        const attribute = attributes[index];
        const name = try classfile.utf8(attribute.name_index);
        if bytes_equal(name, "SourceFile".bytes()) {
            var reader = ByteReader.init(attribute.raw);
            const source_file_index = try reader.read_u2();
            return .ok(try classfile.utf8(source_file_index));
        }
        index = index + 1;
    }
    return .ok("".bytes());
}

fn derive_methods(classfile: &ClassFile, class_name: []const u8): result<List<Method>, ClassfileError> {
    var methods: List<Method> = [];
    const method_infos = classfile.methods[..];
    var index: usize = 0;
    while index < method_infos.len() {
        const descriptor = try classfile.utf8(method_infos[index].descriptor_index);
        const code = try member_code_info(classfile, method_infos[index].attributes[..]);
        methods.push(Method {
            class_name: class_name,
            access_flags: method_access_flags(method_infos[index].access_flags),
            name: try classfile.utf8(method_infos[index].name_index),
            descriptor: descriptor,
            code: code.code,
            max_stack: code.max_stack,
            max_locals: code.max_locals,
            code_len: code.code_len,
            exception_count: code.exception_count,
            local_var_count: code.local_var_count,
            line_number_count: code.line_number_count,
            parameter_count: method_parameter_count(descriptor) as u32,
            return_descriptor: method_return_descriptor(descriptor),
        });
        index = index + 1;
    }
    return .ok(methods);
}

pub fn derive_class(classfile: &ClassFile): result<Class, ClassfileError> {
    const class_name = try classfile.class_name(classfile.this_class);
    var fields = try derive_fields(classfile, class_name);
    var methods = try derive_methods(classfile, class_name);
    var super_class = "".bytes();
    if classfile.super_class != 0 {
        super_class = try classfile.class_name(classfile.super_class);
    }
    return .ok(Class {
        name: string.from(class_name),
        descriptor: class_descriptor_from_name(class_name),
        access_flags: class_access_flags(classfile.access_flags),
        super_class: super_class,
        interfaces: try derive_interfaces(classfile),
        fields: fields,
        methods: methods,
        instance_vars: instance_var_count(&fields),
        static_vars: derive_static_vars(&fields),
        source_file: try derive_source_file(classfile),
        is_array: false,
        component_type: "".bytes(),
        element_type: "".bytes(),
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    });
}

test "method descriptor parser extracts parameter count and return type" {
    const descriptor = "([Ljava/lang/String;I)Ljava/lang/Object;".bytes();
    const first = first_type(descriptor[1..descriptor.len()]);
    assert(first.len() == 19);
    assert(first[0] == 91);
    assert(first[18] == 59);
    assert(method_parameter_count(descriptor) == 2);

    const ret = method_return_descriptor(descriptor);
    assert(ret.len() == 18);
    assert(ret[0] == 76);
    assert(ret[17] == 59);
}

test "method area parses array class descriptor metadata" {
    const name = "[[Ljava/lang/String;".bytes();
    var class = derive_array_class(name);

    assert(class.is_array);
    assert(class.name.len() == 20);
    assert(class.descriptor.len() == 20);
    assert(class.super_class.len() == 16);
    assert(class.interfaces.len() == 2);
    assert(class.component_type[0] == 91);
    assert(class.element_type[0] == 76);
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
}

test "method area defines parsed classes once" {
    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main".bytes()),
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
    assert(area.has_class("Main".bytes()));
    assert(area.symbols.symbols.len() == 1);
}

test "method area synthesizes array classes once" {
    var area = new_method_area();
    const first = area.define_array_class("[I".bytes());
    const second = area.define_array_class("[I".bytes());

    assert(first == 0);
    assert(second == 0);
    assert(area.classes.len() == 1);
    assert(area.classes[0].is_array);
    assert(area.classes[0].component_type[0] == 73);
    assert(area.has_class("[I".bytes()));
}

test "method area loads class from bytes" {
    var data = [: 34]u8;
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

    data.push(0);
    data.push(33);
    data.push(0);
    data.push(2);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);
    data.push(0);

    var area = new_method_area();
    const index = try area.load_class_from_bytes(data[..]);
    assert(index == 0);
    assert(area.has_class("Main".bytes()));
    assert(area.classes[0].descriptor.len() == 6);
}

test "method area resolves class field and method refs" {
    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main".bytes()),
            .class_ref(1),
            .utf8("answer".bytes()),
            .utf8("I".bytes()),
            .name_and_type(ConstantNameAndType { name_index: 3, descriptor_index: 4 }),
            .field_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 5 }),
            .utf8("run".bytes()),
            .utf8("()I".bytes()),
            .name_and_type(ConstantNameAndType { name_index: 7, descriptor_index: 8 }),
            .method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 9 })
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 0,
        interfaces: [],
        fields: [MemberInfo { access_flags: 8, name_index: 3, descriptor_index: 4, attributes: [] }],
        methods: [MemberInfo { access_flags: 9, name_index: 7, descriptor_index: 8, attributes: [] }],
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
    var relative = class_file_path("classes", "java/lang/Object".bytes());
    assert(relative == "classes/java/lang/Object.class");

    var rooted = class_file_path("classes/", "Main".bytes());
    assert(rooted == "classes/Main.class");

    var bare = class_file_path("", "Main".bytes());
    assert(bare == "Main.class");

    drop relative;
    drop rooted;
    drop bare;
}

test "method area derives class metadata from classfile" {
    var code_raw = [: 44]u8;
    code_raw.push(0);
    code_raw.push(2);
    code_raw.push(0);
    code_raw.push(1);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(2);
    code_raw.push(4);
    code_raw.push(172);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(2);

    code_raw.push(0);
    code_raw.push(15);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(6);
    code_raw.push(0);
    code_raw.push(1);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(42);

    code_raw.push(0);
    code_raw.push(16);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(12);
    code_raw.push(0);
    code_raw.push(1);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(2);
    code_raw.push(0);
    code_raw.push(10);
    code_raw.push(0);
    code_raw.push(8);
    code_raw.push(0);
    code_raw.push(0);
    code_raw.push(0);

    var source_raw = [: 2]u8;
    source_raw.push(0);
    source_raw.push(14);

    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main".bytes()),
            .class_ref(1),
            .utf8("java/lang/Object".bytes()),
            .class_ref(3),
            .utf8("Runnable".bytes()),
            .class_ref(5),
            .utf8("answer".bytes()),
            .utf8("I".bytes()),
            .utf8("value".bytes()),
            .utf8("run".bytes()),
            .utf8("()I".bytes()),
            .utf8("Code".bytes()),
            .utf8("SourceFile".bytes()),
            .utf8("Main.java".bytes()),
            .utf8("LineNumberTable".bytes()),
            .utf8("LocalVariableTable".bytes())
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 4,
        interfaces: [6],
        fields: [MemberInfo { access_flags: 8, name_index: 7, descriptor_index: 8, attributes: [] }, MemberInfo { access_flags: 1, name_index: 9, descriptor_index: 8, attributes: [] }],
        methods: [MemberInfo { access_flags: 9, name_index: 10, descriptor_index: 11, attributes: [AttributeInfo { name_index: 12, length: 44, raw: code_raw[..] }] }],
        attributes: [AttributeInfo { name_index: 13, length: 2, raw: source_raw[..] }],
    };

    var class = try derive_class(&classfile);
    const class_name = class.name.bytes();
    assert(class_name[0] == 77);
    assert(class.descriptor.len() == 6);
    assert(class.descriptor.bytes()[0] == 76);
    assert(class.super_class[0] == 106);
    assert(class.source_file[0] == 77);
    assert(class.source_file.len() == 9);
    assert(class.interfaces.len() == 1);
    assert(class.interfaces[0].value[0] == 82);
    assert(class.fields.len() == 2);
    assert(class.fields[0].is_static());
    assert(class.fields[0].slot == 0);
    assert(!class.fields[1].is_static());
    assert(class.fields[1].slot == 0);
    assert(class.instance_vars == 1);
    assert(class.static_vars.len() == 1);
    switch class.static_vars[0] {
    case .int_value(value) { assert(value == 0); }
    case .byte_value(value) { const ignored = value; assert(false); }
    case .short_value(value) { const ignored = value; assert(false); }
    case .char_value(value) { const ignored = value; assert(false); }
    case .long_value(value) { const ignored = value; assert(false); }
    case .float_value(value) { const ignored = value; assert(false); }
    case .double_value(value) { const ignored = value; assert(false); }
    case .boolean_value(value) { const ignored = value; assert(false); }
    case .return_address_value(value) { const ignored = value; assert(false); }
    case .ref_value(value) { const ignored = value; assert(false); }
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
    assert(class.methods[0].return_descriptor[0] == 73);
}

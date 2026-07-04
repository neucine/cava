import { Constant } from .classfile;

pub type byte = i8;
pub type short = i16;
pub type char = u16;
pub type int = i32;
pub type long = i64;
pub type float = f32;
pub type double = f64;
pub type boolean = u8;
pub type return_address = u32;

pub enum ReferenceKind: i32 {
    null_ref = 0,
    object,
    array,
}

pub struct Reference {
    pub kind: ReferenceKind;
    pub slot: ?usize;
    pub generation: usize;

    pub fn init_null(): Reference {
        return Reference {
            kind: ReferenceKind.null_ref,
            slot: none,
            generation: 0,
        };
    }

    pub fn is_null(self: Reference): bool {
        return self.slot == none;
    }

    pub fn non_null(self: Reference): bool {
        return self.slot != none;
    }

    pub fn equals(self: Reference, that: Reference): bool {
        if self.slot is left {
            if that.slot is right {
                return self.kind == that.kind and left == right and self.generation == that.generation;
            }
            return false;
        }
        return that.slot == none;
    }
}

pub union Value {
    byte_value: byte;
    short_value: short;
    char_value: char;
    int_value: int;
    long_value: long;
    float_value: float;
    double_value: double;
    boolean_value: boolean;
    return_address_value: return_address;
    ref_value: Reference;
}

pub const true_value: boolean = 1;
pub const false_value: boolean = 0;

pub enum InstructionError: i32 {
    unsupported_opcode = 0,
    missing_return,
    invalid_constant,
    unsupported_native,
}

pub type ObjectRef = Reference;
pub type ArrayRef = Reference;
pub type JavaLangClass = ObjectRef;
pub type JavaLangString = ObjectRef;
pub type JavaLangThread = ObjectRef;
pub type JavaLangThrowable = ObjectRef;
pub type JavaLangClassLoader = ObjectRef;
pub type JavaLangReflectField = ObjectRef;
pub type JavaLangReflectConstructor = ObjectRef;

pub const null_ref: Reference = Reference {
    kind: ReferenceKind.null_ref,
    slot: none,
    generation: 0,
};

fn descriptor_tag(descriptor: []const u8): u8 {
    return descriptor[0];
}

pub fn default_value(descriptor: []const u8): Value {
    const ch = descriptor_tag(descriptor);
    if ch == 66 {
        return .byte_value(0);
    }
    if ch == 67 {
        return .char_value(0);
    }
    if ch == 68 {
        return .double_value(0.0);
    }
    if ch == 70 {
        return .float_value(0.0);
    }
    if ch == 73 {
        return .int_value(0);
    }
    if ch == 74 {
        return .long_value(0);
    }
    if ch == 83 {
        return .short_value(0);
    }
    if ch == 90 {
        return .boolean_value(false_value);
    }
    if ch == 76 or ch == 91 {
        return .ref_value(null_ref);
    }

    return .int_value(0);
}

pub fn is_primitive_descriptor(descriptor: []const u8): bool {
    if descriptor.len() != 1 {
        return false;
    }

    const ch = descriptor_tag(descriptor);
    return ch == 66 or ch == 67 or ch == 68 or ch == 70 or ch == 73 or ch == 74 or ch == 83 or ch == 90;
}

pub fn method_argument_count(descriptor: string): result<usize, InstructionError> {
    const bytes = descriptor.bytes();
    if bytes.len() < 2 or bytes[0] != 40 {
        return .err(InstructionError.invalid_constant);
    }

    var index: usize = 1;
    var count: usize = 0;
    while index < bytes.len() and bytes[index] != 41 {
        while index < bytes.len() and bytes[index] == 91 {
            index = index + 1;
        }
        if index >= bytes.len() {
            return .err(InstructionError.invalid_constant);
        }
        if bytes[index] == 76 {
            while index < bytes.len() and bytes[index] != 59 {
                index = index + 1;
            }
            if index >= bytes.len() {
                return .err(InstructionError.invalid_constant);
            }
        }
        index = index + 1;
        count = count + 1;
    }

    if index >= bytes.len() or bytes[index] != 41 {
        return .err(InstructionError.invalid_constant);
    }
    return .ok(count);
}

pub fn reference_array_component_descriptor(class_name: string): string {
    const name_bytes = class_name.bytes();
    if name_bytes.len() > 0 and name_bytes[0] == 91 {
        return string.from(name_bytes);
    }

    return $"L{class_name};";
}

pub fn reference_array_descriptor(component_descriptor: string): string {
    return $"[{component_descriptor}";
}

pub fn array_component_descriptor(descriptor: string): string {
    const bytes = descriptor.bytes();
    if bytes.len() == 0 or bytes[0] != 91 {
        return string.from(bytes[0..0]);
    }
    return string.from(bytes[1..bytes.len()]);
}

pub flags ClassAccessFlags: u16 {
    public = 1,
    final = 16,
    super_flag = 32,
    interface_flag = 512,
    abstract = 1024,
    synthetic = 4096,
    annotation = 8192,
    enum_flag = 16384,
}

pub flags FieldAccessFlags: u16 {
    public = 1,
    private = 2,
    protected = 4,
    static_flag = 8,
    final = 16,
    volatile_flag = 64,
    transient = 128,
    synthetic = 4096,
    enum_flag = 16384,
}

pub flags MethodAccessFlags: u16 {
    public = 1,
    private = 2,
    protected = 4,
    static_flag = 8,
    final = 16,
    synchronized = 32,
    bridge = 64,
    varargs = 128,
    native = 256,
    abstract = 1024,
    strict = 2048,
    synthetic = 4096,
}

pub fn class_access_flags(raw: u16): ClassAccessFlags {
    return raw as ClassAccessFlags;
}

pub fn field_access_flags(raw: u16): FieldAccessFlags {
    return raw as FieldAccessFlags;
}

pub fn method_access_flags(raw: u16): MethodAccessFlags {
    return raw as MethodAccessFlags;
}

pub fn raw_class_access(access: ClassAccessFlags): u16 {
    return access as u16;
}

pub fn raw_field_access(access: FieldAccessFlags): u16 {
    return access as u16;
}

pub fn raw_method_access(access: MethodAccessFlags): u16 {
    return access as u16;
}

pub struct ExceptionHandler {
    pub start_pc: u16;
    pub end_pc: u16;
    pub handle_pc: u16;
    pub catch_type: u16;
}

pub struct Field {
    pub class_name: string;
    pub access_flags: FieldAccessFlags;
    pub name: string;
    pub descriptor: string;
    pub index: u16;
    pub slot: u16;

    pub fn is_static(self: &Field): bool {
        return FieldAccessFlags.static_flag in self.access_flags;
    }

    pub fn is_public(self: &Field): bool {
        return FieldAccessFlags.public in self.access_flags;
    }

    pub fn clear(self: &Field): void {
        self.class_name = "";
        self.name = "";
        self.descriptor = "";
    }

    pub fn __copy(self: &Field): Field {
        return Field {
            class_name: copy self.class_name,
            access_flags: self.access_flags,
            name: copy self.name,
            descriptor: copy self.descriptor,
            index: self.index,
            slot: self.slot,
        };
    }
}

pub struct Method {
    pub class_name: string;
    pub access_flags: MethodAccessFlags;
    pub name: string;
    pub descriptor: string;
    pub code: [:]u8;
    pub max_stack: u16;
    pub max_locals: u16;
    pub code_len: u32;
    pub exception_count: u32;
    pub exception_handlers: List<ExceptionHandler>;
    pub local_var_count: u32;
    pub line_number_count: u32;
    pub parameter_count: u32;
    pub return_descriptor: string;

    pub fn is_static(self: &Method): bool {
        return MethodAccessFlags.static_flag in self.access_flags;
    }

    pub fn is_native(self: &Method): bool {
        return MethodAccessFlags.native in self.access_flags;
    }

    pub fn is_abstract(self: &Method): bool {
        return MethodAccessFlags.abstract in self.access_flags;
    }

    pub fn clear(self: &Method): void {
        self.class_name = "";
        self.name = "";
        self.descriptor = "";
        self.code = byte_buffer("".bytes());
        self.exception_handlers.clear();
        self.return_descriptor = "";
    }

    pub fn __copy(self: &Method): Method {
        return Method {
            class_name: copy self.class_name,
            access_flags: self.access_flags,
            name: copy self.name,
            descriptor: copy self.descriptor,
            code: copy self.code,
            max_stack: self.max_stack,
            max_locals: self.max_locals,
            code_len: self.code_len,
            exception_count: self.exception_count,
            exception_handlers: copy self.exception_handlers,
            local_var_count: self.local_var_count,
            line_number_count: self.line_number_count,
            parameter_count: self.parameter_count,
            return_descriptor: copy self.return_descriptor,
        };
    }
}

pub fn byte_buffer(source: []const u8): [:]u8 {
    var out = [: source.len()]u8;
    var index: usize = 0;
    while index < source.len() {
        out.push(source[index]);
        index = index + 1;
    }
    return out;
}

pub fn java_utf16_units_from_utf8(source: []const u8): [:]u16 {
    var out = [: source.len()]u16;
    var index: usize = 0;
    while index < source.len() {
        const first = source[index];
        if first < 128 {
            out.push(first as u16);
            index = index + 1;
        } else {
            if first >= 192 and first < 224 and index + 1 < source.len() {
                const second = source[index + 1];
                const code = ((first as u32) & 31) << 6 | ((second as u32) & 63);
                out.push(code as u16);
                index = index + 2;
            } else {
                if first >= 224 and first < 240 and index + 2 < source.len() {
                    const second = source[index + 1];
                    const third = source[index + 2];
                    const code = ((first as u32) & 15) << 12 | (((second as u32) & 63) << 6) | ((third as u32) & 63);
                    out.push(code as u16);
                    index = index + 3;
                } else {
                    if first >= 240 and first < 248 and index + 3 < source.len() {
                        const second = source[index + 1];
                        const third = source[index + 2];
                        const fourth = source[index + 3];
                        const code = ((first as u32) & 7) << 18 | (((second as u32) & 63) << 12) | (((third as u32) & 63) << 6) | ((fourth as u32) & 63);
                        const adjusted = code - 65536;
                        out.push((55296 + ((adjusted >> 10) & 1023)) as u16);
                        out.push((56320 + (adjusted & 1023)) as u16);
                        index = index + 4;
                    } else {
                        out.push(first as u16);
                        index = index + 1;
                    }
                }
            }
        }
    }
    return out;
}

test "types decodes UTF-8 bytes to Java UTF-16 units" {
    const raw: [4]u8 = [0x37, 0xE4, 0xA0, 0x80];
    const units = java_utf16_units_from_utf8(raw[..]);
    assert(units.len() == 2);
    assert(units[0] == 55);
    assert(units[1] == 0x4800);
    drop units;
}

pub struct LocalVariable {
    pub start_pc: u16;
    pub length: u16;
    pub index: u16;
    pub name: string;
    pub descriptor: string;
}

pub struct LineNumber {
    pub start_pc: u16;
    pub line_number: u32;
}

pub struct Class {
    pub name: string;
    pub descriptor: string;
    pub access_flags: ClassAccessFlags;
    pub super_class: string;
    pub interfaces: List<string>;
    pub fields: List<Field>;
    pub methods: List<Method>;
    pub constant_pool: List<Constant>;
    pub instance_vars: u16;
    pub static_vars: List<Value>;
    pub source_file: string;
    pub is_array: bool;
    pub component_type: string;
    pub element_type: string;
    pub dimensions: u32;
    pub defined: bool;
    pub linked: bool;
    pub class_object: Reference;

    pub fn is_interface(self: &Class): bool {
        return ClassAccessFlags.interface_flag in self.access_flags;
    }

    pub fn field_index(self: &Class, name: string, descriptor: string, is_static: bool): ?i32 {
        var i: usize = 0;
        while i < self.fields.len() {
            const field = &self.fields[i];
            if field.name == name and field.descriptor == descriptor and field.is_static() == is_static {
                return i as i32;
            }
            i = i + 1;
        }
        return none;
    }

    pub fn method_index(self: &Class, name: string, descriptor: string, is_static: bool): ?i32 {
        var i: usize = 0;
        while i < self.methods.len() {
            const method = &self.methods[i];
            if method.name == name and method.descriptor == descriptor and method.is_static() == is_static {
                return i as i32;
            }
            i = i + 1;
        }
        return none;
    }

    pub fn has_field(self: &Class, name: string, descriptor: string, is_static: bool): bool {
        return self.field_index(name, descriptor, is_static) != none;
    }

    pub fn has_method(self: &Class, name: string, descriptor: string, is_static: bool): bool {
        return self.method_index(name, descriptor, is_static) != none;
    }

    pub fn clear(self: &Class): void {
        self.name = "";
        self.descriptor = "";
        self.super_class = "";
        while self.interfaces.len() > 0 {
            var interface_name = self.interfaces.pop();
            drop interface_name;
        }

        var field_index: usize = 0;
        while field_index < self.fields.len() {
            self.fields[field_index].clear();
            field_index = field_index + 1;
        }
        self.fields.clear();

        var method_index: usize = 0;
        while method_index < self.methods.len() {
            self.methods[method_index].clear();
            method_index = method_index + 1;
        }
        self.methods.clear();

        var constant_index: usize = 0;
        while constant_index < self.constant_pool.len() {
            self.constant_pool[constant_index] = .unusable(0);
            constant_index = constant_index + 1;
        }
        self.constant_pool.clear();
        self.static_vars.clear();
        self.source_file = "";
        self.component_type = "";
        self.element_type = "";
    }

    pub fn __copy(self: &Class): Class {
        return Class {
            name: copy self.name,
            descriptor: copy self.descriptor,
            access_flags: self.access_flags,
            super_class: copy self.super_class,
            interfaces: copy self.interfaces,
            fields: copy self.fields,
            methods: copy self.methods,
            constant_pool: copy self.constant_pool,
            instance_vars: self.instance_vars,
            static_vars: copy self.static_vars,
            source_file: copy self.source_file,
            is_array: self.is_array,
            component_type: copy self.component_type,
            element_type: copy self.element_type,
            dimensions: self.dimensions,
            defined: self.defined,
            linked: self.linked,
            class_object: self.class_object,
        };
    }
}

fn fail_unexpected_value(value: Value): void {
    switch value {
    case .byte_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .short_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .char_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .int_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .long_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .float_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .double_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .boolean_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .return_address_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    case .ref_value(ignored) {
        const unused = ignored;
        assert(false);
    }
    }
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
    case .byte_value(value) { fail_unexpected_value(.byte_value(value)); }
    case .short_value(value) { fail_unexpected_value(.short_value(value)); }
    case .char_value(value) { fail_unexpected_value(.char_value(value)); }
    case .long_value(value) { fail_unexpected_value(.long_value(value)); }
    case .float_value(value) { fail_unexpected_value(.float_value(value)); }
    case .double_value(value) { fail_unexpected_value(.double_value(value)); }
    case .boolean_value(value) { fail_unexpected_value(.boolean_value(value)); }
    case .return_address_value(value) { fail_unexpected_value(.return_address_value(value)); }
    case .ref_value(value) { fail_unexpected_value(.ref_value(value)); }
    }

    switch default_value("Z".bytes()) {
    case .boolean_value(value) {
        assert(value == false_value);
    }
    case .byte_value(value) { fail_unexpected_value(.byte_value(value)); }
    case .short_value(value) { fail_unexpected_value(.short_value(value)); }
    case .char_value(value) { fail_unexpected_value(.char_value(value)); }
    case .int_value(value) { fail_unexpected_value(.int_value(value)); }
    case .long_value(value) { fail_unexpected_value(.long_value(value)); }
    case .float_value(value) { fail_unexpected_value(.float_value(value)); }
    case .double_value(value) { fail_unexpected_value(.double_value(value)); }
    case .return_address_value(value) { fail_unexpected_value(.return_address_value(value)); }
    case .ref_value(value) { fail_unexpected_value(.ref_value(value)); }
    }
}

test "reference descriptor default" {
    switch default_value("Ljava/lang/Object;".bytes()) {
    case .ref_value(reference) {
        assert(reference.is_null());
    }
    case .byte_value(value) { fail_unexpected_value(.byte_value(value)); }
    case .short_value(value) { fail_unexpected_value(.short_value(value)); }
    case .char_value(value) { fail_unexpected_value(.char_value(value)); }
    case .int_value(value) { fail_unexpected_value(.int_value(value)); }
    case .long_value(value) { fail_unexpected_value(.long_value(value)); }
    case .float_value(value) { fail_unexpected_value(.float_value(value)); }
    case .double_value(value) { fail_unexpected_value(.double_value(value)); }
    case .boolean_value(value) { fail_unexpected_value(.boolean_value(value)); }
    case .return_address_value(value) { fail_unexpected_value(.return_address_value(value)); }
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
        assert(class.methods[value].max_stack == 2);
        assert(class.methods[value].parameter_count == 1);
    } else {
        assert(false);
    }

    assert(!class.has_field("answer", "I", false));
    assert(!class.has_method("missing", "()V", true));
}

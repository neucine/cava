pub type byte = i8;
pub type short = i16;
pub type char = u16;
pub type int = i32;
pub type long = i64;
pub type float = f32;
pub type double = f64;
pub type boolean = u8;
pub type return_address = u32;

pub struct Reference {
    pub object_id: ?u64;

    pub fn init_null(): Reference {
        return Reference { object_id: none };
    }

    pub fn is_null(self: Reference): bool {
        return self.object_id == none;
    }

    pub fn non_null(self: Reference): bool {
        return self.object_id != none;
    }

    pub fn equals(self: Reference, that: Reference): bool {
        if self.object_id is left {
            if that.object_id is right {
                return left == right;
            }
            return false;
        }
        return that.object_id == none;
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

pub type ObjectRef = Reference;
pub type ArrayRef = Reference;
pub type JavaLangClass = ObjectRef;
pub type JavaLangString = ObjectRef;
pub type JavaLangThread = ObjectRef;
pub type JavaLangThrowable = ObjectRef;
pub type JavaLangClassLoader = ObjectRef;
pub type JavaLangReflectField = ObjectRef;
pub type JavaLangReflectConstructor = ObjectRef;

pub const null_ref: Reference = Reference { object_id: none };

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

pub struct Field {
    pub class_name: []const u8;
    pub access_flags: FieldAccessFlags;
    pub name: []const u8;
    pub descriptor: []const u8;
    pub index: u16;
    pub slot: u16;

    pub fn is_static(self: &Field): bool {
        return FieldAccessFlags.static_flag in self.access_flags;
    }

    pub fn is_public(self: &Field): bool {
        return FieldAccessFlags.public in self.access_flags;
    }
}

pub struct Name {
    pub value: []const u8;
}

pub struct Method {
    pub class_name: []const u8;
    pub access_flags: MethodAccessFlags;
    pub name: []const u8;
    pub descriptor: []const u8;
    pub code: []const u8;
    pub max_stack: u16;
    pub max_locals: u16;
    pub code_len: u32;
    pub exception_count: u32;
    pub local_var_count: u32;
    pub line_number_count: u32;
    pub parameter_count: u32;
    pub return_descriptor: []const u8;

    pub fn is_static(self: &Method): bool {
        return MethodAccessFlags.static_flag in self.access_flags;
    }

    pub fn is_native(self: &Method): bool {
        return MethodAccessFlags.native in self.access_flags;
    }

    pub fn is_abstract(self: &Method): bool {
        return MethodAccessFlags.abstract in self.access_flags;
    }
}

pub struct LocalVariable {
    pub start_pc: u16;
    pub length: u16;
    pub index: u16;
    pub name: []const u8;
    pub descriptor: []const u8;
}

pub struct LineNumber {
    pub start_pc: u16;
    pub line_number: u32;
}

pub struct ExceptionHandler {
    pub start_pc: u16;
    pub end_pc: u16;
    pub handle_pc: u16;
    pub catch_type: u16;
}

pub struct Class {
    pub name: string;
    pub descriptor: string;
    pub access_flags: ClassAccessFlags;
    pub super_class: []const u8;
    pub interfaces: List<Name>;
    pub fields: List<Field>;
    pub methods: List<Method>;
    pub instance_vars: u16;
    pub static_vars: List<Value>;
    pub source_file: []const u8;
    pub is_array: bool;
    pub component_type: []const u8;
    pub element_type: []const u8;
    pub dimensions: u32;
    pub defined: bool;
    pub linked: bool;
    pub class_object: Reference;

    pub fn is_interface(self: &Class): bool {
        return ClassAccessFlags.interface_flag in self.access_flags;
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

    pub fn field_index(self: &Class, name: []const u8, descriptor: []const u8, is_static: bool): ?i32 {
        var i: usize = 0;
        while i < self.fields.len() {
            if Class.bytes_equal(self.fields[i].name, name) and Class.bytes_equal(self.fields[i].descriptor, descriptor) and self.fields[i].is_static() == is_static {
                return i as i32;
            }
            i = i + 1;
        }
        return none;
    }

    pub fn method_index(self: &Class, name: []const u8, descriptor: []const u8, is_static: bool): ?i32 {
        var i: usize = 0;
        while i < self.methods.len() {
            if Class.bytes_equal(self.methods[i].name, name) and Class.bytes_equal(self.methods[i].descriptor, descriptor) and self.methods[i].is_static() == is_static {
                return i as i32;
            }
            i = i + 1;
        }
        return none;
    }

    pub fn has_field(self: &Class, name: []const u8, descriptor: []const u8, is_static: bool): bool {
        return self.field_index(name, descriptor, is_static) != none;
    }

    pub fn has_method(self: &Class, name: []const u8, descriptor: []const u8, is_static: bool): bool {
        return self.method_index(name, descriptor, is_static) != none;
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
    const second = Reference { object_id: none };
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
        class_name: "Example".bytes(),
        access_flags: field_access_flags(0x0008),
        name: "answer".bytes(),
        descriptor: "I".bytes(),
        index: 0,
        slot: 0,
    };
    const method = Method {
        class_name: "Example".bytes(),
        access_flags: method_access_flags(0x0009),
        name: "main".bytes(),
        descriptor: "([Ljava/lang/String;)V".bytes(),
        code: "A".bytes(),
        max_stack: 2,
        max_locals: 1,
        code_len: 8,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 1,
        return_descriptor: "V".bytes(),
    };
    const class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object".bytes(),
        interfaces: [],
        fields: [field],
        methods: [method],
        instance_vars: 0,
        static_vars: [],
        source_file: "Example.java".bytes(),
        is_array: false,
        component_type: "".bytes(),
        element_type: "".bytes(),
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };

    const found_field = class.field_index("answer".bytes(), "I".bytes(), true);
    if found_field is value {
        assert(value == 0);
    } else {
        assert(false);
    }

    const found_method = class.method_index("main".bytes(), "([Ljava/lang/String;)V".bytes(), true);
    if found_method is value {
        assert(value == 0);
        assert(class.methods[value].max_stack == 2);
        assert(class.methods[value].parameter_count == 1);
    } else {
        assert(false);
    }

    assert(!class.has_field("answer".bytes(), "I".bytes(), false));
    assert(!class.has_method("missing".bytes(), "()V".bytes(), true));
}

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

pub const null_ref: Reference = {
    kind: ReferenceKind.null_ref,
    slot: none,
    generation: 0,
};

fn descriptor_tag(descriptor: []const u8): u8 {
    return descriptor[0];
}

pub fn default_value(descriptor: []const u8): Value {
    const ch = descriptor_tag(descriptor);
    if ch == 'B' {
        return .byte_value(0);
    }
    if ch == 'C' {
        return .char_value(0);
    }
    if ch == 'D' {
        return .double_value(0.0);
    }
    if ch == 'F' {
        return .float_value(0.0);
    }
    if ch == 'I' {
        return .int_value(0);
    }
    if ch == 'J' {
        return .long_value(0);
    }
    if ch == 'S' {
        return .short_value(0);
    }
    if ch == 'Z' {
        return .boolean_value(false_value);
    }
    if ch == 'L' or ch == '[' {
        return .ref_value(null_ref);
    }

    return .int_value(0);
}

pub fn is_primitive_descriptor(descriptor: []const u8): bool {
    if descriptor.len() != 1 {
        return false;
    }

    const ch = descriptor_tag(descriptor);
    return ch == 'B' or ch == 'C' or ch == 'D' or ch == 'F' or ch == 'I' or ch == 'J' or ch == 'S' or ch == 'Z';
}

pub fn method_argument_count(descriptor: string): usize ! InstructionError {
    const bytes = descriptor.bytes();
    if bytes.len() < 2 or bytes[0] != '(' {
        throw InstructionError.invalid_constant;
    }

    var index: usize = 1;
    var count: usize = 0;
    while index < bytes.len() and bytes[index] != ')' {
        while index < bytes.len() and bytes[index] == '[' {
            index = index + 1;
        }
        if index >= bytes.len() {
            throw InstructionError.invalid_constant;
        }
        if bytes[index] == 'L' {
            while index < bytes.len() and bytes[index] != ';' {
                index = index + 1;
            }
            if index >= bytes.len() {
                throw InstructionError.invalid_constant;
            }
        }
        index = index + 1;
        count = count + 1;
    }

    if index >= bytes.len() or bytes[index] != ')' {
        throw InstructionError.invalid_constant;
    }
    return count;
}

pub fn reference_array_component_descriptor(class_name: string): string {
    const name_bytes = class_name.bytes();
    if name_bytes.len() > 0 and name_bytes[0] == '[' {
        return string.from(name_bytes);
    }

    return $"L{class_name};";
}

pub fn reference_array_descriptor(component_descriptor: string): string {
    return $"[{component_descriptor}";
}

pub fn array_component_descriptor(descriptor: string): string {
    const bytes = descriptor.bytes();
    if bytes.len() == 0 or bytes[0] != '[' {
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

impl ExceptionHandler: Clone {
    fn clone(self: &const ExceptionHandler): ExceptionHandler {
        return ExceptionHandler {
            start_pc: self.start_pc,
            end_pc: self.end_pc,
            handle_pc: self.handle_pc,
            catch_type: self.catch_type,
        };
    }
}

pub struct Field {
    pub class_name: string;
    pub access_flags: FieldAccessFlags;
    pub name: string;
    pub descriptor: string;
    pub index: u16;
    pub slot: u16;

    pub fn is_static(self: &const Field): bool {
        return FieldAccessFlags.static_flag in self.access_flags;
    }

    pub fn is_public(self: &const Field): bool {
        return FieldAccessFlags.public in self.access_flags;
    }

    pub fn clear(self: &Field): void {
        self.class_name = "";
        self.name = "";
        self.descriptor = "";
    }

    pub fn clone(self: &const Field): Field {
        return Field {
            class_name: self.class_name.clone(),
            access_flags: self.access_flags,
            name: self.name.clone(),
            descriptor: self.descriptor.clone(),
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

    pub fn is_static(self: &const Method): bool {
        return MethodAccessFlags.static_flag in self.access_flags;
    }

    pub fn is_native(self: &const Method): bool {
        return MethodAccessFlags.native in self.access_flags;
    }

    pub fn is_synchronized(self: &const Method): bool {
        return MethodAccessFlags.synchronized in self.access_flags;
    }

    pub fn is_abstract(self: &const Method): bool {
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

    pub fn clone(self: &const Method): Method {
        return Method {
            class_name: self.class_name.clone(),
            access_flags: self.access_flags,
            name: self.name.clone(),
            descriptor: self.descriptor.clone(),
            code: self.code.clone(),
            max_stack: self.max_stack,
            max_locals: self.max_locals,
            code_len: self.code_len,
            exception_count: self.exception_count,
            exception_handlers: self.exception_handlers.clone(),
            local_var_count: self.local_var_count,
            line_number_count: self.line_number_count,
            parameter_count: self.parameter_count,
            return_descriptor: self.return_descriptor.clone(),
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
        } else if first >= 192 and first < 224 and index + 1 < source.len() {
            const second = source[index + 1];
            const code = ((first as u32) & 31) << 6 | ((second as u32) & 63);
            out.push(code as u16);
            index = index + 2;
        } else if first >= 224 and first < 240 and index + 2 < source.len() {
            const second = source[index + 1];
            const third = source[index + 2];
            const code = ((first as u32) & 15) << 12 | (((second as u32) & 63) << 6) | ((third as u32) & 63);
            out.push(code as u16);
            index = index + 3;
        } else if first >= 240 and first < 248 and index + 3 < source.len() {
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
    return out;
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

    pub fn is_interface(self: &const Class): bool {
        return ClassAccessFlags.interface_flag in self.access_flags;
    }

    pub fn field_index(self: &const Class, name: string, descriptor: string, is_static: bool): ?i32 {
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

    pub fn method_index(self: &const Class, name: string, descriptor: string, is_static: bool): ?i32 {
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

    pub fn has_field(self: &const Class, name: string, descriptor: string, is_static: bool): bool {
        return self.field_index(name, descriptor, is_static) != none;
    }

    pub fn has_method(self: &const Class, name: string, descriptor: string, is_static: bool): bool {
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

    pub fn clone(self: &const Class): Class {
        var fields: List<Field> = [];
        var field_index: usize = 0;
        while field_index < self.fields.len() {
            fields.push(self.fields[field_index].clone());
            field_index = field_index + 1;
        }
        var methods: List<Method> = [];
        var index: usize = 0;
        while index < self.methods.len() {
            methods.push(self.methods[index].clone());
            index = index + 1;
        }
        var constants: List<Constant> = [];
        var constant_index: usize = 0;
        while constant_index < self.constant_pool.len() {
            switch self.constant_pool[constant_index] {
                .utf8(value) => {
                    constants.push(.utf8(value.clone()));
                }
                _ => {
                    constants.push(self.constant_pool[constant_index]);
                }
            }
            constant_index = constant_index + 1;
        }
        var static_vars: List<Value> = [];
        var static_index: usize = 0;
        while static_index < self.static_vars.len() {
            static_vars.push(self.static_vars[static_index]);
            static_index = static_index + 1;
        }
        return Class {
            name: self.name.clone(),
            descriptor: self.descriptor.clone(),
            access_flags: self.access_flags,
            super_class: self.super_class.clone(),
            interfaces: self.interfaces.clone(),
            fields: fields,
            methods: methods,
            constant_pool: constants,
            instance_vars: self.instance_vars,
            static_vars: static_vars,
            source_file: self.source_file.clone(),
            is_array: self.is_array,
            component_type: self.component_type.clone(),
            element_type: self.element_type.clone(),
            dimensions: self.dimensions,
            defined: self.defined,
            linked: self.linked,
            class_object: self.class_object,
        };
    }
}

fn fail_unexpected_value(value: Value): void {
    switch value {
        .byte_value => {
            assert(false);
        }
        .short_value => {
            assert(false);
        }
        .char_value => {
            assert(false);
        }
        .int_value => {
            assert(false);
        }
        .long_value => {
            assert(false);
        }
        .float_value => {
            assert(false);
        }
        .double_value => {
            assert(false);
        }
        .boolean_value => {
            assert(false);
        }
        .return_address_value => {
            assert(false);
        }
        .ref_value => {
            assert(false);
        }
    }
}

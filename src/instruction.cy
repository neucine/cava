import { Constant, ConstantMemberRef, ConstantMethodHandle, ConstantNameAndType, ConstantWide } from .classfile;
import { Context, Frame, FrameResult, apply_method_result, dispatch_exception, execute_method_frame_with_runtime, execute_method_frame_with_vm, new_frame } from .engine;
import { InitializationDecision } from .class_initialization;
import { enter_monitor } from .method_monitor;
import { MethodArea, ResolvedMethod, class_matches, find_loaded_class_index, new_method_area, reference_assignable_to, runtime_field_slot } from .method_area;
import { VM } from .vm;
import { new_vm } from .vm;
import { execute_native_method } from .native;
import { Class, Field, InstructionError, Method, Reference, ReferenceKind, Value, array_component_descriptor, byte_buffer, class_access_flags, field_access_flags, method_access_flags, method_argument_count, null_ref, reference_array_component_descriptor, reference_array_descriptor } from .types;
import { env_get } from std.process;

pub enum Opcode: i32 {
    unsupported = 256,
    nop = 0,
    aconst_null,
    iconst_m1 = 2,
    iconst_0,
    iconst_1,
    iconst_2,
    iconst_3,
    iconst_4,
    iconst_5,
    lconst_0 = 9,
    lconst_1,
    fconst_0,
    fconst_1,
    fconst_2,
    dconst_0,
    dconst_1,
    bipush = 16,
    sipush = 17,
    ldc,
    ldc_w,
    ldc2_w,
    iload = 21,
    lload,
    fload,
    dload,
    aload = 25,
    iload_0 = 26,
    iload_1,
    iload_2,
    iload_3,
    lload_0,
    lload_1,
    lload_2,
    lload_3,
    fload_0,
    fload_1,
    fload_2,
    fload_3,
    dload_0,
    dload_1,
    dload_2,
    dload_3,
    aload_0 = 42,
    aload_1,
    aload_2,
    aload_3,
    iaload = 46,
    laload,
    faload,
    daload,
    aaload,
    baload,
    caload,
    saload,
    istore = 54,
    lstore,
    fstore,
    dstore,
    astore = 58,
    istore_0 = 59,
    istore_1,
    istore_2,
    istore_3,
    lstore_0,
    lstore_1,
    lstore_2,
    lstore_3,
    fstore_0,
    fstore_1,
    fstore_2,
    fstore_3,
    dstore_0,
    dstore_1,
    dstore_2,
    dstore_3,
    astore_0 = 75,
    astore_1,
    astore_2,
    astore_3,
    iastore = 79,
    lastore,
    fastore,
    dastore,
    aastore,
    bastore,
    castore,
    sastore,
    pop = 87,
    pop2,
    dup,
    dup_x1,
    dup_x2,
    dup2,
    dup2_x1,
    dup2_x2,
    swap = 95,
    iadd = 96,
    ladd,
    fadd,
    dadd,
    isub = 100,
    lsub,
    fsub,
    dsub,
    imul = 104,
    lmul,
    fmul,
    dmul,
    idiv,
    ldiv,
    fdiv = 110,
    ddiv,
    irem,
    lrem,
    ineg = 116,
    lneg,
    fneg,
    dneg,
    ishl = 120,
    lshl,
    ishr = 122,
    lshr,
    iushr,
    lushr,
    iand = 126,
    land,
    ior = 128,
    lor,
    ixor = 130,
    lxor,
    iinc = 132,
    i2l,
    i2f,
    i2d,
    l2i = 136,
    l2f,
    l2d,
    f2i,
    f2l,
    f2d,
    d2i,
    d2l,
    d2f,
    i2b = 145,
    i2c,
    i2s,
    lcmp = 148,
    fcmpl,
    fcmpg,
    dcmpl,
    dcmpg,
    ifeq = 153,
    ifne,
    iflt,
    ifge,
    ifgt,
    ifle,
    if_icmpeq,
    if_icmpne,
    if_icmplt,
    if_icmpge,
    if_icmpgt,
    if_icmple,
    if_acmpeq,
    if_acmpne,
    goto_ = 167,
    jsr,
    ret,
    tableswitch = 170,
    lookupswitch,
    ireturn = 172,
    lreturn,
    freturn,
    dreturn,
    areturn = 176,
    return_ = 177,
    getstatic = 178,
    putstatic,
    getfield,
    putfield,
    invoke_virtual,
    invoke_special,
    invoke_static,
    invoke_interface,
    invoke_dynamic,
    new_ = 187,
    newarray = 188,
    anewarray,
    arraylength = 190,
    athrow = 191,
    checkcast,
    instanceof,
    monitorenter,
    monitorexit,
    wide = 196,
    multianewarray,
    ifnull = 198,
    ifnonnull,
    goto_w = 200,
    jsr_w,
}

pub struct Instruction {
    pub opcode: Opcode;
    pub length: u32;
    pub execute: ExecuteFn;
    pub local_execute: LocalExecuteFn;
    pub is_local: bool;
}

type ExecuteFn = fn (context: &Context, vm: &VM): result<void, InstructionError>;
type LocalExecuteFn = fn (context: &Context): result<void, InstructionError>;

pub fn constant_utf8(context: &Context, index: u16): result<string, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
        case .utf8(value) {
            return .ok(string.from(value.bytes()));
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }
}

pub fn constant_class_name(context: &Context, index: u16): result<string, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
        case .class_ref(name_index) {
            return constant_utf8(context, name_index);
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }
}

fn constant_utf8_equals(context: &Context, index: u16, expected: string): result<bool, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
        case .utf8(value) {
            return .ok(value == expected);
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }
}

pub fn find_class_index_by_constant(context: &Context, vm: &VM, index: u16): result<usize, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        case .class_ref(actual) {
            name_index = actual;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }
    if name_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[name_index as usize] {
        case .utf8(name) {
            return vm.resolve_class_index(copy name);
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }
}

pub fn find_class_index(context: &Context, vm: &VM, name: string): result<usize, InstructionError> {
    return vm.resolve_class_index(copy name);
}

pub fn field_runtime_slot(vm: &VM, reference: Reference, field: Field): ?u16 {
    if vm.heap.object_class_index(reference) is object_class_index {
        return runtime_field_slot(vm.method_area.classes[..], object_class_index, field);
    }
    return none;
}

fn find_field_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.fields.len() {
        const field = &class.fields[index];
        const name_matches = try constant_utf8_equals(context, name_index, field.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, field.descriptor);
        if name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_field_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<Field, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        switch find_field_index_by_constants(class, context, name_index, descriptor_index) {
            case .ok(field_index) {
                return .ok(class.fields[field_index]);
            }
            case .err {}
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

pub fn find_field_by_name_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name: string, descriptor: string, is_static: bool): result<Field, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        if class.field_index(name, descriptor, is_static) is field_index {
            return .ok(class.fields[field_index as usize]);
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

pub fn find_field_index(class: &Class, name: string, descriptor: string): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.fields.len() {
        const field = &class.fields[index];
        if field.name == name and field.descriptor == descriptor {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_static_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.methods.len() {
        const method = &class.methods[index];
        const name_matches = try constant_utf8_equals(context, name_index, method.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, method.descriptor);
        if method.is_static() and name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_instance_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.methods.len() {
        const method = &class.methods[index];
        const name_matches = try constant_utf8_equals(context, name_index, method.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, method.descriptor);
        if !method.is_static() and name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_static_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<ResolvedMethod, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        switch find_static_method_index_by_constants(class, context, name_index, descriptor_index) {
            case .ok(method_index) {
                return .ok(ResolvedMethod {
                    class_index: current_index,
                    method_index: method_index
                });
            }
            case .err {}
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

fn find_instance_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<ResolvedMethod, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        switch find_instance_method_index_by_constants(class, context, name_index, descriptor_index) {
            case .ok(method_index) {
                return .ok(ResolvedMethod {
                    class_index: current_index,
                    method_index: method_index
                });
            }
            case .err {}
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

fn find_interface_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<ResolvedMethod, InstructionError> {
    if class_index >= vm.method_area.classes.len() {
        return .err(InstructionError.invalid_constant);
    }
    var classes = vm.method_area.classes[..];
    switch find_instance_method_index_by_constants(&classes[class_index], context, name_index, descriptor_index) {
        case .ok(method_index) {
            return .ok(ResolvedMethod {
                class_index: class_index,
                method_index: method_index
            });
        }
        case .err {}
    }

    var interface_index: usize = 0;
    while interface_index < classes[class_index].interfaces.len() {
        switch vm.resolve_class_index(copy classes[class_index].interfaces[interface_index]) {
            case .ok(parent_index) {
                switch find_interface_method_index_in_hierarchy(context, vm, parent_index, name_index, descriptor_index) {
                    case .ok(found) {
                        return .ok(found);
                    }
                    case .err {}
                }
            }
            case .err {}
        }
        interface_index = interface_index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

pub fn find_instance_method_by_name_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name: string, descriptor: string): result<ResolvedMethod, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        if class.method_index(name, descriptor, false) is method_index {
            return .ok(ResolvedMethod {
                class_index: current_index,
                method_index: method_index as usize
            });
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

pub fn resolve_field(context: &Context, vm: &VM, index: u16): result<Field, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        case .field_ref(member) {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        case .name_and_type(pair) {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_field_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_static_method(context: &Context, vm: &VM, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        case .method_ref(member) {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        case .name_and_type(pair) {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_static_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_instance_method(context: &Context, vm: &VM, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        case .method_ref(member) {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        case .name_and_type(pair) {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_instance_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_interface_method(context: &Context, vm: &VM, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        case .interface_method_ref(member) {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        case .name_and_type(pair) {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_interface_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

fn push_int(context: &Context, value: i32): void {
    context.frame.stack.push(.int_value(value));
}

fn expect_int(value: Value): i32 {
    switch value {
        case .int_value(actual) {
            return actual;
        }
        case .boolean_value(actual) {
            return actual as i32;
        }
        case .byte_value(actual) {
            return actual as i32;
        }
        case .short_value(actual) {
            return actual as i32;
        }
        case .char_value(actual) {
            return actual as i32;
        } else {
            assert(false);
        }
    }
    return 0;
}

fn expect_ref(value: Value): Reference {
    switch value {
        case .ref_value(actual) {
            return actual;
        } else {
            assert(false);
        }
    }
    return null_ref;
}

fn expect_long(value: Value): i64 {
    switch value {
        case .long_value(actual) {
            return actual;
        } else {
            assert(false);
        }
    }
    return 0;
}

fn expect_float(value: Value): f32 {
    switch value {
        case .float_value(actual) {
            return actual;
        } else {
            assert(false);
        }
    }
    return 0.0;
}

fn expect_double(value: Value): f64 {
    switch value {
        case .double_value(actual) {
            return actual;
        } else {
            assert(false);
        }
    }
    return 0.0;
}

fn expect_return_address(value: Value): u32 {
    switch value {
        case .return_address_value(actual) {
            return actual;
        } else {
            assert(false);
        }
    }
    return 0;
}

fn expect_array_load(context: &Context, vm: &VM): Value {
    const index = expect_int(context.frame.pop());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() or index < 0 {
        assert(false);
    }
    if vm.heap.get_element(reference, index as usize) is value {
        return value;
    }
    assert(false);
    return .int_value(0);
}

fn store_array_value(context: &Context, vm: &VM, value: Value): void {
    const index = expect_int(context.frame.pop());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() or index < 0 {
        assert(false);
    }
    if vm.heap.set_element(reference, index as usize, value) {
        return;
    }
    assert(false);
}

fn load_int(context: &Context, index: u16): void {
    push_int(context, expect_int(context.frame.load(index)));
}

fn load_long(context: &Context, index: u16): void {
    context.frame.push(.long_value(expect_long(context.frame.load(index))));
}

fn load_float(context: &Context, index: u16): void {
    context.frame.push(.float_value(expect_float(context.frame.load(index))));
}

fn load_double(context: &Context, index: u16): void {
    context.frame.push(.double_value(expect_double(context.frame.load(index))));
}

fn store_int(context: &Context, index: u16): void {
    context.frame.store(index, .int_value(expect_int(context.frame.pop())));
}

fn store_long(context: &Context, index: u16): void {
    context.frame.store(index, .long_value(expect_long(context.frame.pop())));
}

fn store_float(context: &Context, index: u16): void {
    context.frame.store(index, .float_value(expect_float(context.frame.pop())));
}

fn store_double(context: &Context, index: u16): void {
    context.frame.store(index, .double_value(expect_double(context.frame.pop())));
}

fn load_ref(context: &Context, index: u16): void {
    context.frame.push(.ref_value(expect_ref(context.frame.load(index))));
}

fn store_ref_like(context: &Context, index: u16): void {
    const value = context.frame.pop();
    switch value {
        case .ref_value(reference) {
            context.frame.store(index, .ref_value(reference));
        }
        case .return_address_value(address) {
            context.frame.store(index, .return_address_value(address));
        } else {
            assert(false);
        }
    }
}

fn is_category2(value: Value): bool {
    switch value {
        case .long_value {
            return true;
        }
        case .double_value {
            return true;
        } else {
            return false;
        }
    }
}

fn sign_extend_u1(value: u8): i32 {
    if value > 127 {
        return (value as i32) - 256;
    }
    return value as i32;
}

fn wide_bits(value: ConstantWide): u64 {
    return ((value.high_bytes as u64) << 32) | (value.low_bytes as u64);
}

fn load_constant(context: &Context, vm: &VM, index: u16, wide: bool): result<void, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    const constant = context.constant_pool[index as usize];
    switch constant {
        case .integer(bits) {
            if wide {
                return .err(InstructionError.invalid_constant);
            }
            context.frame.push(.int_value(bits as! i32));
            return .ok();
        }
        case .float(bits) {
            if wide {
                return .err(InstructionError.invalid_constant);
            }
            context.frame.push(.float_value(bits as! f32));
            return .ok();
        }
        case .long(bits) {
            if !wide {
                return .err(InstructionError.invalid_constant);
            }
            context.frame.push(.long_value(wide_bits(bits) as! i64));
            return .ok();
        }
        case .double(bits) {
            if !wide {
                return .err(InstructionError.invalid_constant);
            }
            context.frame.push(.double_value(wide_bits(bits) as! f64));
            return .ok();
        }
        case .class_ref(name_index) {
            if wide {
                return .err(InstructionError.invalid_constant);
            }
            return load_class_constant(context, vm, index, name_index);
        }
        case .string_ref(utf8_index) {
            if wide {
                return .err(InstructionError.invalid_constant);
            }
            return load_string_constant(context, vm, utf8_index);
        }
        case .method_type(descriptor_index) {
            if wide {
                return .err(InstructionError.invalid_constant);
            }
            return load_method_type_constant(context, vm, descriptor_index);
        }
        case .method_handle(handle) {
            if wide {
                return .err(InstructionError.invalid_constant);
            }
            return load_method_handle_constant(context, vm, handle);
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }
}

fn load_class_constant(context: &Context, vm: &VM, constant_index: u16, name_index: u16): result<void, InstructionError> {
    const ignored = name_index;
    const target_class_index = try find_class_index_by_constant(context, vm, constant_index);
    const class_class_index = try vm.resolve_class_index("java/lang/Class");
    var classes = vm.method_area.classes[..];
    const class_class = &classes[class_class_index];
    const target_class = &classes[target_class_index];
    if target_class.class_object.is_null() {
        target_class.class_object = vm.heap.allocate_object(class_class_index, class_class);
    }
    context.frame.push(.ref_value(target_class.class_object));
    return .ok();
}

fn load_string_constant(context: &Context, vm: &VM, utf8_index: u16): result<void, InstructionError> {
    if utf8_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var value: []const u8 = "".bytes();
    switch context.constant_pool[utf8_index as usize] {
        case .utf8(actual) {
            value = actual.bytes();
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    switch vm.method_area.resolve_class("java/lang/String") {
        case .ok {}
        case .err {
            return .err(InstructionError.invalid_constant);
        }
    }
    const reference = try vm.allocate_java_string(value);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn load_method_type_constant(context: &Context, vm: &VM, descriptor_index: u16): result<void, InstructionError> {
    if descriptor_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var descriptor: []const u8 = "".bytes();
    switch context.constant_pool[descriptor_index as usize] {
        case .utf8(actual) {
            descriptor = actual.bytes();
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }

    const method_type_class_index = try vm.resolve_class_index("java/lang/invoke/MethodType");
    var classes = vm.method_area.classes[..];
    const reference = vm.heap.intern_method_type(method_type_class_index, &classes[method_type_class_index], descriptor);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn load_method_handle_constant(context: &Context, vm: &VM, handle: ConstantMethodHandle): result<void, InstructionError> {
    if handle.reference_kind < 1 or handle.reference_kind > 9 {
        return .err(InstructionError.invalid_constant);
    }
    if handle.reference_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    const method_handle_class_index = try vm.resolve_class_index("java/lang/invoke/MethodHandle");
    var classes = vm.method_area.classes[..];
    const reference = vm.heap.intern_method_handle(method_handle_class_index, &classes[method_handle_class_index], handle.reference_kind, handle.reference_index);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn unsupported(context: &Context, vm: &VM): result<void, InstructionError> {
    return .err(InstructionError.unsupported_opcode);
}

fn nop(context: &Context): result<void, InstructionError> {
    return .ok();
}

fn aconst_null(context: &Context): result<void, InstructionError> {
    context.frame.push(.ref_value(null_ref));
    return .ok();
}

fn iconst_m1(context: &Context): result<void, InstructionError> {
    push_int(context, 0 - 1);
    return .ok();
}

fn iconst_0(context: &Context): result<void, InstructionError> {
    push_int(context, 0);
    return .ok();
}

fn iconst_1(context: &Context): result<void, InstructionError> {
    push_int(context, 1);
    return .ok();
}

fn iconst_2(context: &Context): result<void, InstructionError> {
    push_int(context, 2);
    return .ok();
}

fn iconst_3(context: &Context): result<void, InstructionError> {
    push_int(context, 3);
    return .ok();
}

fn iconst_4(context: &Context): result<void, InstructionError> {
    push_int(context, 4);
    return .ok();
}

fn iconst_5(context: &Context): result<void, InstructionError> {
    push_int(context, 5);
    return .ok();
}

fn lconst_0(context: &Context): result<void, InstructionError> {
    context.frame.push(.long_value(0));
    return .ok();
}

fn lconst_1(context: &Context): result<void, InstructionError> {
    context.frame.push(.long_value(1));
    return .ok();
}

fn fconst_0(context: &Context): result<void, InstructionError> {
    context.frame.push(.float_value(0.0));
    return .ok();
}

fn fconst_1(context: &Context): result<void, InstructionError> {
    context.frame.push(.float_value(1.0));
    return .ok();
}

fn fconst_2(context: &Context): result<void, InstructionError> {
    context.frame.push(.float_value(2.0));
    return .ok();
}

fn dconst_0(context: &Context): result<void, InstructionError> {
    context.frame.push(.double_value(0.0));
    return .ok();
}

fn dconst_1(context: &Context): result<void, InstructionError> {
    context.frame.push(.double_value(1.0));
    return .ok();
}

fn ldc(context: &Context, vm: &VM): result<void, InstructionError> {
    return load_constant(context, vm, context.read_u1() as u16, false);
}

fn ldc_w(context: &Context, vm: &VM): result<void, InstructionError> {
    return load_constant(context, vm, context.read_u2(), false);
}

fn ldc2_w(context: &Context, vm: &VM): result<void, InstructionError> {
    return load_constant(context, vm, context.read_u2(), true);
}

fn bipush(context: &Context): result<void, InstructionError> {
    push_int(context, sign_extend_u1(context.read_u1()));
    return .ok();
}

fn sipush(context: &Context): result<void, InstructionError> {
    push_int(context, context.read_i2() as i32);
    return .ok();
}

fn iload(context: &Context): result<void, InstructionError> {
    load_int(context, context.read_u1() as u16);
    return .ok();
}

fn lload(context: &Context): result<void, InstructionError> {
    load_long(context, context.read_u1() as u16);
    return .ok();
}

fn fload(context: &Context): result<void, InstructionError> {
    load_float(context, context.read_u1() as u16);
    return .ok();
}

fn dload(context: &Context): result<void, InstructionError> {
    load_double(context, context.read_u1() as u16);
    return .ok();
}

fn aload(context: &Context): result<void, InstructionError> {
    load_ref(context, context.read_u1() as u16);
    return .ok();
}

fn iload_0(context: &Context): result<void, InstructionError> {
    load_int(context, 0);
    return .ok();
}

fn iload_1(context: &Context): result<void, InstructionError> {
    load_int(context, 1);
    return .ok();
}

fn iload_2(context: &Context): result<void, InstructionError> {
    load_int(context, 2);
    return .ok();
}

fn iload_3(context: &Context): result<void, InstructionError> {
    load_int(context, 3);
    return .ok();
}

fn lload_0(context: &Context): result<void, InstructionError> {
    load_long(context, 0);
    return .ok();
}

fn lload_1(context: &Context): result<void, InstructionError> {
    load_long(context, 1);
    return .ok();
}

fn lload_2(context: &Context): result<void, InstructionError> {
    load_long(context, 2);
    return .ok();
}

fn lload_3(context: &Context): result<void, InstructionError> {
    load_long(context, 3);
    return .ok();
}

fn fload_0(context: &Context): result<void, InstructionError> {
    load_float(context, 0);
    return .ok();
}

fn fload_1(context: &Context): result<void, InstructionError> {
    load_float(context, 1);
    return .ok();
}

fn fload_2(context: &Context): result<void, InstructionError> {
    load_float(context, 2);
    return .ok();
}

fn fload_3(context: &Context): result<void, InstructionError> {
    load_float(context, 3);
    return .ok();
}

fn dload_0(context: &Context): result<void, InstructionError> {
    load_double(context, 0);
    return .ok();
}

fn dload_1(context: &Context): result<void, InstructionError> {
    load_double(context, 1);
    return .ok();
}

fn dload_2(context: &Context): result<void, InstructionError> {
    load_double(context, 2);
    return .ok();
}

fn dload_3(context: &Context): result<void, InstructionError> {
    load_double(context, 3);
    return .ok();
}

fn aload_0(context: &Context): result<void, InstructionError> {
    load_ref(context, 0);
    return .ok();
}

fn aload_1(context: &Context): result<void, InstructionError> {
    load_ref(context, 1);
    return .ok();
}

fn aload_2(context: &Context): result<void, InstructionError> {
    load_ref(context, 2);
    return .ok();
}

fn aload_3(context: &Context): result<void, InstructionError> {
    load_ref(context, 3);
    return .ok();
}

fn istore(context: &Context): result<void, InstructionError> {
    store_int(context, context.read_u1() as u16);
    return .ok();
}

fn lstore(context: &Context): result<void, InstructionError> {
    store_long(context, context.read_u1() as u16);
    return .ok();
}

fn fstore(context: &Context): result<void, InstructionError> {
    store_float(context, context.read_u1() as u16);
    return .ok();
}

fn dstore(context: &Context): result<void, InstructionError> {
    store_double(context, context.read_u1() as u16);
    return .ok();
}

fn astore(context: &Context): result<void, InstructionError> {
    store_ref_like(context, context.read_u1() as u16);
    return .ok();
}

fn istore_0(context: &Context): result<void, InstructionError> {
    store_int(context, 0);
    return .ok();
}

fn istore_1(context: &Context): result<void, InstructionError> {
    store_int(context, 1);
    return .ok();
}

fn istore_2(context: &Context): result<void, InstructionError> {
    store_int(context, 2);
    return .ok();
}

fn istore_3(context: &Context): result<void, InstructionError> {
    store_int(context, 3);
    return .ok();
}

fn lstore_0(context: &Context): result<void, InstructionError> {
    store_long(context, 0);
    return .ok();
}

fn lstore_1(context: &Context): result<void, InstructionError> {
    store_long(context, 1);
    return .ok();
}

fn lstore_2(context: &Context): result<void, InstructionError> {
    store_long(context, 2);
    return .ok();
}

fn lstore_3(context: &Context): result<void, InstructionError> {
    store_long(context, 3);
    return .ok();
}

fn fstore_0(context: &Context): result<void, InstructionError> {
    store_float(context, 0);
    return .ok();
}

fn fstore_1(context: &Context): result<void, InstructionError> {
    store_float(context, 1);
    return .ok();
}

fn fstore_2(context: &Context): result<void, InstructionError> {
    store_float(context, 2);
    return .ok();
}

fn fstore_3(context: &Context): result<void, InstructionError> {
    store_float(context, 3);
    return .ok();
}

fn dstore_0(context: &Context): result<void, InstructionError> {
    store_double(context, 0);
    return .ok();
}

fn dstore_1(context: &Context): result<void, InstructionError> {
    store_double(context, 1);
    return .ok();
}

fn dstore_2(context: &Context): result<void, InstructionError> {
    store_double(context, 2);
    return .ok();
}

fn dstore_3(context: &Context): result<void, InstructionError> {
    store_double(context, 3);
    return .ok();
}

fn astore_0(context: &Context): result<void, InstructionError> {
    store_ref_like(context, 0);
    return .ok();
}

fn astore_1(context: &Context): result<void, InstructionError> {
    store_ref_like(context, 1);
    return .ok();
}

fn astore_2(context: &Context): result<void, InstructionError> {
    store_ref_like(context, 2);
    return .ok();
}

fn astore_3(context: &Context): result<void, InstructionError> {
    store_ref_like(context, 3);
    return .ok();
}

fn iaload(context: &Context, vm: &VM): result<void, InstructionError> {
    push_int(context, expect_int(expect_array_load(context, vm)));
    return .ok();
}

fn laload(context: &Context, vm: &VM): result<void, InstructionError> {
    context.frame.push(.long_value(expect_long(expect_array_load(context, vm))));
    return .ok();
}

fn faload(context: &Context, vm: &VM): result<void, InstructionError> {
    context.frame.push(.float_value(expect_float(expect_array_load(context, vm))));
    return .ok();
}

fn daload(context: &Context, vm: &VM): result<void, InstructionError> {
    context.frame.push(.double_value(expect_double(expect_array_load(context, vm))));
    return .ok();
}

fn aaload(context: &Context, vm: &VM): result<void, InstructionError> {
    context.frame.push(.ref_value(expect_ref(expect_array_load(context, vm))));
    return .ok();
}

fn baload(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_array_load(context, vm);
    switch value {
        case .byte_value(actual) {
            push_int(context, actual as i32);
        }
        case .boolean_value(actual) {
            push_int(context, actual as i32);
        } else {
            assert(false);
        }
    }
    return .ok();
}

fn caload(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_array_load(context, vm);
    switch value {
        case .char_value(actual) {
            push_int(context, actual as i32);
        } else {
            assert(false);
        }
    }
    return .ok();
}

fn saload(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_array_load(context, vm);
    switch value {
        case .short_value(actual) {
            push_int(context, actual as i32);
        } else {
            assert(false);
        }
    }
    return .ok();
}

fn pop(context: &Context): result<void, InstructionError> {
    const ignored = context.frame.pop();
    return .ok();
}

fn pop2(context: &Context): result<void, InstructionError> {
    const first = context.frame.pop();
    if !is_category2(first) {
        const second = context.frame.pop();
        const ignored = second;
    }
    return .ok();
}

fn dup(context: &Context): result<void, InstructionError> {
    const value = context.frame.pop();
    context.frame.push(value);
    context.frame.push(value);
    return .ok();
}

fn dup_x1(context: &Context): result<void, InstructionError> {
    const value1 = context.frame.pop();
    const value2 = context.frame.pop();
    if is_category2(value1) or is_category2(value2) {
        assert(false);
    }
    context.frame.push(value1);
    context.frame.push(value2);
    context.frame.push(value1);
    return .ok();
}

fn dup_x2(context: &Context): result<void, InstructionError> {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        assert(false);
    }
    const value2 = context.frame.pop();
    if is_category2(value2) {
        context.frame.push(value1);
        context.frame.push(value2);
        context.frame.push(value1);
        return .ok();
    }
    const value3 = context.frame.pop();
    if is_category2(value3) {
        assert(false);
    }
    context.frame.push(value1);
    context.frame.push(value3);
    context.frame.push(value2);
    context.frame.push(value1);
    return .ok();
}

fn dup2(context: &Context): result<void, InstructionError> {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        context.frame.push(value1);
        context.frame.push(value1);
        return .ok();
    }
    const value2 = context.frame.pop();
    if is_category2(value2) {
        assert(false);
    }
    context.frame.push(value2);
    context.frame.push(value1);
    context.frame.push(value2);
    context.frame.push(value1);
    return .ok();
}

fn dup2_x1(context: &Context): result<void, InstructionError> {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        const value2 = context.frame.pop();
        if is_category2(value2) {
            assert(false);
        }
        context.frame.push(value1);
        context.frame.push(value2);
        context.frame.push(value1);
        return .ok();
    }
    const value2 = context.frame.pop();
    const value3 = context.frame.pop();
    if is_category2(value2) or is_category2(value3) {
        assert(false);
    }
    context.frame.push(value2);
    context.frame.push(value1);
    context.frame.push(value3);
    context.frame.push(value2);
    context.frame.push(value1);
    return .ok();
}

fn dup2_x2(context: &Context): result<void, InstructionError> {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        const value2 = context.frame.pop();
        if is_category2(value2) {
            context.frame.push(value1);
            context.frame.push(value2);
            context.frame.push(value1);
            return .ok();
        }
        const value3 = context.frame.pop();
        if is_category2(value3) {
            context.frame.push(value1);
            context.frame.push(value3);
            context.frame.push(value2);
            context.frame.push(value1);
            return .ok();
        }
        assert(false);
    }
    const value2 = context.frame.pop();
    if is_category2(value2) {
        assert(false);
    }
    const value3 = context.frame.pop();
    if is_category2(value3) {
        context.frame.push(value2);
        context.frame.push(value1);
        context.frame.push(value3);
        context.frame.push(value2);
        context.frame.push(value1);
        return .ok();
    }
    const value4 = context.frame.pop();
    if is_category2(value4) {
        assert(false);
    }
    context.frame.push(value2);
    context.frame.push(value1);
    context.frame.push(value4);
    context.frame.push(value3);
    context.frame.push(value2);
    context.frame.push(value1);
    return .ok();
}

fn swap(context: &Context): result<void, InstructionError> {
    const value1 = context.frame.pop();
    const value2 = context.frame.pop();
    if is_category2(value1) or is_category2(value2) {
        assert(false);
    }
    context.frame.push(value1);
    context.frame.push(value2);
    return .ok();
}

fn iastore(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    store_array_value(context, vm, .int_value(value));
    return .ok();
}

fn lastore(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_long(context.frame.pop());
    store_array_value(context, vm, .long_value(value));
    return .ok();
}

fn fastore(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_float(context.frame.pop());
    store_array_value(context, vm, .float_value(value));
    return .ok();
}

fn dastore(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_double(context.frame.pop());
    store_array_value(context, vm, .double_value(value));
    return .ok();
}

fn aastore(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_ref(context.frame.pop());
    store_array_value(context, vm, .ref_value(value));
    return .ok();
}

fn bastore(context: &Context, vm: &VM): result<void, InstructionError> {
    const raw = expect_int(context.frame.pop());
    const index = expect_int(context.frame.pop());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() or index < 0 {
        assert(false);
    }
    if vm.heap.get_element(reference, index as usize) is current {
        switch current {
            case .boolean_value {
                const low_bit: u8 = (raw & 1) as u8;
                if vm.heap.set_element(reference, index as usize, .boolean_value(low_bit)) {
                    return .ok();
                }
            }
            case .byte_value {
                const low_bits: u8 = (raw & 255) as u8;
                if vm.heap.set_element(reference, index as usize, .byte_value(low_bits as! i8)) {
                    return .ok();
                }
            } else {
                assert(false);
            }
        }
    }
    assert(false);
    return .ok();
}

fn castore(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    store_array_value(context, vm, .char_value(low_bits));
    return .ok();
}

fn sastore(context: &Context, vm: &VM): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    store_array_value(context, vm, .short_value(low_bits as! i16));
    return .ok();
}

fn iadd(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 +% value2);
    return .ok();
}

fn ladd(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 +% value2));
    return .ok();
}

fn fadd(context: &Context): result<void, InstructionError> {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 + value2));
    return .ok();
}

fn dadd(context: &Context): result<void, InstructionError> {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 + value2));
    return .ok();
}

fn isub(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 -% value2);
    return .ok();
}

fn lsub(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 -% value2));
    return .ok();
}

fn fsub(context: &Context): result<void, InstructionError> {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 - value2));
    return .ok();
}

fn dsub(context: &Context): result<void, InstructionError> {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 - value2));
    return .ok();
}

fn imul(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 *% value2);
    return .ok();
}

fn lmul(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 *% value2));
    return .ok();
}

fn fmul(context: &Context): result<void, InstructionError> {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 * value2));
    return .ok();
}

fn dmul(context: &Context): result<void, InstructionError> {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 * value2));
    return .ok();
}

fn fdiv(context: &Context): result<void, InstructionError> {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 / value2));
    return .ok();
}

fn ddiv(context: &Context): result<void, InstructionError> {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 / value2));
    return .ok();
}

fn idiv(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    if value2 == 0 {
        assert(false);
    }
    const min_value: i32 = (0 - 2147483647) - 1;
    if value1 == min_value and value2 == (0 - 1) {
        push_int(context, min_value);
    } else {
        push_int(context, value1 / value2);
    }
    return .ok();
}

fn ldiv(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    if value2 == 0 {
        assert(false);
    }
    const min_value: i64 = (0 - 9223372036854775807) - 1;
    if value1 == min_value and value2 == (0 - 1) {
        context.frame.push(.long_value(min_value));
    } else {
        context.frame.push(.long_value(value1 / value2));
    }
    return .ok();
}

fn irem(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    if value2 == 0 {
        assert(false);
    }
    push_int(context, value1 % value2);
    return .ok();
}

fn lrem(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    if value2 == 0 {
        assert(false);
    }
    context.frame.push(.long_value(value1 % value2));
    return .ok();
}

fn ineg(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    push_int(context, 0 -% value);
    return .ok();
}

fn lneg(context: &Context): result<void, InstructionError> {
    const value = expect_long(context.frame.pop());
    context.frame.push(.long_value(0 -% value));
    return .ok();
}

fn fneg(context: &Context): result<void, InstructionError> {
    const value = expect_float(context.frame.pop());
    const zero: f32 = 0.0;
    context.frame.push(.float_value(zero - value));
    return .ok();
}

fn dneg(context: &Context): result<void, InstructionError> {
    const value = expect_double(context.frame.pop());
    context.frame.push(.double_value(0.0 - value));
    return .ok();
}

fn ishl(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 << (value2 & 31));
    return .ok();
}

fn lshl(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 << (value2 & 63)));
    return .ok();
}

fn ishr(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 >> (value2 & 31));
    return .ok();
}

fn lshr(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 >> (value2 & 63)));
    return .ok();
}

fn iushr(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    const bits: u32 = value1 as! u32;
    push_int(context, (bits >> (value2 & 31)) as! i32);
    return .ok();
}

fn lushr(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    const bits: u64 = value1 as! u64;
    context.frame.push(.long_value((bits >> (value2 & 63)) as! i64));
    return .ok();
}

fn iand(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 & value2);
    return .ok();
}

fn land(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 & value2));
    return .ok();
}

fn ior(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 | value2);
    return .ok();
}

fn lor(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 | value2));
    return .ok();
}

fn ixor(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, (value1 | value2) -% (value1 & value2));
    return .ok();
}

fn lxor(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value((value1 | value2) -% (value1 & value2)));
    return .ok();
}

fn iinc(context: &Context): result<void, InstructionError> {
    const index = context.read_u1() as u16;
    const increment = sign_extend_u1(context.read_u1());
    const value = expect_int(context.frame.load(index));
    context.frame.store(index, .int_value(value +% increment));
    return .ok();
}

fn i2l(context: &Context): result<void, InstructionError> {
    context.frame.push(.long_value(expect_int(context.frame.pop()) as i64));
    return .ok();
}

fn i2f(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const zero: f32 = 0.0;
    context.frame.push(.float_value(value + zero));
    return .ok();
}

fn i2d(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const zero: f64 = 0.0;
    context.frame.push(.double_value(value + zero));
    return .ok();
}

fn l2i(context: &Context): result<void, InstructionError> {
    const value = expect_long(context.frame.pop());
    const low_bits: u32 = (value & 4294967295) as u32;
    push_int(context, low_bits as! i32);
    return .ok();
}

fn l2f(context: &Context): result<void, InstructionError> {
    const value = expect_long(context.frame.pop());
    const zero: f32 = 0.0;
    context.frame.push(.float_value(value + zero));
    return .ok();
}

fn l2d(context: &Context): result<void, InstructionError> {
    const value = expect_long(context.frame.pop());
    const zero: f64 = 0.0;
    context.frame.push(.double_value(value + zero));
    return .ok();
}

fn f2d(context: &Context): result<void, InstructionError> {
    const value = expect_float(context.frame.pop());
    context.frame.push(.double_value(value as f64));
    return .ok();
}

fn jvm_f2i_value(value: f32): i32 {
    if value != value {
        return 0;
    }
    const min_value: f32 = -2147483648.0;
    const upper_value: f32 = 2147483648.0;
    if value <= min_value {
        return (0 - 2147483647) - 1;
    }
    if value >= upper_value {
        return 2147483647;
    }
    return value as i32;
}

fn jvm_f2l_value(value: f32): i64 {
    if value != value {
        return 0;
    }
    const min_value: f32 = -9223372036854775808.0;
    const upper_value: f32 = 9223372036854775808.0;
    if value <= min_value {
        return (0 - 9223372036854775807) - 1;
    }
    if value >= upper_value {
        return 9223372036854775807;
    }
    return value as i64;
}

fn jvm_d2i_value(value: f64): i32 {
    if value != value {
        return 0;
    }
    const min_value: f64 = -2147483648.0;
    const upper_value: f64 = 2147483648.0;
    if value <= min_value {
        return (0 - 2147483647) - 1;
    }
    if value >= upper_value {
        return 2147483647;
    }
    return value as i32;
}

fn jvm_d2l_value(value: f64): i64 {
    if value != value {
        return 0;
    }
    const min_value: f64 = -9223372036854775808.0;
    const upper_value: f64 = 9223372036854775808.0;
    if value <= min_value {
        return (0 - 9223372036854775807) - 1;
    }
    if value >= upper_value {
        return 9223372036854775807;
    }
    return value as i64;
}

fn f2i(context: &Context): result<void, InstructionError> {
    push_int(context, jvm_f2i_value(expect_float(context.frame.pop())));
    return .ok();
}

fn f2l(context: &Context): result<void, InstructionError> {
    context.frame.push(.long_value(jvm_f2l_value(expect_float(context.frame.pop()))));
    return .ok();
}

fn d2i(context: &Context): result<void, InstructionError> {
    push_int(context, jvm_d2i_value(expect_double(context.frame.pop())));
    return .ok();
}

fn d2l(context: &Context): result<void, InstructionError> {
    context.frame.push(.long_value(jvm_d2l_value(expect_double(context.frame.pop()))));
    return .ok();
}

fn d2f(context: &Context): result<void, InstructionError> {
    context.frame.push(.float_value(expect_double(context.frame.pop()) as f32));
    return .ok();
}

fn i2b(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const low_bits: u8 = (value & 255) as u8;
    push_int(context, (low_bits as! i8) as i32);
    return .ok();
}

fn i2c(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    push_int(context, low_bits as i32);
    return .ok();
}

fn i2s(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    push_int(context, (low_bits as! i16) as i32);
    return .ok();
}

fn lcmp(context: &Context): result<void, InstructionError> {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    if value1 > value2 {
        push_int(context, 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 0 - 1);
    }
    return .ok();
}

fn fcmpl(context: &Context): result<void, InstructionError> {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 < value2 {
        push_int(context, 0 - 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 1);
    }
    return .ok();
}

fn fcmpg(context: &Context): result<void, InstructionError> {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 > value2 {
        push_int(context, 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 0 - 1);
    }
    return .ok();
}

fn dcmpl(context: &Context): result<void, InstructionError> {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 < value2 {
        push_int(context, 0 - 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 1);
    }
    return .ok();
}

fn dcmpg(context: &Context): result<void, InstructionError> {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 > value2 {
        push_int(context, 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 0 - 1);
    }
    return .ok();
}

fn branch(context: &Context, should_branch: bool): void {
    const offset = context.read_i2() as i32;
    if should_branch {
        context.frame.next(offset);
    }
}

fn ifeq(context: &Context): result<void, InstructionError> {
    branch(context, expect_int(context.frame.pop()) == 0);
    return .ok();
}

fn ifne(context: &Context): result<void, InstructionError> {
    branch(context, expect_int(context.frame.pop()) != 0);
    return .ok();
}

fn iflt(context: &Context): result<void, InstructionError> {
    branch(context, expect_int(context.frame.pop()) < 0);
    return .ok();
}

fn ifge(context: &Context): result<void, InstructionError> {
    branch(context, expect_int(context.frame.pop()) >= 0);
    return .ok();
}

fn ifgt(context: &Context): result<void, InstructionError> {
    branch(context, expect_int(context.frame.pop()) > 0);
    return .ok();
}

fn ifle(context: &Context): result<void, InstructionError> {
    branch(context, expect_int(context.frame.pop()) <= 0);
    return .ok();
}

fn if_icmpeq(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 == value2);
    return .ok();
}

fn if_icmpne(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 != value2);
    return .ok();
}

fn if_icmplt(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 < value2);
    return .ok();
}

fn if_icmpge(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 >= value2);
    return .ok();
}

fn if_icmpgt(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 > value2);
    return .ok();
}

fn if_icmple(context: &Context): result<void, InstructionError> {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 <= value2);
    return .ok();
}

fn if_acmpeq(context: &Context): result<void, InstructionError> {
    const value2 = expect_ref(context.frame.pop());
    const value1 = expect_ref(context.frame.pop());
    branch(context, value1.equals(value2));
    return .ok();
}

fn if_acmpne(context: &Context): result<void, InstructionError> {
    const value2 = expect_ref(context.frame.pop());
    const value1 = expect_ref(context.frame.pop());
    branch(context, !value1.equals(value2));
    return .ok();
}

fn goto_(context: &Context): result<void, InstructionError> {
    context.frame.next(context.read_i2() as i32);
    return .ok();
}

fn goto_w(context: &Context): result<void, InstructionError> {
    context.frame.next(context.read_i4());
    return .ok();
}

fn jsr(context: &Context): result<void, InstructionError> {
    const return_address = context.frame.pc + 3;
    context.frame.push(.return_address_value(return_address));
    context.frame.next(context.read_i2() as i32);
    return .ok();
}

fn ret(context: &Context): result<void, InstructionError> {
    const index = context.read_u1() as u16;
    context.frame.pc = expect_return_address(context.frame.load(index));
    return .ok();
}

fn tableswitch(context: &Context): result<void, InstructionError> {
    const key = expect_int(context.frame.pop());
    context.padding();
    const default_offset = context.read_i4();
    const low = context.read_i4();
    const high = context.read_i4();
    if high < low {
        assert(false);
    }

    var current = low;
    while current <= high {
        const jump_offset = context.read_i4();
        if key == current {
            context.frame.next(jump_offset);
            return .ok();
        }
        current = current + 1;
    }

    context.frame.next(default_offset);
    return .ok();
}

fn lookupswitch(context: &Context): result<void, InstructionError> {
    const key = expect_int(context.frame.pop());
    context.padding();
    const default_offset = context.read_i4();
    const pair_count = context.read_i4();
    if pair_count < 0 {
        assert(false);
    }

    var index: i32 = 0;
    while index < pair_count {
        const match_value = context.read_i4();
        const jump_offset = context.read_i4();
        if key == match_value {
            context.frame.next(jump_offset);
            return .ok();
        }
        index = index + 1;
    }

    context.frame.next(default_offset);
    return .ok();
}

fn jsr_w(context: &Context): result<void, InstructionError> {
    const return_address = context.frame.pc + 5;
    context.frame.push(.return_address_value(return_address));
    context.frame.next(context.read_i4());
    return .ok();
}

fn ireturn(context: &Context): result<void, InstructionError> {
    const result: FrameResult = .return_value(context.frame.stack.pop());
    context.frame.result = result;
    return .ok();
}

fn lreturn(context: &Context): result<void, InstructionError> {
    const value: Value = .long_value(expect_long(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return .ok();
}

fn freturn(context: &Context): result<void, InstructionError> {
    const value: Value = .float_value(expect_float(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return .ok();
}

fn dreturn(context: &Context): result<void, InstructionError> {
    const value: Value = .double_value(expect_double(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return .ok();
}

fn areturn(context: &Context): result<void, InstructionError> {
    const value: Value = .ref_value(expect_ref(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return .ok();
}

fn return_(context: &Context): result<void, InstructionError> {
    const result: FrameResult = .return_value(none);
    context.frame.result = result;
    return .ok();
}

fn value_local_width(value: Value): u16 {
    if is_category2(value) {
        return 2;
    }
    return 1;
}

fn instruction_length_for_scan(opcode: u8, code: []const u8): usize {
    if opcode == 170 {
        const padding = (4 - ((1) % 4)) % 4;
        if code.len() < 1 + padding + 12 {
            return 1;
        }
        const low = read_scan_i4(code, 1 + padding + 4);
        const high = read_scan_i4(code, 1 + padding + 8);
        return 1 + padding + 12 + (((high - low + 1) as usize) * 4);
    }
    if opcode == 171 {
        const padding = (4 - ((1) % 4)) % 4;
        if code.len() < 1 + padding + 8 {
            return 1;
        }
        const npairs = read_scan_i4(code, 1 + padding + 4);
        return 1 + padding + 8 + ((npairs as usize) * 8);
    }
    if opcode == 196 {
        if code.len() > 1 and code[1] == 132 {
            return 6;
        }
        return 4;
    }
    if registry[opcode as usize].opcode == Opcode.unsupported {
        return 1;
    }
    return registry[opcode as usize].length as usize;
}

fn read_scan_i4(code: []const u8, offset: usize): i32 {
    if offset + 3 >= code.len() {
        return 0;
    }
    return ((code[offset] as i32) << 24) | ((code[offset + 1] as i32) << 16) | ((code[offset + 2] as i32) << 8) | (code[offset + 3] as i32);
}

fn native_arguments(arguments: List<Value>): List<Value> {
    var in_args = arguments;
    var out: List<Value> = [];
    while in_args.len() > 0 {
        out.push(in_args.pop());
    }
    return out;
}

pub fn is_access_controller_do_privileged(classes: []Class, class_index: usize, method_index: usize): bool {
    if classes[class_index].name != "java/security/AccessController" {
        return false;
    }
    const method_name = classes[class_index].methods[method_index].name;
    const descriptor = classes[class_index].methods[method_index].descriptor;
    if method_name != "doPrivileged" {
        return false;
    }
    return descriptor == "(Ljava/security/PrivilegedAction;)Ljava/lang/Object;"
    or descriptor == "(Ljava/security/PrivilegedExceptionAction;)Ljava/lang/Object;"
    or descriptor == "(Ljava/security/PrivilegedAction;Ljava/security/AccessControlContext;)Ljava/lang/Object;"
    or descriptor == "(Ljava/security/PrivilegedExceptionAction;Ljava/security/AccessControlContext;)Ljava/lang/Object;";
}

fn execute_child_method_frame(context: &Context, vm: &VM, class_index: usize, method_index: usize, frame: Frame, constant_pool: []const Constant): result<FrameResult, InstructionError> {
    if context.runtime is runtime {
        return execute_method_frame_with_runtime(copy runtime, vm, class_index, method_index, frame, constant_pool);
    }
    return execute_method_frame_with_vm(vm, class_index, method_index, frame, constant_pool);
}

pub fn invoke_privileged_action(context: &Context, vm: &VM, action: Reference): result<?Value, InstructionError> {
    if action.is_null() {
        return .err(InstructionError.invalid_constant);
    }
    var action_class_index: usize = 0;
    if vm.heap.object_class_index(action) is actual_class_index {
        action_class_index = actual_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var run_method_index: usize = 0;
    var classes = vm.method_area.classes[..];
    if classes[action_class_index].method_index("run", "()Ljava/lang/Object;", false) is actual_run_method_index {
        run_method_index = actual_run_method_index as usize;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var frame = new_frame(action_class_index, run_method_index, classes[action_class_index].methods[run_method_index].max_locals, classes[action_class_index].methods[run_method_index].max_stack);
    frame.store(0, .ref_value(action));
    const result = try execute_child_method_frame(context, vm, action_class_index, run_method_index, frame, context.constant_pool);
    switch result {
        case .return_value(value) {
            return .ok(value);
        }
        case .exception {
            return .err(InstructionError.invalid_constant);
        }
    }
}

fn invoke_instance_method_direct(context: &Context, vm: &VM, receiver: Reference, name: string, descriptor: string, arguments: &List<Value>): result<?Value, InstructionError> {
    if receiver.is_null() {
        return .err(InstructionError.invalid_constant);
    }
    var receiver_class_index: usize = 0;
    if vm.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }

    const target = try find_instance_method_by_name_in_hierarchy(context, vm, receiver_class_index, name, descriptor);
    var classes = vm.method_area.classes[..];
    const target_class = &classes[target.class_index];
    var target_methods = target_class.methods[..];
    const target_method = &target_methods[target.method_index];
    if target_method.is_native() {
        return .err(InstructionError.unsupported_native);
    }

    var frame = new_frame(target.class_index, target.method_index, target_method.max_locals, target_method.max_stack);
    frame.store(0, .ref_value(receiver));
    var local_index: u16 = 1;
    var argument_index: usize = 0;
    while argument_index < arguments.len() {
        const value = arguments[argument_index];
        frame.store(local_index, value);
        local_index = local_index + value_local_width(value);
        argument_index = argument_index + 1;
    }

    const result = try execute_child_method_frame(context, vm, target.class_index, target.method_index, frame, context.constant_pool);
    switch result {
        case .return_value(value) {
            return .ok(value);
        }
        case .exception {
            return .err(InstructionError.invalid_constant);
        }
    }
}

fn find_class_object_index_instruction(context: &Context, vm: &VM, class_object: Reference): ?usize {
    var classes = vm.method_area.classes[..];
    var index: usize = 0;
    while index < classes.len() {
        const class = &classes[index];
        if class.class_object.equals(class_object) {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn get_instance_field_by_name(context: &Context, vm: &VM, reference: Reference, class_index: usize, name: string, descriptor: string): result<Value, InstructionError> {
    const field = try find_field_by_name_in_hierarchy(context, vm, class_index, name, descriptor, false);
    if field_runtime_slot(vm, reference, field) is slot {
        if vm.heap.get_field(reference, slot) is value {
            return .ok(value);
        }
    }
    return .err(InstructionError.invalid_constant);
}

fn java_string_bytes_instruction(context: &Context, vm: &VM, reference: Reference): result<[:]u8, InstructionError> {
    var value_option = vm.heap.string_bytes(reference);
    if take value_option is value {
        const bytes = copy value.value;
        return .ok(bytes);
    }
    const string_class_index = try vm.resolve_class_index("java/lang/String");
    const value_field = try get_instance_field_by_name(context, vm, reference, string_class_index, "value", "[C");
    switch value_field {
        case .ref_value(chars_reference) {
            if vm.heap.array_length(chars_reference) is length {
                var bytes: List<u8> = [];
                var index: usize = 0;
                while index < length {
                    if vm.heap.get_element(chars_reference, index) is element {
                        switch element {
                            case .char_value(ch) {
                                bytes.push(ch as u8);
                            }
                            case .byte_value(ch) {
                                bytes.push(ch as u8);
                            } else {
                                return .err(InstructionError.invalid_constant);
                            }
                        }
                    } else {
                        return .err(InstructionError.invalid_constant);
                    }
                    index = index + 1;
                }
                const out = byte_buffer(bytes[..]);
                return .ok(out);
            }
        } else {
            return .err(InstructionError.invalid_constant);
        }
    }
    return .err(InstructionError.invalid_constant);
}

pub fn invoke_reflect_constructor(context: &Context, vm: &VM, constructor: Reference, args_array: Reference): result<?Value, InstructionError> {
    const constructor_class_index = try vm.resolve_class_index("java/lang/reflect/Constructor");
    const clazz_value = try get_instance_field_by_name(context, vm, constructor, constructor_class_index, "clazz", "Ljava/lang/Class;");
    const signature_value = try get_instance_field_by_name(context, vm, constructor, constructor_class_index, "signature", "Ljava/lang/String;");
    const clazz_reference = expect_ref(clazz_value);
    const signature_reference = expect_ref(signature_value);
    var descriptor_bytes = try java_string_bytes_instruction(context, vm, signature_reference);
    var target_class_index: usize = 0;
    if find_class_object_index_instruction(context, vm, clazz_reference) is actual_target_class_index {
        target_class_index = actual_target_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var classes = vm.method_area.classes[..];
    const target_class = &classes[target_class_index];
    var constructor_method_index: usize = 0;
    const descriptor = string.from(descriptor_bytes[..]);
    if target_class.method_index("<init>", descriptor, false) is constructor_method_index_value {
        constructor_method_index = constructor_method_index_value as usize;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var methods = target_class.methods[..];
    const constructor_method = &methods[constructor_method_index];
    const object = vm.heap.allocate_object_with_hierarchy(target_class_index, classes);
    var frame = new_frame(target_class_index, constructor_method_index, constructor_method.max_locals, constructor_method.max_stack);
    frame.store(0, .ref_value(object));
    if args_array.non_null() {
        if vm.heap.array_length(args_array) is length {
            var index: usize = 0;
            while index < length and index + 1 < constructor_method.max_locals as usize {
                if vm.heap.get_element(args_array, index) is arg {
                    frame.store((index + 1) as u16, arg);
                }
                index = index + 1;
            }
        }
    }
    const result = try execute_child_method_frame(context, vm, target_class_index, constructor_method_index, frame, target_class.constant_pool[..]);
    switch result {
        case .return_value {
            const out: Value = .ref_value(object);
            return .ok(out);
        }
        case .exception {
            return .err(InstructionError.invalid_constant);
        }
    }
}

fn set_java_system_property(context: &Context, vm: &VM, properties: Reference, key: []const u8, value: []const u8): result<void, InstructionError> {
    var arguments: List<Value> = [];
    const ignored_string_index = try vm.resolve_class_index("java/lang/String");
    const key_reference = try vm.allocate_java_string(key);
    const value_reference = try vm.allocate_java_string(value);
    arguments.push(.ref_value(key_reference));
    arguments.push(.ref_value(value_reference));
    const result = try invoke_instance_method_direct(context, vm, properties, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;", &arguments);
    const ignored = result;
    return .ok();
}

pub fn initialize_java_system_properties(context: &Context, vm: &VM, properties: Reference): result<?Value, InstructionError> {
    try set_java_system_property(context, vm, properties, "java.version".bytes(), "1.8.0_152-ea".bytes());
    try set_java_system_property(context, vm, properties, "java.home".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "java.specification.name".bytes(), "Java Platform API Specification".bytes());
    try set_java_system_property(context, vm, properties, "java.specification.version".bytes(), "1.8".bytes());
    try set_java_system_property(context, vm, properties, "java.specification.vendor".bytes(), "Oracle Corporation".bytes());
    try set_java_system_property(context, vm, properties, "java.vendor".bytes(), "Oracle Corporation".bytes());
    try set_java_system_property(context, vm, properties, "java.vendor.url".bytes(), "http://java.oracle.com/".bytes());
    try set_java_system_property(context, vm, properties, "java.vendor.url.bug".bytes(), "http://bugreport.sun.com/bugreport/".bytes());
    try set_java_system_property(context, vm, properties, "java.vm.name".bytes(), "Zava 64-Bit VM".bytes());
    try set_java_system_property(context, vm, properties, "java.vm.version".bytes(), "1.0.0".bytes());
    try set_java_system_property(context, vm, properties, "java.vm.vendor".bytes(), "Chao Yang".bytes());
    try set_java_system_property(context, vm, properties, "java.vm.info".bytes(), "mixed mode".bytes());
    try set_java_system_property(context, vm, properties, "java.vm.specification.name".bytes(), "Java Virtual Machine Specification".bytes());
    try set_java_system_property(context, vm, properties, "java.vm.specification.version".bytes(), "1.8".bytes());
    try set_java_system_property(context, vm, properties, "java.vm.specification.vendor".bytes(), "Oracle Corporation".bytes());
    try set_java_system_property(context, vm, properties, "java.runtime.name".bytes(), "Java(TM) SE Runtime Environment".bytes());
    try set_java_system_property(context, vm, properties, "java.runtime.version".bytes(), "1.8.0_152-ea-b05".bytes());
    try set_java_system_property(context, vm, properties, "java.class.version".bytes(), "52.0".bytes());
    try set_java_system_property(context, vm, properties, "java.class.path".bytes(), "src/classes;jdk/classes".bytes());
    try set_java_system_property(context, vm, properties, "java.io.tmpdir".bytes(), "/var/tmp".bytes());
    try set_java_system_property(context, vm, properties, "java.library.path".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "java.ext.dirs".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "java.endorsed.dirs".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "java.awt.graphicsenv".bytes(), "sun.awt.CGraphicsEnvironment".bytes());
    try set_java_system_property(context, vm, properties, "java.awt.printerjob".bytes(), "sun.lwawt.macosx.CPrinterJob".bytes());
    try set_java_system_property(context, vm, properties, "awt.toolkit".bytes(), "sun.lwawt.macosx.LWCToolkit".bytes());
    try set_java_system_property(context, vm, properties, "path.separator".bytes(), ":".bytes());
    const newline: [1]u8 = [10];
    try set_java_system_property(context, vm, properties, "line.separator".bytes(), newline[..]);
    try set_java_system_property(context, vm, properties, "file.separator".bytes(), "/".bytes());
    try set_java_system_property(context, vm, properties, "file.encoding".bytes(), "UTF-8".bytes());
    try set_java_system_property(context, vm, properties, "file.encoding.pkg".bytes(), "sun.io".bytes());
    try set_java_system_property(context, vm, properties, "sun.stdout.encoding".bytes(), "UTF-8".bytes());
    try set_java_system_property(context, vm, properties, "sun.stderr.encoding".bytes(), "UTF-8".bytes());
    try set_java_system_property(context, vm, properties, "os.name".bytes(), "Mac OS X".bytes());
    try set_java_system_property(context, vm, properties, "os.arch".bytes(), "x86_64".bytes());
    try set_java_system_property(context, vm, properties, "os.version".bytes(), "10.12.5".bytes());
    try set_java_system_property(context, vm, properties, "user.name".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "user.home".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "user.country".bytes(), "US".bytes());
    try set_java_system_property(context, vm, properties, "user.language".bytes(), "en".bytes());
    try set_java_system_property(context, vm, properties, "user.timezone".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "user.dir".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "sun.java.launcher".bytes(), "SUN_STANDARD".bytes());
    try set_java_system_property(context, vm, properties, "sun.java.command".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "sun.boot.library.path".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "sun.boot.class.path".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "sun.os.patch.level".bytes(), "unknown".bytes());
    try set_java_system_property(context, vm, properties, "sun.jnu.encoding".bytes(), "UTF-8".bytes());
    try set_java_system_property(context, vm, properties, "sun.management.compiler".bytes(), "HotSpot 64-Bit Tiered Compilers".bytes());
    try set_java_system_property(context, vm, properties, "sun.arch.data.model".bytes(), "64".bytes());
    try set_java_system_property(context, vm, properties, "sun.cpu.endian".bytes(), "little".bytes());
    try set_java_system_property(context, vm, properties, "sun.io.unicode.encoding".bytes(), "UnicodeBig".bytes());
    try set_java_system_property(context, vm, properties, "sun.cpu.isalist".bytes(), "".bytes());
    try set_java_system_property(context, vm, properties, "http.nonProxyHosts".bytes(), "local|*.local|169.254/16|*.169.254/16".bytes());
    try set_java_system_property(context, vm, properties, "ftp.nonProxyHosts".bytes(), "local|*.local|169.254/16|*.169.254/16".bytes());
    try set_java_system_property(context, vm, properties, "socksNonProxyHosts".bytes(), "local|*.local|169.254/16|*.169.254/16".bytes());
    try set_java_system_property(context, vm, properties, "gopherProxySet".bytes(), "false".bytes());
    const out: Value = .ref_value(properties);
    return .ok(out);
}

fn invoke_static(context: &Context, vm: &VM): result<void, InstructionError> {
    const resolved = try resolve_static_method(context, vm, context.read_u2());
    var classes = vm.method_area.classes[..];
    var class = &classes[resolved.class_index];
    var methods = class.methods[..];
    var method = &methods[resolved.method_index];
    if method.is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    const argument_count = try method_argument_count(method.descriptor);
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }
    if method.name != "<clinit>" {
        try initialize_static_class(context, vm, resolved.class_index);
    }
    var active_classes = vm.method_area.classes[..];
    const active_class = &active_classes[resolved.class_index];
    var active_methods = active_class.methods[..];
    const active_method = &active_methods[resolved.method_index];

    if active_method.is_native() {
        const native_args = native_arguments(arguments);
        const result = execute_native_method(context, vm, resolved.class_index, resolved.method_index, none, native_args);
        switch result {
            case .ok(value) {
                if value is actual {
                    context.frame.push(actual);
                }
                return .ok();
            }
            case .err(error_value) {
                return .err(error_value);
            }
        }
    } else {
        var frame = new_frame(resolved.class_index, resolved.method_index, active_method.max_locals, active_method.max_stack);
        var local_index: u16 = 0;
        var argument_index = arguments.len();
        while argument_index > 0 {
            argument_index = argument_index - 1;
            const value = arguments[argument_index];
            frame.store(local_index, value);
            local_index = local_index + value_local_width(value);
        }
        drop arguments;

        const result = try execute_child_method_frame(context, vm, resolved.class_index, resolved.method_index, frame, context.constant_pool);
        return apply_method_result(context, vm, result);
    }
}

fn invoke_special(context: &Context, vm: &VM): result<void, InstructionError> {
    const resolved = try resolve_instance_method(context, vm, context.read_u2());
    var classes = vm.method_area.classes[..];
    const class = &classes[resolved.class_index];
    var methods = class.methods[..];
    const method = &methods[resolved.method_index];
    if method.is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    const argument_count = try method_argument_count(method.descriptor);
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }

    const receiver = expect_ref(context.frame.pop());
    if receiver.is_null() {
        return .err(InstructionError.invalid_constant);
    }

    if method.is_native() {
        const native_args = native_arguments(arguments);
        const result = execute_native_method(context, vm, resolved.class_index, resolved.method_index, receiver, native_args);
        switch result {
            case .ok(value) {
                if value is actual {
                    context.frame.push(actual);
                }
                return .ok();
            }
            case .err(error_value) {
                return .err(error_value);
            }
        }
    } else {
        var frame = new_frame(resolved.class_index, resolved.method_index, method.max_locals, method.max_stack);
        frame.store(0, .ref_value(receiver));
        var local_index: u16 = 1;
        var argument_index = arguments.len();
        while argument_index > 0 {
            argument_index = argument_index - 1;
            const value = arguments[argument_index];
            frame.store(local_index, value);
            local_index = local_index + value_local_width(value);
        }
        drop arguments;

        const result = try execute_child_method_frame(context, vm, resolved.class_index, resolved.method_index, frame, context.constant_pool);
        return apply_method_result(context, vm, result);
    }
}

fn invoke_virtual(context: &Context, vm: &VM): result<void, InstructionError> {
    const declared = try resolve_instance_method(context, vm, context.read_u2());
    var classes = vm.method_area.classes[..];
    const declared_class = &classes[declared.class_index];
    var declared_methods = declared_class.methods[..];
    const declared_method = &declared_methods[declared.method_index];
    const argument_count = try method_argument_count(declared_method.descriptor);
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }

    const receiver = expect_ref(context.frame.pop());
    if receiver.is_null() {
        return .err(InstructionError.invalid_constant);
    }
    const target_name = copy declared_method.name;
    const target_descriptor = copy declared_method.descriptor;
    if vm.heap.array_class_index(receiver) is array_class_index {
        if target_name == "clone" and target_descriptor == "()Ljava/lang/Object;" {
            var component_descriptor = "Ljava/lang/Object;".bytes();
            if array_class_index < classes.len() {
                const array_class = &classes[array_class_index];
                if array_class.is_array {
                    if vm.heap.array_length(receiver) is length {
                        const clone = vm.heap.allocate_array(array_class_index, array_class.component_type.bytes(), length);
                        var element_index: usize = 0;
                        while element_index < length {
                            if vm.heap.get_element(receiver, element_index) is value {
                                const ignored_set = vm.heap.set_element(clone, element_index, value);
                            }
                            element_index = element_index + 1;
                        }
                        context.frame.push(.ref_value(clone));
                        return .ok();
                    }
                }
            }
            if vm.heap.array_length(receiver) is length {
                const clone = vm.heap.allocate_array(array_class_index, component_descriptor, length);
                var element_index: usize = 0;
                while element_index < length {
                    if vm.heap.get_element(receiver, element_index) is value {
                        const ignored_set = vm.heap.set_element(clone, element_index, value);
                    }
                    element_index = element_index + 1;
                }
                context.frame.push(.ref_value(clone));
                return .ok();
            }
        }
        if target_name == "getClass" and target_descriptor == "()Ljava/lang/Class;" {
            const native_args: List<Value> = [];
            const result = execute_native_method(context, vm, declared.class_index, declared.method_index, receiver, native_args);
            switch result {
                case .ok(value) {
                    if value is actual {
                        context.frame.push(actual);
                    }
                    return .ok();
                }
                case .err(error_value) {
                    return .err(error_value);
                }
            }
        }
    }
    var receiver_class_index: usize = 0;
    if vm.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    const target = try find_instance_method_by_name_in_hierarchy(context, vm, receiver_class_index, copy target_name, copy target_descriptor);
    const target_class = &classes[target.class_index];
    var target_methods = target_class.methods[..];
    const target_method = &target_methods[target.method_index];
    if target_method.is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    if target_method.is_native() {
        const native_args = native_arguments(arguments);
        const result = execute_native_method(context, vm, target.class_index, target.method_index, receiver, native_args);
        switch result {
            case .ok(value) {
                if value is actual {
                    context.frame.push(actual);
                }
                return .ok();
            }
            case .err(error_value) {
                return .err(error_value);
            }
        }
    } else {
        var frame = new_frame(target.class_index, target.method_index, target_method.max_locals, target_method.max_stack);
        frame.store(0, .ref_value(receiver));
        var local_index: u16 = 1;
        var argument_index = arguments.len();
        while argument_index > 0 {
            argument_index = argument_index - 1;
            const value = arguments[argument_index];
            frame.store(local_index, value);
            local_index = local_index + value_local_width(value);
        }
        drop arguments;

        const result = try execute_child_method_frame(context, vm, target.class_index, target.method_index, frame, context.constant_pool);
        return apply_method_result(context, vm, result);
    }
}

fn invoke_interface(context: &Context, vm: &VM): result<void, InstructionError> {
    const declared = try resolve_interface_method(context, vm, context.read_u2());
    const count = context.read_u1();
    const zero = context.read_u1();
    if count == 0 or zero != 0 {
        return .err(InstructionError.invalid_constant);
    }

    var classes = vm.method_area.classes[..];
    const declared_class = &classes[declared.class_index];
    var declared_methods = declared_class.methods[..];
    const declared_method = &declared_methods[declared.method_index];
    const argument_count = try method_argument_count(declared_method.descriptor);
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }

    const receiver = expect_ref(context.frame.pop());
    if receiver.is_null() {
        return .err(InstructionError.invalid_constant);
    }
    var receiver_class_index: usize = 0;
    if vm.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    const target_name = copy declared_method.name;
    const target_descriptor = copy declared_method.descriptor;
    const target = try find_instance_method_by_name_in_hierarchy(context, vm, receiver_class_index, copy target_name, copy target_descriptor);
    const target_class = &classes[target.class_index];
    var target_methods = target_class.methods[..];
    const target_method = &target_methods[target.method_index];
    if target_method.is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    if target_method.is_native() {
        const native_args = native_arguments(arguments);
        const result = execute_native_method(context, vm, target.class_index, target.method_index, receiver, native_args);
        switch result {
            case .ok(value) {
                if value is actual {
                    context.frame.push(actual);
                }
                return .ok();
            }
            case .err(error_value) {
                return .err(error_value);
            }
        }
    } else {
        var frame = new_frame(target.class_index, target.method_index, target_method.max_locals, target_method.max_stack);
        frame.store(0, .ref_value(receiver));
        var local_index: u16 = 1;
        var argument_index = arguments.len();
        while argument_index > 0 {
            argument_index = argument_index - 1;
            const value = arguments[argument_index];
            frame.store(local_index, value);
            local_index = local_index + value_local_width(value);
        }
        drop arguments;

        const result = try execute_child_method_frame(context, vm, target.class_index, target.method_index, frame, context.constant_pool);
        return apply_method_result(context, vm, result);
    }
}

fn new_(context: &Context, vm: &VM): result<void, InstructionError> {
    const class_index = try find_class_index_by_constant(context, vm, context.read_u2());
    var classes = vm.method_area.classes[..];
    try initialize_static_class(context, vm, class_index);
    const reference = vm.heap.allocate_object_with_hierarchy(class_index, classes);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn getstatic(context: &Context, vm: &VM): result<void, InstructionError> {
    const field = try resolve_field(context, vm, context.read_u2());
    if !field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const class_index = try vm.resolve_class_index(copy field.class_name);
    try initialize_static_class(context, vm, class_index);
    const slot = field.slot as usize;
    var classes = vm.method_area.classes[..];
    var class = &classes[class_index];
    if slot >= class.static_vars.len() {
        return .err(InstructionError.invalid_constant);
    }
    const value = class.static_vars[slot];
    drop field;
    context.frame.push(value);
    return .ok();
}

fn initialize_static_class(context: &Context, vm: &VM, class_index: usize): result<void, InstructionError> {
    if context.runtime is runtime {
        var decision = runtime.initializers.begin(class_index);
        while decision == InitializationDecision.waiting {
            if !runtime.pause(1) {
                return .err(InstructionError.invalid_constant);
            }
            decision = runtime.initializers.begin(class_index);
        }
        if decision == InitializationDecision.failed {
            return .err(InstructionError.invalid_constant);
        }
        if decision == InitializationDecision.complete or decision == InitializationDecision.recursive {
            return .ok();
        }
        const result = initialize_static_class_body(context, vm, class_index);
        switch result {
            case .ok {
                runtime.initializers.finish(class_index, true);
            }
            case .err {
                runtime.initializers.finish(class_index, false);
            }
        }
        return result;
    }
    return initialize_static_class_body(context, vm, class_index);
}

fn initialize_static_class_body(context: &Context, vm: &VM, class_index: usize): result<void, InstructionError> {
    if class_index >= vm.method_area.classes.len() {
        return .err(InstructionError.invalid_constant);
    }
    var classes = vm.method_area.classes[..];
    const class = &classes[class_index];
    if class.linked {
        return .ok();
    }
    const class_name = copy class.name;
    if class.super_class.len() > 0 {
        if find_loaded_class_index(classes, copy class.super_class) is super_index {
            try initialize_static_class(context, vm, super_index);
        }
    }
    var active_classes = vm.method_area.classes[..];
    const active_class = &active_classes[class_index];
    active_class.linked = true;
    if active_class.method_index("<clinit>", "()V", true) is clinit_index_value {
        const clinit_index = clinit_index_value as usize;
        var frame = new_frame(class_index, clinit_index, active_class.methods[clinit_index].max_locals, active_class.methods[clinit_index].max_stack);
        const result = try execute_child_method_frame(context, vm, class_index, clinit_index, frame, active_class.constant_pool[..]);
        switch result {
            case .return_value {}
            case .exception {
                return .err(InstructionError.invalid_constant);
            }
        }
    }
    if class_name == "java/lang/System" {
        try initialize_system_static_fields(context, vm, class_index);
    }
    if class_name == "sun/misc/VM" {
        try initialize_vm_static_fields(context, vm, class_index);
    }
    return .ok();
}

fn initialize_system_static_fields(context: &Context, vm: &VM, system_index: usize): result<void, InstructionError> {
    var classes = vm.method_area.classes[..];
    const out_field_index = classes[system_index].field_index("out", "Ljava/io/PrintStream;", true);
    const err_field_index = classes[system_index].field_index("err", "Ljava/io/PrintStream;", true);
    if out_field_index == none and err_field_index == none {
        return .ok();
    }

    const print_stream_index = try vm.resolve_class_index("java/io/PrintStream");
    classes = vm.method_area.classes[..];
    const reference = vm.heap.allocate_object_with_hierarchy(print_stream_index, classes);
    const output_stream_index = try vm.resolve_class_index("java/io/OutputStream");
    classes = vm.method_area.classes[..];
    const output_reference = vm.heap.allocate_object_with_hierarchy(output_stream_index, classes);
    const ignored_set = vm.heap.set_field(reference, 0, .ref_value(output_reference));
    if out_field_index is field_index_value {
        var fields = classes[system_index].fields[..];
        const field = &fields[field_index_value as usize];
        classes[system_index].static_vars[field.slot as usize] = .ref_value(reference);
    }
    if err_field_index is field_index_value {
        var fields = classes[system_index].fields[..];
        const field = &fields[field_index_value as usize];
        classes[system_index].static_vars[field.slot as usize] = .ref_value(reference);
    }
    return .ok();
}

fn initialize_vm_static_fields(context: &Context, vm: &VM, vm_index: usize): result<void, InstructionError> {
    var classes = vm.method_area.classes[..];
    var vm_class = &classes[vm_index];
    if vm_class.field_index("savedProps", "Ljava/util/Properties;", true) is field_index_value {
        var fields = vm_class.fields[..];
        const field = &fields[field_index_value as usize];
        switch vm_class.static_vars[field.slot as usize] {
            case .ref_value(props_reference) {
                if props_reference.is_null() {
                    return .ok();
                }
                if vm.heap.object_class_index(props_reference) is props_class_index {
                    const count_field = try find_field_by_name_in_hierarchy(context, vm, props_class_index, "count", "I", false);
                    if field_runtime_slot(vm, props_reference, count_field) is count_slot {
                        const ignored_set = vm.heap.set_field(props_reference, count_slot, .int_value(1));
                    }
                }
            } else {
                return .ok();
            }
        }
    }
    return .ok();
}

fn putstatic(context: &Context, vm: &VM): result<void, InstructionError> {
    const field = try resolve_field(context, vm, context.read_u2());
    if !field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const class_index = try vm.resolve_class_index(copy field.class_name);
    try initialize_static_class(context, vm, class_index);
    const slot = field.slot as usize;
    var classes = vm.method_area.classes[..];
    var class = &classes[class_index];
    if slot >= class.static_vars.len() {
        return .err(InstructionError.invalid_constant);
    }
    class.static_vars[slot] = context.frame.pop();
    drop field;
    return .ok();
}

fn getfield(context: &Context, vm: &VM): result<void, InstructionError> {
    const field = try resolve_field(context, vm, context.read_u2());
    if field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    var found = false;
    var out: Value = .int_value(0);
    if field_runtime_slot(vm, reference, field) is slot {
        if vm.heap.get_field(reference, slot) is value {
            out = value;
            found = true;
        }
    }
    drop field;
    if found {
        context.frame.push(out);
        return .ok();
    }
    return .err(InstructionError.invalid_constant);
}

fn putfield(context: &Context, vm: &VM): result<void, InstructionError> {
    const field = try resolve_field(context, vm, context.read_u2());
    if field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const value = context.frame.pop();
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    var stored = false;
    if field_runtime_slot(vm, reference, field) is slot {
        if vm.heap.set_field(reference, slot, value) {
            stored = true;
        }
    }
    drop field;
    if stored {
        return .ok();
    }
    return .err(InstructionError.invalid_constant);
}

fn athrow(context: &Context, vm: &VM): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if !(try dispatch_exception(context, vm, reference)) {
        context.frame.throw_exception(reference);
    }
    return .ok();
}

fn newarray(context: &Context, vm: &VM): result<void, InstructionError> {
    const count = expect_int(context.frame.pop());
    if count < 0 {
        assert(false);
    }

    const atype = context.read_u1();
    var descriptor = "I";
    var valid = true;
    if atype == 4 {
        descriptor = "Z";
    }
    if atype == 5 {
        descriptor = "C";
    }
    if atype == 6 {
        descriptor = "F";
    }
    if atype == 7 {
        descriptor = "D";
    }
    if atype == 8 {
        descriptor = "B";
    }
    if atype == 9 {
        descriptor = "S";
    }
    if atype == 10 {
        descriptor = "I";
    }
    if atype == 11 {
        descriptor = "J";
    }
    if atype < 4 or atype > 11 {
        valid = false;
    }
    if !valid {
        assert(false);
    }

    const reference = vm.heap.allocate_array(0, descriptor.bytes(), count as usize);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn anewarray(context: &Context, vm: &VM): result<void, InstructionError> {
    const class_name = try constant_class_name(context, context.read_u2());
    const count = expect_int(context.frame.pop());
    if count < 0 {
        assert(false);
    }

    const descriptor = reference_array_component_descriptor(class_name);
    const array_descriptor = reference_array_descriptor(descriptor);
    var array_class_index: usize = 0;
    switch vm.resolve_class_index(copy array_descriptor) {
        case .ok(found_index) {
            array_class_index = found_index;
        }
        case .err {}
    }
    const reference = vm.heap.allocate_array(array_class_index, descriptor.bytes(), count as usize);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn checkcast(context: &Context, vm: &VM): result<void, InstructionError> {
    const expected_class_index = try find_class_index_by_constant(context, vm, context.read_u2());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        context.frame.push(.ref_value(reference));
        return .ok();
    }
    var classes = vm.method_area.classes[..];
    if vm.heap.object_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            context.frame.push(.ref_value(reference));
            return .ok();
        }
    }
    if vm.heap.array_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            context.frame.push(.ref_value(reference));
            return .ok();
        }
        if actual_class_index == 0 and expected_class_index < classes.len() and classes[expected_class_index].is_array {
            context.frame.push(.ref_value(reference));
            return .ok();
        }
    }
    return .err(InstructionError.invalid_constant);
}

fn instanceof(context: &Context, vm: &VM): result<void, InstructionError> {
    const expected_class_index = try find_class_index_by_constant(context, vm, context.read_u2());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        push_int(context, 0);
        return .ok();
    }
    var classes = vm.method_area.classes[..];
    if vm.heap.object_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            push_int(context, 1);
            return .ok();
        }
    }
    if vm.heap.array_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            push_int(context, 1);
            return .ok();
        }
        if actual_class_index == 0 and expected_class_index < classes.len() and classes[expected_class_index].is_array {
            push_int(context, 1);
            return .ok();
        }
    }
    push_int(context, 0);
    return .ok();
}

fn monitorenter(context: &Context, vm: &VM): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    return enter_monitor(context.runtime, vm, reference);
}

fn monitorexit(context: &Context, vm: &VM): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    if !vm.heap.monitor_exit(reference) {
        return .err(InstructionError.invalid_constant);
    }
    return .ok();
}

fn allocate_multi_array(context: &Context, vm: &VM, descriptor: string, counts: []i32, depth: usize): Reference {
    const count = counts[counts.len() - 1 - depth];
    if count < 0 {
        assert(false);
    }
    const component_descriptor = array_component_descriptor(descriptor);
    const reference = vm.heap.allocate_array(0, component_descriptor.bytes(), count as usize);
    if depth + 1 < counts.len() {
        var index: usize = 0;
        while index < count as usize {
            const nested = allocate_multi_array(context, vm, component_descriptor, counts, depth + 1);
            if !vm.heap.set_element(reference, index, .ref_value(nested)) {
                assert(false);
            }
            index = index + 1;
        }
    }
    return reference;
}

fn multianewarray(context: &Context, vm: &VM): result<void, InstructionError> {
    const descriptor = try constant_class_name(context, context.read_u2());
    const dimensions = context.read_u1();
    if dimensions == 0 {
        return .err(InstructionError.invalid_constant);
    }

    var counts = [: dimensions as usize]i32;
    var index: u8 = 0;
    while index < dimensions {
        const count = expect_int(context.frame.pop());
        if count < 0 {
            assert(false);
        }
        counts.push(count);
        index = index + 1;
    }

    const reference = allocate_multi_array(context, vm, descriptor, counts[..], 0);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn arraylength(context: &Context, vm: &VM): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if vm.heap.array_length(reference) is length {
        push_int(context, length as i32);
        return .ok();
    }
    assert(false);
    return .ok();
}

fn wide(context: &Context): result<void, InstructionError> {
    const modified_opcode = context.read_u1();
    const index = context.read_u2();
    var handled = false;
    var advance = true;

    if modified_opcode == 21 {
        load_int(context, index);
        handled = true;
    }
    if modified_opcode == 22 {
        load_long(context, index);
        handled = true;
    }
    if modified_opcode == 23 {
        load_float(context, index);
        handled = true;
    }
    if modified_opcode == 24 {
        load_double(context, index);
        handled = true;
    }
    if modified_opcode == 25 {
        load_ref(context, index);
        handled = true;
    }
    if modified_opcode == 54 {
        store_int(context, index);
        handled = true;
    }
    if modified_opcode == 55 {
        store_long(context, index);
        handled = true;
    }
    if modified_opcode == 56 {
        store_float(context, index);
        handled = true;
    }
    if modified_opcode == 57 {
        store_double(context, index);
        handled = true;
    }
    if modified_opcode == 58 {
        store_ref_like(context, index);
        handled = true;
    }
    if modified_opcode == 132 {
        const increment = context.read_i2() as i32;
        const value = expect_int(context.frame.load(index));
        context.frame.store(index, .int_value(value +% increment));
        handled = true;
    }
    if modified_opcode == 169 {
        context.frame.pc = expect_return_address(context.frame.load(index));
        handled = true;
        advance = false;
    }
    if !handled {
        assert(false);
    }

    if advance {
        context.frame.next(context.frame.offset as i32);
    }
    return .ok();
}

fn ifnull(context: &Context): result<void, InstructionError> {
    branch(context, expect_ref(context.frame.pop()).is_null());
    return .ok();
}

fn ifnonnull(context: &Context): result<void, InstructionError> {
    branch(context, expect_ref(context.frame.pop()).non_null());
    return .ok();
}

const registry: [256]Instruction = [{
        opcode: .nop,
        length: 1,
        execute: execute_frame_registered,
        local_execute: nop,
        is_local: true
    }, // 0x00 nop
    {
        opcode: .aconst_null,
        length: 1,
        execute: execute_frame_registered,
        local_execute: aconst_null,
        is_local: true
    }, // 0x01 aconst_null
    {
        opcode: .iconst_m1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iconst_m1,
        is_local: true
    }, // 0x02 iconst_m1
    {
        opcode: .iconst_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iconst_0,
        is_local: true
    }, // 0x03 iconst_0
    {
        opcode: .iconst_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iconst_1,
        is_local: true
    }, // 0x04 iconst_1
    {
        opcode: .iconst_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iconst_2,
        is_local: true
    }, // 0x05 iconst_2
    {
        opcode: .iconst_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iconst_3,
        is_local: true
    }, // 0x06 iconst_3
    {
        opcode: .iconst_4,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iconst_4,
        is_local: true
    }, // 0x07 iconst_4
    {
        opcode: .iconst_5,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iconst_5,
        is_local: true
    }, // 0x08 iconst_5
    {
        opcode: .lconst_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lconst_0,
        is_local: true
    }, // 0x09 lconst_0
    {
        opcode: .lconst_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lconst_1,
        is_local: true
    }, // 0x0A lconst_1
    {
        opcode: .fconst_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fconst_0,
        is_local: true
    }, // 0x0B fconst_0
    {
        opcode: .fconst_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fconst_1,
        is_local: true
    }, // 0x0C fconst_1
    {
        opcode: .fconst_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fconst_2,
        is_local: true
    }, // 0x0D fconst_2
    {
        opcode: .dconst_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dconst_0,
        is_local: true
    }, // 0x0E dconst_0
    {
        opcode: .dconst_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dconst_1,
        is_local: true
    }, // 0x0F dconst_1
    {
        opcode: .bipush,
        length: 2,
        execute: execute_frame_registered,
        local_execute: bipush,
        is_local: true
    }, // 0x10 bipush
    {
        opcode: .sipush,
        length: 3,
        execute: execute_frame_registered,
        local_execute: sipush,
        is_local: true
    }, // 0x11 sipush
    {
        opcode: .ldc,
        length: 2,
        execute: ldc,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x12 ldc
    {
        opcode: .ldc_w,
        length: 3,
        execute: ldc_w,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x13 ldc_w
    {
        opcode: .ldc2_w,
        length: 3,
        execute: ldc2_w,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x14 ldc2_w
    {
        opcode: .iload,
        length: 2,
        execute: execute_frame_registered,
        local_execute: iload,
        is_local: true
    }, // 0x15 iload
    {
        opcode: .lload,
        length: 2,
        execute: execute_frame_registered,
        local_execute: lload,
        is_local: true
    }, // 0x16 lload
    {
        opcode: .fload,
        length: 2,
        execute: execute_frame_registered,
        local_execute: fload,
        is_local: true
    }, // 0x17 fload
    {
        opcode: .dload,
        length: 2,
        execute: execute_frame_registered,
        local_execute: dload,
        is_local: true
    }, // 0x18 dload
    {
        opcode: .aload,
        length: 2,
        execute: execute_frame_registered,
        local_execute: aload,
        is_local: true
    }, // 0x19 aload
    {
        opcode: .iload_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iload_0,
        is_local: true
    }, // 0x1A iload_0
    {
        opcode: .iload_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iload_1,
        is_local: true
    }, // 0x1B iload_1
    {
        opcode: .iload_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iload_2,
        is_local: true
    }, // 0x1C iload_2
    {
        opcode: .iload_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iload_3,
        is_local: true
    }, // 0x1D iload_3
    {
        opcode: .lload_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lload_0,
        is_local: true
    }, // 0x1E lload_0
    {
        opcode: .lload_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lload_1,
        is_local: true
    }, // 0x1F lload_1
    {
        opcode: .lload_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lload_2,
        is_local: true
    }, // 0x20 lload_2
    {
        opcode: .lload_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lload_3,
        is_local: true
    }, // 0x21 lload_3
    {
        opcode: .fload_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fload_0,
        is_local: true
    }, // 0x22 fload_0
    {
        opcode: .fload_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fload_1,
        is_local: true
    }, // 0x23 fload_1
    {
        opcode: .fload_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fload_2,
        is_local: true
    }, // 0x24 fload_2
    {
        opcode: .fload_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fload_3,
        is_local: true
    }, // 0x25 fload_3
    {
        opcode: .dload_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dload_0,
        is_local: true
    }, // 0x26 dload_0
    {
        opcode: .dload_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dload_1,
        is_local: true
    }, // 0x27 dload_1
    {
        opcode: .dload_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dload_2,
        is_local: true
    }, // 0x28 dload_2
    {
        opcode: .dload_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dload_3,
        is_local: true
    }, // 0x29 dload_3
    {
        opcode: .aload_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: aload_0,
        is_local: true
    }, // 0x2A aload_0
    {
        opcode: .aload_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: aload_1,
        is_local: true
    }, // 0x2B aload_1
    {
        opcode: .aload_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: aload_2,
        is_local: true
    }, // 0x2C aload_2
    {
        opcode: .aload_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: aload_3,
        is_local: true
    }, // 0x2D aload_3
    {
        opcode: .iaload,
        length: 1,
        execute: iaload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x2E iaload
    {
        opcode: .laload,
        length: 1,
        execute: laload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x2F laload
    {
        opcode: .faload,
        length: 1,
        execute: faload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x30 faload
    {
        opcode: .daload,
        length: 1,
        execute: daload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x31 daload
    {
        opcode: .aaload,
        length: 1,
        execute: aaload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x32 aaload
    {
        opcode: .baload,
        length: 1,
        execute: baload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x33 baload
    {
        opcode: .caload,
        length: 1,
        execute: caload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x34 caload
    {
        opcode: .saload,
        length: 1,
        execute: saload,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x35 saload
    {
        opcode: .istore,
        length: 2,
        execute: execute_frame_registered,
        local_execute: istore,
        is_local: true
    }, // 0x36 istore
    {
        opcode: .lstore,
        length: 2,
        execute: execute_frame_registered,
        local_execute: lstore,
        is_local: true
    }, // 0x37 lstore
    {
        opcode: .fstore,
        length: 2,
        execute: execute_frame_registered,
        local_execute: fstore,
        is_local: true
    }, // 0x38 fstore
    {
        opcode: .dstore,
        length: 2,
        execute: execute_frame_registered,
        local_execute: dstore,
        is_local: true
    }, // 0x39 dstore
    {
        opcode: .astore,
        length: 2,
        execute: execute_frame_registered,
        local_execute: astore,
        is_local: true
    }, // 0x3A astore
    {
        opcode: .istore_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: istore_0,
        is_local: true
    }, // 0x3B istore_0
    {
        opcode: .istore_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: istore_1,
        is_local: true
    }, // 0x3C istore_1
    {
        opcode: .istore_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: istore_2,
        is_local: true
    }, // 0x3D istore_2
    {
        opcode: .istore_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: istore_3,
        is_local: true
    }, // 0x3E istore_3
    {
        opcode: .lstore_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lstore_0,
        is_local: true
    }, // 0x3F lstore_0
    {
        opcode: .lstore_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lstore_1,
        is_local: true
    }, // 0x40 lstore_1
    {
        opcode: .lstore_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lstore_2,
        is_local: true
    }, // 0x41 lstore_2
    {
        opcode: .lstore_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lstore_3,
        is_local: true
    }, // 0x42 lstore_3
    {
        opcode: .fstore_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fstore_0,
        is_local: true
    }, // 0x43 fstore_0
    {
        opcode: .fstore_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fstore_1,
        is_local: true
    }, // 0x44 fstore_1
    {
        opcode: .fstore_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fstore_2,
        is_local: true
    }, // 0x45 fstore_2
    {
        opcode: .fstore_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fstore_3,
        is_local: true
    }, // 0x46 fstore_3
    {
        opcode: .dstore_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dstore_0,
        is_local: true
    }, // 0x47 dstore_0
    {
        opcode: .dstore_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dstore_1,
        is_local: true
    }, // 0x48 dstore_1
    {
        opcode: .dstore_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dstore_2,
        is_local: true
    }, // 0x49 dstore_2
    {
        opcode: .dstore_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dstore_3,
        is_local: true
    }, // 0x4A dstore_3
    {
        opcode: .astore_0,
        length: 1,
        execute: execute_frame_registered,
        local_execute: astore_0,
        is_local: true
    }, // 0x4B astore_0
    {
        opcode: .astore_1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: astore_1,
        is_local: true
    }, // 0x4C astore_1
    {
        opcode: .astore_2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: astore_2,
        is_local: true
    }, // 0x4D astore_2
    {
        opcode: .astore_3,
        length: 1,
        execute: execute_frame_registered,
        local_execute: astore_3,
        is_local: true
    }, // 0x4E astore_3
    {
        opcode: .iastore,
        length: 1,
        execute: iastore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x4F iastore
    {
        opcode: .lastore,
        length: 1,
        execute: lastore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x50 lastore
    {
        opcode: .fastore,
        length: 1,
        execute: fastore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x51 fastore
    {
        opcode: .dastore,
        length: 1,
        execute: dastore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x52 dastore
    {
        opcode: .aastore,
        length: 1,
        execute: aastore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x53 aastore
    {
        opcode: .bastore,
        length: 1,
        execute: bastore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x54 bastore
    {
        opcode: .castore,
        length: 1,
        execute: castore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x55 castore
    {
        opcode: .sastore,
        length: 1,
        execute: sastore,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x56 sastore
    {
        opcode: .pop,
        length: 1,
        execute: execute_frame_registered,
        local_execute: pop,
        is_local: true
    }, // 0x57 pop
    {
        opcode: .pop2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: pop2,
        is_local: true
    }, // 0x58 pop2
    {
        opcode: .dup,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dup,
        is_local: true
    }, // 0x59 dup
    {
        opcode: .dup_x1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dup_x1,
        is_local: true
    }, // 0x5A dup_x1
    {
        opcode: .dup_x2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dup_x2,
        is_local: true
    }, // 0x5B dup_x2
    {
        opcode: .dup2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dup2,
        is_local: true
    }, // 0x5C dup2
    {
        opcode: .dup2_x1,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dup2_x1,
        is_local: true
    }, // 0x5D dup2_x1
    {
        opcode: .dup2_x2,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dup2_x2,
        is_local: true
    }, // 0x5E dup2_x2
    {
        opcode: .swap,
        length: 1,
        execute: execute_frame_registered,
        local_execute: swap,
        is_local: true
    }, // 0x5F swap
    {
        opcode: .iadd,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iadd,
        is_local: true
    }, // 0x60 iadd
    {
        opcode: .ladd,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ladd,
        is_local: true
    }, // 0x61 ladd
    {
        opcode: .fadd,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fadd,
        is_local: true
    }, // 0x62 fadd
    {
        opcode: .dadd,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dadd,
        is_local: true
    }, // 0x63 dadd
    {
        opcode: .isub,
        length: 1,
        execute: execute_frame_registered,
        local_execute: isub,
        is_local: true
    }, // 0x64 isub
    {
        opcode: .lsub,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lsub,
        is_local: true
    }, // 0x65 lsub
    {
        opcode: .fsub,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fsub,
        is_local: true
    }, // 0x66 fsub
    {
        opcode: .dsub,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dsub,
        is_local: true
    }, // 0x67 dsub
    {
        opcode: .imul,
        length: 1,
        execute: execute_frame_registered,
        local_execute: imul,
        is_local: true
    }, // 0x68 imul
    {
        opcode: .lmul,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lmul,
        is_local: true
    }, // 0x69 lmul
    {
        opcode: .fmul,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fmul,
        is_local: true
    }, // 0x6A fmul
    {
        opcode: .dmul,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dmul,
        is_local: true
    }, // 0x6B dmul
    {
        opcode: .idiv,
        length: 1,
        execute: execute_frame_registered,
        local_execute: idiv,
        is_local: true
    }, // 0x6C idiv
    {
        opcode: .ldiv,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ldiv,
        is_local: true
    }, // 0x6D ldiv
    {
        opcode: .fdiv,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fdiv,
        is_local: true
    }, // 0x6E fdiv
    {
        opcode: .ddiv,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ddiv,
        is_local: true
    }, // 0x6F ddiv
    {
        opcode: .irem,
        length: 1,
        execute: execute_frame_registered,
        local_execute: irem,
        is_local: true
    }, // 0x70 irem
    {
        opcode: .lrem,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lrem,
        is_local: true
    }, // 0x71 lrem
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x72 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0x73 unsupported
    {
        opcode: .ineg,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ineg,
        is_local: true
    }, // 0x74 ineg
    {
        opcode: .lneg,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lneg,
        is_local: true
    }, // 0x75 lneg
    {
        opcode: .fneg,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fneg,
        is_local: true
    }, // 0x76 fneg
    {
        opcode: .dneg,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dneg,
        is_local: true
    }, // 0x77 dneg
    {
        opcode: .ishl,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ishl,
        is_local: true
    }, // 0x78 ishl
    {
        opcode: .lshl,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lshl,
        is_local: true
    }, // 0x79 lshl
    {
        opcode: .ishr,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ishr,
        is_local: true
    }, // 0x7A ishr
    {
        opcode: .lshr,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lshr,
        is_local: true
    }, // 0x7B lshr
    {
        opcode: .iushr,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iushr,
        is_local: true
    }, // 0x7C iushr
    {
        opcode: .lushr,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lushr,
        is_local: true
    }, // 0x7D lushr
    {
        opcode: .iand,
        length: 1,
        execute: execute_frame_registered,
        local_execute: iand,
        is_local: true
    }, // 0x7E iand
    {
        opcode: .land,
        length: 1,
        execute: execute_frame_registered,
        local_execute: land,
        is_local: true
    }, // 0x7F land
    {
        opcode: .ior,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ior,
        is_local: true
    }, // 0x80 ior
    {
        opcode: .lor,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lor,
        is_local: true
    }, // 0x81 lor
    {
        opcode: .ixor,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ixor,
        is_local: true
    }, // 0x82 ixor
    {
        opcode: .lxor,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lxor,
        is_local: true
    }, // 0x83 lxor
    {
        opcode: .iinc,
        length: 3,
        execute: execute_frame_registered,
        local_execute: iinc,
        is_local: true
    }, // 0x84 iinc
    {
        opcode: .i2l,
        length: 1,
        execute: execute_frame_registered,
        local_execute: i2l,
        is_local: true
    }, // 0x85 i2l
    {
        opcode: .i2f,
        length: 1,
        execute: execute_frame_registered,
        local_execute: i2f,
        is_local: true
    }, // 0x86 i2f
    {
        opcode: .i2d,
        length: 1,
        execute: execute_frame_registered,
        local_execute: i2d,
        is_local: true
    }, // 0x87 i2d
    {
        opcode: .l2i,
        length: 1,
        execute: execute_frame_registered,
        local_execute: l2i,
        is_local: true
    }, // 0x88 l2i
    {
        opcode: .l2f,
        length: 1,
        execute: execute_frame_registered,
        local_execute: l2f,
        is_local: true
    }, // 0x89 l2f
    {
        opcode: .l2d,
        length: 1,
        execute: execute_frame_registered,
        local_execute: l2d,
        is_local: true
    }, // 0x8A l2d
    {
        opcode: .f2i,
        length: 1,
        execute: execute_frame_registered,
        local_execute: f2i,
        is_local: true
    }, // 0x8B f2i
    {
        opcode: .f2l,
        length: 1,
        execute: execute_frame_registered,
        local_execute: f2l,
        is_local: true
    }, // 0x8C f2l
    {
        opcode: .f2d,
        length: 1,
        execute: execute_frame_registered,
        local_execute: f2d,
        is_local: true
    }, // 0x8D f2d
    {
        opcode: .d2i,
        length: 1,
        execute: execute_frame_registered,
        local_execute: d2i,
        is_local: true
    }, // 0x8E d2i
    {
        opcode: .d2l,
        length: 1,
        execute: execute_frame_registered,
        local_execute: d2l,
        is_local: true
    }, // 0x8F d2l
    {
        opcode: .d2f,
        length: 1,
        execute: execute_frame_registered,
        local_execute: d2f,
        is_local: true
    }, // 0x90 d2f
    {
        opcode: .i2b,
        length: 1,
        execute: execute_frame_registered,
        local_execute: i2b,
        is_local: true
    }, // 0x91 i2b
    {
        opcode: .i2c,
        length: 1,
        execute: execute_frame_registered,
        local_execute: i2c,
        is_local: true
    }, // 0x92 i2c
    {
        opcode: .i2s,
        length: 1,
        execute: execute_frame_registered,
        local_execute: i2s,
        is_local: true
    }, // 0x93 i2s
    {
        opcode: .lcmp,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lcmp,
        is_local: true
    }, // 0x94 lcmp
    {
        opcode: .fcmpl,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fcmpl,
        is_local: true
    }, // 0x95 fcmpl
    {
        opcode: .fcmpg,
        length: 1,
        execute: execute_frame_registered,
        local_execute: fcmpg,
        is_local: true
    }, // 0x96 fcmpg
    {
        opcode: .dcmpl,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dcmpl,
        is_local: true
    }, // 0x97 dcmpl
    {
        opcode: .dcmpg,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dcmpg,
        is_local: true
    }, // 0x98 dcmpg
    {
        opcode: .ifeq,
        length: 3,
        execute: execute_frame_registered,
        local_execute: ifeq,
        is_local: true
    }, // 0x99 ifeq
    {
        opcode: .ifne,
        length: 3,
        execute: execute_frame_registered,
        local_execute: ifne,
        is_local: true
    }, // 0x9A ifne
    {
        opcode: .iflt,
        length: 3,
        execute: execute_frame_registered,
        local_execute: iflt,
        is_local: true
    }, // 0x9B iflt
    {
        opcode: .ifge,
        length: 3,
        execute: execute_frame_registered,
        local_execute: ifge,
        is_local: true
    }, // 0x9C ifge
    {
        opcode: .ifgt,
        length: 3,
        execute: execute_frame_registered,
        local_execute: ifgt,
        is_local: true
    }, // 0x9D ifgt
    {
        opcode: .ifle,
        length: 3,
        execute: execute_frame_registered,
        local_execute: ifle,
        is_local: true
    }, // 0x9E ifle
    {
        opcode: .if_icmpeq,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_icmpeq,
        is_local: true
    }, // 0x9F if_icmpeq
    {
        opcode: .if_icmpne,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_icmpne,
        is_local: true
    }, // 0xA0 if_icmpne
    {
        opcode: .if_icmplt,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_icmplt,
        is_local: true
    }, // 0xA1 if_icmplt
    {
        opcode: .if_icmpge,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_icmpge,
        is_local: true
    }, // 0xA2 if_icmpge
    {
        opcode: .if_icmpgt,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_icmpgt,
        is_local: true
    }, // 0xA3 if_icmpgt
    {
        opcode: .if_icmple,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_icmple,
        is_local: true
    }, // 0xA4 if_icmple
    {
        opcode: .if_acmpeq,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_acmpeq,
        is_local: true
    }, // 0xA5 if_acmpeq
    {
        opcode: .if_acmpne,
        length: 3,
        execute: execute_frame_registered,
        local_execute: if_acmpne,
        is_local: true
    }, // 0xA6 if_acmpne
    {
        opcode: .goto_,
        length: 3,
        execute: execute_frame_registered,
        local_execute: goto_,
        is_local: true
    }, // 0xA7 goto
    {
        opcode: .jsr,
        length: 3,
        execute: execute_frame_registered,
        local_execute: jsr,
        is_local: true
    }, // 0xA8 jsr
    {
        opcode: .ret,
        length: 2,
        execute: execute_frame_registered,
        local_execute: ret,
        is_local: true
    }, // 0xA9 ret
    {
        opcode: .tableswitch,
        length: 0,
        execute: execute_frame_registered,
        local_execute: tableswitch,
        is_local: true
    }, // 0xAA tableswitch
    {
        opcode: .lookupswitch,
        length: 0,
        execute: execute_frame_registered,
        local_execute: lookupswitch,
        is_local: true
    }, // 0xAB lookupswitch
    {
        opcode: .ireturn,
        length: 1,
        execute: execute_frame_registered,
        local_execute: ireturn,
        is_local: true
    }, // 0xAC ireturn
    {
        opcode: .lreturn,
        length: 1,
        execute: execute_frame_registered,
        local_execute: lreturn,
        is_local: true
    }, // 0xAD lreturn
    {
        opcode: .freturn,
        length: 1,
        execute: execute_frame_registered,
        local_execute: freturn,
        is_local: true
    }, // 0xAE freturn
    {
        opcode: .dreturn,
        length: 1,
        execute: execute_frame_registered,
        local_execute: dreturn,
        is_local: true
    }, // 0xAF dreturn
    {
        opcode: .areturn,
        length: 1,
        execute: execute_frame_registered,
        local_execute: areturn,
        is_local: true
    }, // 0xB0 areturn
    {
        opcode: .return_,
        length: 1,
        execute: execute_frame_registered,
        local_execute: return_,
        is_local: true
    }, // 0xB1 return
    {
        opcode: .getstatic,
        length: 3,
        execute: getstatic,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB2 getstatic
    {
        opcode: .putstatic,
        length: 3,
        execute: putstatic,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB3 putstatic
    {
        opcode: .getfield,
        length: 3,
        execute: getfield,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB4 getfield
    {
        opcode: .putfield,
        length: 3,
        execute: putfield,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB5 putfield
    {
        opcode: .invoke_virtual,
        length: 3,
        execute: invoke_virtual,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB6 invokevirtual
    {
        opcode: .invoke_special,
        length: 3,
        execute: invoke_special,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB7 invokespecial
    {
        opcode: .invoke_static,
        length: 3,
        execute: invoke_static,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB8 invokestatic
    {
        opcode: .invoke_interface,
        length: 5,
        execute: invoke_interface,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xB9 invokeinterface
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xBA unsupported
    {
        opcode: .new_,
        length: 3,
        execute: new_,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xBB new
    {
        opcode: .newarray,
        length: 2,
        execute: newarray,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xBC newarray
    {
        opcode: .anewarray,
        length: 3,
        execute: anewarray,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xBD anewarray
    {
        opcode: .arraylength,
        length: 1,
        execute: arraylength,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xBE arraylength
    {
        opcode: .athrow,
        length: 1,
        execute: athrow,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xBF athrow
    {
        opcode: .checkcast,
        length: 3,
        execute: checkcast,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xC0 checkcast
    {
        opcode: .instanceof,
        length: 3,
        execute: instanceof,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xC1 instanceof
    {
        opcode: .monitorenter,
        length: 1,
        execute: monitorenter,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xC2 monitorenter
    {
        opcode: .monitorexit,
        length: 1,
        execute: monitorexit,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xC3 monitorexit
    {
        opcode: .wide,
        length: 0,
        execute: execute_frame_registered,
        local_execute: wide,
        is_local: true
    }, // 0xC4 wide
    {
        opcode: .multianewarray,
        length: 4,
        execute: multianewarray,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xC5 multianewarray
    {
        opcode: .ifnull,
        length: 3,
        execute: execute_frame_registered,
        local_execute: ifnull,
        is_local: true
    }, // 0xC6 ifnull
    {
        opcode: .ifnonnull,
        length: 3,
        execute: execute_frame_registered,
        local_execute: ifnonnull,
        is_local: true
    }, // 0xC7 ifnonnull
    {
        opcode: .goto_w,
        length: 5,
        execute: execute_frame_registered,
        local_execute: goto_w,
        is_local: true
    }, // 0xC8 goto_w
    {
        opcode: .jsr_w,
        length: 5,
        execute: execute_frame_registered,
        local_execute: jsr_w,
        is_local: true
    }, // 0xC9 jsr_w
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xCA unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xCB unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xCC unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xCD unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xCE unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xCF unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD0 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD1 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD2 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD3 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD4 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD5 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD6 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD7 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD8 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xD9 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xDA unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xDB unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xDC unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xDD unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xDE unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xDF unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE0 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE1 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE2 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE3 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE4 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE5 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE6 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE7 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE8 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xE9 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xEA unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xEB unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xEC unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xED unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xEE unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xEF unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF0 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF1 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF2 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF3 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF4 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF5 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF6 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF7 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF8 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xF9 unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xFA unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xFB unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xFC unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xFD unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xFE unsupported
    {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    }, // 0xFF unsupported
];

pub fn fetch(raw: u8): result<Instruction, InstructionError> {
    const instruction = registry[raw as usize];
    if instruction.opcode == Opcode.unsupported {
        return .err(InstructionError.unsupported_opcode);
    }
    return .ok(instruction);
}

fn execute_frame_unavailable(context: &Context): result<void, InstructionError> {
    return .err(InstructionError.unsupported_opcode);
}

fn execute_frame_registered(context: &Context, vm: &VM): result<void, InstructionError> {
    const instruction = try fetch(context.code[context.frame.pc as usize]);
    if instruction.is_local {
        const execute = instruction.local_execute;
        return execute(context);
    }
    return .err(InstructionError.unsupported_opcode);
}

pub fn execute_frame_next(context: &Context, class_name: string, method_name: string): result<bool, InstructionError> {
    const pc = context.frame.pc;
    switch fetch(context.code[pc as usize]) {
        case .ok(instruction) {
            if instruction.is_local {
                const execute = instruction.local_execute;
                trace_frame_instruction(context, class_name, method_name, instruction);
                try execute(context);
                finish_instruction(context, pc, instruction.length);
                return .ok(true);
            }
        }
        case .err {}
    }
    return .ok(false);
}

pub fn trace_frame_instruction(context: &Context, class_name: string, method_name: string, instruction: Instruction): void {
    if instruction_trace_enabled() {
        print("trace ");
        print(class_name);
        print(".");
        print(method_name);
        print(" pc=");
        print(context.frame.pc as i64);
        print(" ");
        println(opcode_name(instruction.opcode));
    }
}

pub fn finish_instruction(context: &Context, pc: u32, length: u32): void {
    if context.frame.result == none and context.frame.pc == pc {
        context.frame.pc = context.frame.pc + length;
    }
    context.frame.offset = 1;
}

pub fn execute_array_next(context: &Context, class_name: string, method_name: string): result<bool, InstructionError> {
    const pc = context.frame.pc;
    const opcode = context.code[pc as usize];
    if !((opcode >= 46 and opcode <= 53) or (opcode >= 79 and opcode <= 86) or opcode == 190) {
        return .ok(false);
    }
    if context.runtime is runtime {
        trace_frame_instruction(context, class_name, method_name, try fetch(opcode));
        if opcode == 190 {
            const reference = expect_ref(context.frame.pop());
            if runtime.arrays.length(reference) is length {
                push_int(context, length as i32);
            } else {
                assert(false);
            }
        } else {
            var value: Value = .int_value(0);
            if opcode >= 79 {
                value = context.frame.pop();
            }
            const index = expect_int(context.frame.pop());
            const reference = expect_ref(context.frame.pop());
            assert(index >= 0 and reference.non_null());
            if opcode <= 53 {
                if runtime.arrays.get(reference, index as usize) is loaded {
                    if opcode == 46 {
                        push_int(context, expect_int(loaded));
                    }
                    if opcode == 47 {
                        context.frame.push(.long_value(expect_long(loaded)));
                    }
                    if opcode == 48 {
                        context.frame.push(.float_value(expect_float(loaded)));
                    }
                    if opcode == 49 {
                        context.frame.push(.double_value(expect_double(loaded)));
                    }
                    if opcode == 50 {
                        context.frame.push(.ref_value(expect_ref(loaded)));
                    }
                    if opcode == 51 {
                        switch loaded {
                            case .byte_value(value) {
                                push_int(context, value as i32);
                            }
                            case .boolean_value(value) {
                                push_int(context, value as i32);
                            } else {
                                assert(false);
                            }
                        }
                    }
                    if opcode == 52 {
                        switch loaded {
                            case .char_value(value) {
                                push_int(context, value as i32);
                            } else {
                                assert(false);
                            }
                        }
                    }
                    if opcode == 53 {
                        switch loaded {
                            case .short_value(value) {
                                push_int(context, value as i32);
                            } else {
                                assert(false);
                            }
                        }
                    }
                } else {
                    assert(false);
                }
            } else {
                if opcode == 79 {
                    value = .int_value(expect_int(value));
                }
                if opcode == 80 {
                    value = .long_value(expect_long(value));
                }
                if opcode == 81 {
                    value = .float_value(expect_float(value));
                }
                if opcode == 82 {
                    value = .double_value(expect_double(value));
                }
                if opcode == 83 {
                    value = .ref_value(expect_ref(value));
                }
                if opcode == 84 {
                    const raw = expect_int(value);
                    if runtime.arrays.get(reference, index as usize) is current {
                        switch current {
                            case .boolean_value {
                                value = .boolean_value((raw & 1) as u8);
                            }
                            case .byte_value {
                                value = .byte_value(((raw & 255) as u8) as! i8);
                            } else {
                                assert(false);
                            }
                        }
                    } else {
                        assert(false);
                    }
                }
                if opcode == 85 {
                    value = .char_value((expect_int(value) & 65535) as u16);
                }
                if opcode == 86 {
                    value = .short_value(((expect_int(value) & 65535) as u16) as! i16);
                }
                assert(runtime.arrays.set(reference, index as usize, value));
            }
        }
        finish_instruction(context, pc, 1);
        return .ok(true);
    }
    return .ok(false);
}

pub fn execute_next(context: &Context, vm: &VM): result<void, InstructionError> {
    const pc = context.frame.pc;
    const raw_opcode = context.code[pc as usize];
    var instruction: Instruction = {
        opcode: .unsupported,
        length: 0,
        execute: unsupported,
        local_execute: execute_frame_unavailable,
        is_local: false
    };
    switch fetch(raw_opcode) {
        case .ok(actual_instruction) {
            instruction = actual_instruction;
        }
        case .err(error_value) {
            if error_value == InstructionError.unsupported_opcode {
                print_instruction_gap(context, vm, pc, raw_opcode);
                panic("unsupported JVM instruction");
            }
            return .err(error_value);
        }
    }

    if instruction_trace_enabled() {
        trace_instruction(context, vm, pc, instruction);
    }

    const execute = instruction.execute;
    try execute(context, vm);

    finish_instruction(context, pc, instruction.length);
    return .ok();
}

fn print_instruction_gap(context: &Context, vm: &VM, pc: u32, raw_opcode: u8): void {
    var classes = vm.method_area.classes[..];
    const class = &classes[context.class_index];
    var methods = class.methods[..];
    const method = &methods[context.method_index];
    println("cava panic: unsupported JVM instruction");
    print("  class: ");
    println(class.name);
    print("  method: ");
    print(method.name);
    println(method.descriptor);
    print("  pc: ");
    println(pc as i64);
    print("  opcode: ");
    println(raw_opcode as i64);
}

fn instruction_error_name(error_value: InstructionError): string {
    if error_value == InstructionError.unsupported_opcode {
        return "unsupported opcode";
    }
    if error_value == InstructionError.unsupported_native {
        return "unsupported native";
    }
    if error_value == InstructionError.invalid_constant {
        return "invalid or missing constant/class/member";
    }
    if error_value == InstructionError.missing_return {
        return "missing return";
    }
    return "instruction error";
}

pub fn print_instruction_error_context(context: &Context, vm: &VM, error_value: InstructionError): void {
    println("cava execution error");
    print("  reason: ");
    println(instruction_error_name(error_value));
    print("  class: ");
    var classes = vm.method_area.classes[..];
    if context.class_index < classes.len() {
        const class = &classes[context.class_index];
        println(class.name);
        print("  method: ");
        var methods = class.methods[..];
        if context.method_index < methods.len() {
            const method = &methods[context.method_index];
            print(method.name);
            println(method.descriptor);
        } else {
            println("<unknown>");
        }
    } else {
        println("<unknown>");
        println("  method: <unknown>");
    }
    print("  pc: ");
    println(context.frame.pc as i64);
    if (context.frame.pc as usize) < context.code.len() {
        const raw_opcode = context.code[context.frame.pc as usize];
        print("  opcode: ");
        print(raw_opcode as i64);
        print(" ");
        switch fetch(raw_opcode) {
            case .ok(instruction) {
                println(opcode_name(instruction.opcode));
            }
            case .err {
                println("unsupported");
            }
        }
    }
}

fn instruction_trace_enabled(): bool {
    if env_get("CAVA_TRACE") is value {
        const enabled = value != "" and value != "0";
        drop value;
        return enabled;
    }
    return false;
}

fn opcode_name(opcode: Opcode): string {
    if opcode == Opcode.nop {
        return "nop";
    }
    if opcode == Opcode.aconst_null {
        return "aconst_null";
    }
    if opcode == Opcode.iconst_m1 {
        return "iconst_m1";
    }
    if opcode == Opcode.iconst_0 {
        return "iconst_0";
    }
    if opcode == Opcode.iconst_1 {
        return "iconst_1";
    }
    if opcode == Opcode.iconst_2 {
        return "iconst_2";
    }
    if opcode == Opcode.iconst_3 {
        return "iconst_3";
    }
    if opcode == Opcode.iconst_4 {
        return "iconst_4";
    }
    if opcode == Opcode.iconst_5 {
        return "iconst_5";
    }
    if opcode == Opcode.lconst_0 {
        return "lconst_0";
    }
    if opcode == Opcode.lconst_1 {
        return "lconst_1";
    }
    if opcode == Opcode.fconst_0 {
        return "fconst_0";
    }
    if opcode == Opcode.fconst_1 {
        return "fconst_1";
    }
    if opcode == Opcode.fconst_2 {
        return "fconst_2";
    }
    if opcode == Opcode.dconst_0 {
        return "dconst_0";
    }
    if opcode == Opcode.dconst_1 {
        return "dconst_1";
    }
    if opcode == Opcode.bipush {
        return "bipush";
    }
    if opcode == Opcode.sipush {
        return "sipush";
    }
    if opcode == Opcode.ldc {
        return "ldc";
    }
    if opcode == Opcode.ldc_w {
        return "ldc_w";
    }
    if opcode == Opcode.ldc2_w {
        return "ldc2_w";
    }
    if opcode == Opcode.iload {
        return "iload";
    }
    if opcode == Opcode.lload {
        return "lload";
    }
    if opcode == Opcode.fload {
        return "fload";
    }
    if opcode == Opcode.dload {
        return "dload";
    }
    if opcode == Opcode.aload {
        return "aload";
    }
    if opcode == Opcode.iload_0 {
        return "iload_0";
    }
    if opcode == Opcode.iload_1 {
        return "iload_1";
    }
    if opcode == Opcode.iload_2 {
        return "iload_2";
    }
    if opcode == Opcode.iload_3 {
        return "iload_3";
    }
    if opcode == Opcode.lload_0 {
        return "lload_0";
    }
    if opcode == Opcode.lload_1 {
        return "lload_1";
    }
    if opcode == Opcode.lload_2 {
        return "lload_2";
    }
    if opcode == Opcode.lload_3 {
        return "lload_3";
    }
    if opcode == Opcode.fload_0 {
        return "fload_0";
    }
    if opcode == Opcode.fload_1 {
        return "fload_1";
    }
    if opcode == Opcode.fload_2 {
        return "fload_2";
    }
    if opcode == Opcode.fload_3 {
        return "fload_3";
    }
    if opcode == Opcode.dload_0 {
        return "dload_0";
    }
    if opcode == Opcode.dload_1 {
        return "dload_1";
    }
    if opcode == Opcode.dload_2 {
        return "dload_2";
    }
    if opcode == Opcode.dload_3 {
        return "dload_3";
    }
    if opcode == Opcode.aload_0 {
        return "aload_0";
    }
    if opcode == Opcode.aload_1 {
        return "aload_1";
    }
    if opcode == Opcode.aload_2 {
        return "aload_2";
    }
    if opcode == Opcode.aload_3 {
        return "aload_3";
    }
    if opcode == Opcode.iaload {
        return "iaload";
    }
    if opcode == Opcode.laload {
        return "laload";
    }
    if opcode == Opcode.faload {
        return "faload";
    }
    if opcode == Opcode.daload {
        return "daload";
    }
    if opcode == Opcode.aaload {
        return "aaload";
    }
    if opcode == Opcode.baload {
        return "baload";
    }
    if opcode == Opcode.caload {
        return "caload";
    }
    if opcode == Opcode.saload {
        return "saload";
    }
    if opcode == Opcode.istore {
        return "istore";
    }
    if opcode == Opcode.lstore {
        return "lstore";
    }
    if opcode == Opcode.fstore {
        return "fstore";
    }
    if opcode == Opcode.dstore {
        return "dstore";
    }
    if opcode == Opcode.astore {
        return "astore";
    }
    if opcode == Opcode.istore_0 {
        return "istore_0";
    }
    if opcode == Opcode.istore_1 {
        return "istore_1";
    }
    if opcode == Opcode.istore_2 {
        return "istore_2";
    }
    if opcode == Opcode.istore_3 {
        return "istore_3";
    }
    if opcode == Opcode.lstore_0 {
        return "lstore_0";
    }
    if opcode == Opcode.lstore_1 {
        return "lstore_1";
    }
    if opcode == Opcode.lstore_2 {
        return "lstore_2";
    }
    if opcode == Opcode.lstore_3 {
        return "lstore_3";
    }
    if opcode == Opcode.fstore_0 {
        return "fstore_0";
    }
    if opcode == Opcode.fstore_1 {
        return "fstore_1";
    }
    if opcode == Opcode.fstore_2 {
        return "fstore_2";
    }
    if opcode == Opcode.fstore_3 {
        return "fstore_3";
    }
    if opcode == Opcode.dstore_0 {
        return "dstore_0";
    }
    if opcode == Opcode.dstore_1 {
        return "dstore_1";
    }
    if opcode == Opcode.dstore_2 {
        return "dstore_2";
    }
    if opcode == Opcode.dstore_3 {
        return "dstore_3";
    }
    if opcode == Opcode.astore_0 {
        return "astore_0";
    }
    if opcode == Opcode.astore_1 {
        return "astore_1";
    }
    if opcode == Opcode.astore_2 {
        return "astore_2";
    }
    if opcode == Opcode.astore_3 {
        return "astore_3";
    }
    if opcode == Opcode.iastore {
        return "iastore";
    }
    if opcode == Opcode.lastore {
        return "lastore";
    }
    if opcode == Opcode.fastore {
        return "fastore";
    }
    if opcode == Opcode.dastore {
        return "dastore";
    }
    if opcode == Opcode.aastore {
        return "aastore";
    }
    if opcode == Opcode.bastore {
        return "bastore";
    }
    if opcode == Opcode.castore {
        return "castore";
    }
    if opcode == Opcode.sastore {
        return "sastore";
    }
    if opcode == Opcode.pop {
        return "pop";
    }
    if opcode == Opcode.pop2 {
        return "pop2";
    }
    if opcode == Opcode.dup {
        return "dup";
    }
    if opcode == Opcode.dup_x1 {
        return "dup_x1";
    }
    if opcode == Opcode.dup_x2 {
        return "dup_x2";
    }
    if opcode == Opcode.dup2 {
        return "dup2";
    }
    if opcode == Opcode.dup2_x1 {
        return "dup2_x1";
    }
    if opcode == Opcode.dup2_x2 {
        return "dup2_x2";
    }
    if opcode == Opcode.swap {
        return "swap";
    }
    if opcode == Opcode.iadd {
        return "iadd";
    }
    if opcode == Opcode.ladd {
        return "ladd";
    }
    if opcode == Opcode.fadd {
        return "fadd";
    }
    if opcode == Opcode.dadd {
        return "dadd";
    }
    if opcode == Opcode.isub {
        return "isub";
    }
    if opcode == Opcode.lsub {
        return "lsub";
    }
    if opcode == Opcode.fsub {
        return "fsub";
    }
    if opcode == Opcode.dsub {
        return "dsub";
    }
    if opcode == Opcode.imul {
        return "imul";
    }
    if opcode == Opcode.lmul {
        return "lmul";
    }
    if opcode == Opcode.fmul {
        return "fmul";
    }
    if opcode == Opcode.dmul {
        return "dmul";
    }
    if opcode == Opcode.idiv {
        return "idiv";
    }
    if opcode == Opcode.ldiv {
        return "ldiv";
    }
    if opcode == Opcode.fdiv {
        return "fdiv";
    }
    if opcode == Opcode.ddiv {
        return "ddiv";
    }
    if opcode == Opcode.irem {
        return "irem";
    }
    if opcode == Opcode.lrem {
        return "lrem";
    }
    if opcode == Opcode.unsupported {
        return "unsupported";
    }
    if opcode == Opcode.ineg {
        return "ineg";
    }
    if opcode == Opcode.lneg {
        return "lneg";
    }
    if opcode == Opcode.fneg {
        return "fneg";
    }
    if opcode == Opcode.dneg {
        return "dneg";
    }
    if opcode == Opcode.ishl {
        return "ishl";
    }
    if opcode == Opcode.lshl {
        return "lshl";
    }
    if opcode == Opcode.ishr {
        return "ishr";
    }
    if opcode == Opcode.lshr {
        return "lshr";
    }
    if opcode == Opcode.iushr {
        return "iushr";
    }
    if opcode == Opcode.lushr {
        return "lushr";
    }
    if opcode == Opcode.iand {
        return "iand";
    }
    if opcode == Opcode.land {
        return "land";
    }
    if opcode == Opcode.ior {
        return "ior";
    }
    if opcode == Opcode.lor {
        return "lor";
    }
    if opcode == Opcode.ixor {
        return "ixor";
    }
    if opcode == Opcode.lxor {
        return "lxor";
    }
    if opcode == Opcode.iinc {
        return "iinc";
    }
    if opcode == Opcode.i2l {
        return "i2l";
    }
    if opcode == Opcode.i2f {
        return "i2f";
    }
    if opcode == Opcode.i2d {
        return "i2d";
    }
    if opcode == Opcode.l2i {
        return "l2i";
    }
    if opcode == Opcode.l2f {
        return "l2f";
    }
    if opcode == Opcode.l2d {
        return "l2d";
    }
    if opcode == Opcode.f2i {
        return "f2i";
    }
    if opcode == Opcode.f2l {
        return "f2l";
    }
    if opcode == Opcode.f2d {
        return "f2d";
    }
    if opcode == Opcode.d2i {
        return "d2i";
    }
    if opcode == Opcode.d2l {
        return "d2l";
    }
    if opcode == Opcode.d2f {
        return "d2f";
    }
    if opcode == Opcode.i2b {
        return "i2b";
    }
    if opcode == Opcode.i2c {
        return "i2c";
    }
    if opcode == Opcode.i2s {
        return "i2s";
    }
    if opcode == Opcode.lcmp {
        return "lcmp";
    }
    if opcode == Opcode.fcmpl {
        return "fcmpl";
    }
    if opcode == Opcode.fcmpg {
        return "fcmpg";
    }
    if opcode == Opcode.dcmpl {
        return "dcmpl";
    }
    if opcode == Opcode.dcmpg {
        return "dcmpg";
    }
    if opcode == Opcode.ifeq {
        return "ifeq";
    }
    if opcode == Opcode.ifne {
        return "ifne";
    }
    if opcode == Opcode.iflt {
        return "iflt";
    }
    if opcode == Opcode.ifge {
        return "ifge";
    }
    if opcode == Opcode.ifgt {
        return "ifgt";
    }
    if opcode == Opcode.ifle {
        return "ifle";
    }
    if opcode == Opcode.if_icmpeq {
        return "if_icmpeq";
    }
    if opcode == Opcode.if_icmpne {
        return "if_icmpne";
    }
    if opcode == Opcode.if_icmplt {
        return "if_icmplt";
    }
    if opcode == Opcode.if_icmpge {
        return "if_icmpge";
    }
    if opcode == Opcode.if_icmpgt {
        return "if_icmpgt";
    }
    if opcode == Opcode.if_icmple {
        return "if_icmple";
    }
    if opcode == Opcode.if_acmpeq {
        return "if_acmpeq";
    }
    if opcode == Opcode.if_acmpne {
        return "if_acmpne";
    }
    if opcode == Opcode.goto_ {
        return "goto";
    }
    if opcode == Opcode.jsr {
        return "jsr";
    }
    if opcode == Opcode.ret {
        return "ret";
    }
    if opcode == Opcode.tableswitch {
        return "tableswitch";
    }
    if opcode == Opcode.lookupswitch {
        return "lookupswitch";
    }
    if opcode == Opcode.ireturn {
        return "ireturn";
    }
    if opcode == Opcode.lreturn {
        return "lreturn";
    }
    if opcode == Opcode.freturn {
        return "freturn";
    }
    if opcode == Opcode.dreturn {
        return "dreturn";
    }
    if opcode == Opcode.areturn {
        return "areturn";
    }
    if opcode == Opcode.return_ {
        return "return";
    }
    if opcode == Opcode.getstatic {
        return "getstatic";
    }
    if opcode == Opcode.putstatic {
        return "putstatic";
    }
    if opcode == Opcode.getfield {
        return "getfield";
    }
    if opcode == Opcode.putfield {
        return "putfield";
    }
    if opcode == Opcode.invoke_virtual {
        return "invokevirtual";
    }
    if opcode == Opcode.invoke_special {
        return "invokespecial";
    }
    if opcode == Opcode.invoke_static {
        return "invokestatic";
    }
    if opcode == Opcode.invoke_interface {
        return "invokeinterface";
    }
    if opcode == Opcode.new_ {
        return "new";
    }
    if opcode == Opcode.newarray {
        return "newarray";
    }
    if opcode == Opcode.anewarray {
        return "anewarray";
    }
    if opcode == Opcode.arraylength {
        return "arraylength";
    }
    if opcode == Opcode.athrow {
        return "athrow";
    }
    if opcode == Opcode.checkcast {
        return "checkcast";
    }
    if opcode == Opcode.instanceof {
        return "instanceof";
    }
    if opcode == Opcode.monitorenter {
        return "monitorenter";
    }
    if opcode == Opcode.monitorexit {
        return "monitorexit";
    }
    if opcode == Opcode.wide {
        return "wide";
    }
    if opcode == Opcode.multianewarray {
        return "multianewarray";
    }
    if opcode == Opcode.ifnull {
        return "ifnull";
    }
    if opcode == Opcode.ifnonnull {
        return "ifnonnull";
    }
    if opcode == Opcode.goto_w {
        return "goto_w";
    }
    if opcode == Opcode.jsr_w {
        return "jsr_w";
    }
    return "unsupported";
}

fn trace_instruction(context: &Context, vm: &VM, pc: u32, instruction: Instruction): void {
    var classes = vm.method_area.classes[..];
    const class = &classes[context.class_index];
    var methods = class.methods[..];
    const method = &methods[context.method_index];
    print("trace ");
    print(class.name);
    print(".");
    print(method.name);
    print(" pc=");
    print(pc as i64);
    print(" ");
    println(opcode_name(instruction.opcode));
}

pub fn execute_method(method: &Method): result<FrameResult, InstructionError> {
    var constant_pool: [:]Constant = [: 0][];
    var vm = new_vm();
    var code = copy method.code;
    var frame = new_frame(0, 0, method.max_locals, method.max_stack);
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: frame,
        code: code[..],
        constant_pool: constant_pool[..]
    };

    while context.frame.pc < method.code_len {
        try execute_next(&context, &vm);
        if context.frame.result is result {
            const out = result;
            drop context;
            code.clear();
            drop code;
            vm.clear();
            drop vm;
            return .ok(out);
        }
    }
    drop context;
    code.clear();
    drop code;
    vm.clear();
    drop vm;
    return .err(InstructionError.missing_return);
}

fn assert_int_result(result: FrameResult, expected: i32): void {
    switch result {
        case .return_value(value) {
            if value is actual {
                switch actual {
                    case .int_value(int_value) {
                        assert(int_value == expected);
                    } else {
                        assert(false);
                    }
                }
            } else {
                assert(false);
            }
        }
        case .exception {
            assert(false);
        }
    }
}

fn assert_long_result(result: FrameResult, expected: i64): void {
    switch result {
        case .return_value(value) {
            if value is actual {
                switch actual {
                    case .long_value(long_value) {
                        assert(long_value == expected);
                    } else {
                        assert(false);
                    }
                }
            } else {
                assert(false);
            }
        }
        case .exception {
            assert(false);
        }
    }
}

fn assert_float_result(result: FrameResult, expected: f32): void {
    switch result {
        case .return_value(value) {
            if value is actual {
                switch actual {
                    case .float_value(float_value) {
                        assert(float_value == expected);
                    } else {
                        assert(false);
                    }
                }
            } else {
                assert(false);
            }
        }
        case .exception {
            assert(false);
        }
    }
}

fn assert_double_result(result: FrameResult, expected: f64): void {
    switch result {
        case .return_value(value) {
            if value is actual {
                switch actual {
                    case .double_value(double_value) {
                        assert(double_value == expected);
                    } else {
                        assert(false);
                    }
                }
            } else {
                assert(false);
            }
        }
        case .exception {
            assert(false);
        }
    }
}

fn assert_null_ref_result(result: FrameResult): void {
    switch result {
        case .return_value(value) {
            if value is actual {
                const reference = expect_ref(actual);
                assert(reference.is_null());
            } else {
                assert(false);
            }
        }
        case .exception {
            assert(false);
        }
    }
}

fn assert_void_result(result: FrameResult): void {
    switch result {
        case .return_value(value) {
            assert(value == none);
        }
        case .exception {
            assert(false);
        }
    }
}

fn assert_exception_result(result: FrameResult, expected: Reference): void {
    switch result {
        case .return_value {
            assert(false);
        }
        case .exception(reference) {
            assert(reference.equals(expected));
        }
    }
}

fn seed_test_vm(vm: &VM, classes: []Class): void {
    var index: usize = 0;
    while index < classes.len() {
        vm.method_area.classes.push(copy classes[index]);
        index = index + 1;
    }
}

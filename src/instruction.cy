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

type ExecuteFn = fn (context: &Context, vm: &VM): void ! InstructionError;
type LocalExecuteFn = fn (context: &Context): void ! InstructionError;

pub fn constant_utf8(context: &Context, index: u16): string ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    switch context.constant_pool[index as usize] {
        .utf8(value) => return value;
        _ => throw InstructionError.invalid_constant;
    }
}

pub fn constant_class_name(context: &Context, index: u16): string ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    switch context.constant_pool[index as usize] {
        .class_ref(name_index) => return constant_utf8(context, name_index);
        _ => throw InstructionError.invalid_constant;
    }
}

fn constant_utf8_equals(context: &Context, index: u16, expected: string): bool ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    switch context.constant_pool[index as usize] {
        .utf8(value) => return value == expected;
        _ => throw InstructionError.invalid_constant;
    }
}

pub fn find_class_index_by_constant(context: &Context, vm: &VM, index: u16): usize ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    var name_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        .class_ref(actual) => {
            name_index = actual;
        }
        _ => throw InstructionError.invalid_constant;
    }
    if name_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    switch context.constant_pool[name_index as usize] {
        .utf8(name) => return vm.resolve_class_index(name.clone());
        _ => throw InstructionError.invalid_constant;
    }
}

pub fn find_class_index(context: &Context, vm: &VM, name: string): usize ! InstructionError {
    return vm.resolve_class_index(name.clone());
}

pub fn field_runtime_slot(vm: &VM, reference: Reference, field: Field): ?u16 {
    if vm.heap.object_class_index(reference) is object_class_index {
        return runtime_field_slot(vm.method_area.classes[..], object_class_index, field);
    }
    return none;
}

fn find_field_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): usize ! InstructionError {
    var index: usize = 0;
    while index < class.fields.len() {
        const field = &class.fields[index];
        const name_matches = try constant_utf8_equals(context, name_index, field.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, field.descriptor);
        if name_matches and descriptor_matches {
            return index;
        }
        index = index + 1;
    }
    throw InstructionError.invalid_constant;
}

fn find_field_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): Field ! InstructionError {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        const field_index: ?usize = find_field_index_by_constants(class, context, name_index, descriptor_index) catch (problem) => none;
        if field_index {
            return class.fields[field_index];
        }
        if class.super_class == "" {
            throw InstructionError.invalid_constant;
        }
        current_index = try vm.resolve_class_index(class.super_class.clone());
    }
    throw InstructionError.invalid_constant;
}

pub fn find_field_by_name_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name: string, descriptor: string, is_static: bool): Field ! InstructionError {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        if class.field_index(name, descriptor, is_static) is field_index {
            return class.fields[field_index];
        }
        if class.super_class == "" {
            throw InstructionError.invalid_constant;
        }
        current_index = try vm.resolve_class_index(class.super_class.clone());
    }
    throw InstructionError.invalid_constant;
}

pub fn find_field_index(class: &Class, name: string, descriptor: string): usize ! InstructionError {
    var index: usize = 0;
    while index < class.fields.len() {
        const field = &class.fields[index];
        if field.name == name and field.descriptor == descriptor {
            return index;
        }
        index = index + 1;
    }
    throw InstructionError.invalid_constant;
}

fn find_static_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): usize ! InstructionError {
    var index: usize = 0;
    while index < class.methods.len() {
        const method = &class.methods[index];
        const name_matches = try constant_utf8_equals(context, name_index, method.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, method.descriptor);
        if method.is_static() and name_matches and descriptor_matches {
            return index;
        }
        index = index + 1;
    }
    throw InstructionError.invalid_constant;
}

fn find_instance_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): usize ! InstructionError {
    var index: usize = 0;
    while index < class.methods.len() {
        const method = &class.methods[index];
        const name_matches = try constant_utf8_equals(context, name_index, method.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, method.descriptor);
        if !method.is_static() and name_matches and descriptor_matches {
            return index;
        }
        index = index + 1;
    }
    throw InstructionError.invalid_constant;
}

fn find_static_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): ResolvedMethod ! InstructionError {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        const method_index: ?usize = find_static_method_index_by_constants(class, context, name_index, descriptor_index) catch (problem) => none;
        if method_index {
            return ResolvedMethod {
                class_index: current_index,
                method_index: method_index
            };
        }
        if class.super_class == "" {
            throw InstructionError.invalid_constant;
        }
        current_index = try vm.resolve_class_index(class.super_class.clone());
    }
    throw InstructionError.invalid_constant;
}

fn find_instance_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): ResolvedMethod ! InstructionError {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        const method_index: ?usize = find_instance_method_index_by_constants(class, context, name_index, descriptor_index) catch (problem) => none;
        if method_index {
            return ResolvedMethod {
                class_index: current_index,
                method_index: method_index
            };
        }
        if class.super_class == "" {
            throw InstructionError.invalid_constant;
        }
        current_index = try vm.resolve_class_index(class.super_class.clone());
    }
    throw InstructionError.invalid_constant;
}

fn find_interface_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): ResolvedMethod ! InstructionError {
    if class_index >= vm.method_area.classes.len() {
        throw InstructionError.invalid_constant;
    }
    var classes = vm.method_area.classes[..];
    const method_index: ?usize = find_instance_method_index_by_constants(&classes[class_index], context, name_index, descriptor_index) catch (problem) => none;
    if method_index {
        return ResolvedMethod {
            class_index: class_index,
            method_index: method_index
        };
    }

    var interface_index: usize = 0;
    while interface_index < classes[class_index].interfaces.len() {
        const parent_index: ?usize = vm.resolve_class_index(classes[class_index].interfaces[interface_index].clone()) catch (problem) => none;
        if parent_index {
            const method: ?ResolvedMethod = find_interface_method_index_in_hierarchy(context, vm, parent_index, name_index, descriptor_index) catch (problem) => none;
            if method {
                return method;
            }
        }
        interface_index = interface_index + 1;
    }
    throw InstructionError.invalid_constant;
}

pub fn find_instance_method_by_name_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name: string, descriptor: string): ResolvedMethod ! InstructionError {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        if class.method_index(name, descriptor, false) is method_index {
            return ResolvedMethod {
                class_index: current_index,
                method_index: method_index as usize
            };
        }
        if class.super_class == "" {
            throw InstructionError.invalid_constant;
        }
        current_index = try vm.resolve_class_index(class.super_class.clone());
    }
    throw InstructionError.invalid_constant;
}

pub fn resolve_field(context: &Context, vm: &VM, index: u16): Field ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        .field_ref(member) => {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        .name_and_type(pair) => {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_field_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_static_method(context: &Context, vm: &VM, index: u16): ResolvedMethod ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        .method_ref(member) => {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        .name_and_type(pair) => {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_static_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_instance_method(context: &Context, vm: &VM, index: u16): ResolvedMethod ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        .method_ref(member) => {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        .name_and_type(pair) => {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_instance_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_interface_method(context: &Context, vm: &VM, index: u16): ResolvedMethod ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
        .interface_method_ref(member) => {
            class_index = member.class_index;
            name_and_type_index = member.name_and_type_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
        .name_and_type(pair) => {
            name_index = pair.name_index;
            descriptor_index = pair.descriptor_index;
        }
        _ => throw InstructionError.invalid_constant;
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_interface_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

fn push_int(context: &Context, value: i32): void {
    context.frame.stack.push(.int_value(value));
}

fn expect_int(value: Value): i32 {
    switch value {
        .int_value(actual) => return actual;
        .boolean_value(actual) => return actual as i32;
        .byte_value(actual) => return actual as i32;
        .short_value(actual) => return actual as i32;
        .char_value(actual) => return actual as i32;
        _ => unreachable;
    }
    return 0;
}

fn expect_ref(value: Value): Reference {
    switch value {
        .ref_value(actual) => return actual;
        _ => unreachable;
    }
    return null_ref;
}

fn expect_long(value: Value): i64 {
    switch value {
        .long_value(actual) => return actual;
        _ => unreachable;
    }
    return 0;
}

fn expect_float(value: Value): f32 {
    switch value {
        .float_value(actual) => return actual;
        _ => unreachable;
    }
    return 0.0;
}

fn expect_double(value: Value): f64 {
    switch value {
        .double_value(actual) => return actual;
        _ => unreachable;
    }
    return 0.0;
}

fn expect_return_address(value: Value): u32 {
    switch value {
        .return_address_value(actual) => return actual;
        _ => unreachable;
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
        .ref_value(reference) => context.frame.store(index, .ref_value(reference));
        .return_address_value(address) => context.frame.store(index, .return_address_value(address));
        _ => unreachable;
    }
}

fn is_category2(value: Value): bool {
    return switch value {
        .long_value => true;
        .double_value => true;
        _ => false;
    };
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

fn load_constant(context: &Context, vm: &VM, index: u16, wide: bool): void ! InstructionError {
    if index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    const constant = context.constant_pool[index as usize];
    if wide {
        switch constant {
            .long(bits) => context.frame.push(.long_value(wide_bits(bits) as! i64));
            .double(bits) => context.frame.push(.double_value(wide_bits(bits) as! f64));
            _ => throw InstructionError.invalid_constant;
        }
        return;
    }

    switch constant {
        .integer(bits) => context.frame.push(.int_value(bits as! i32));
        .float(bits) => context.frame.push(.float_value(bits as! f32));
        .class_ref(name_index) => { try load_class_constant(context, vm, index, name_index); }
        .string_ref(utf8_index) => { try load_string_constant(context, vm, utf8_index); }
        .method_type(descriptor_index) => { try load_method_type_constant(context, vm, descriptor_index); }
        .method_handle(handle) => { try load_method_handle_constant(context, vm, handle); }
        _ => throw InstructionError.invalid_constant;
    }
    return;
}

fn load_class_constant(context: &Context, vm: &VM, constant_index: u16, name_index: u16): void ! InstructionError {
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
    return;
}

fn load_string_constant(context: &Context, vm: &VM, utf8_index: u16): void ! InstructionError {
    if utf8_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    var value: []const u8 = "".bytes();
    switch context.constant_pool[utf8_index as usize] {
        .utf8(actual) => {
            value = actual.bytes();
        }
        _ => throw InstructionError.invalid_constant;
    }

    const ignored_class = vm.method_area.resolve_class("java/lang/String") catch (problem) {
        throw InstructionError.invalid_constant;
    };
    const reference = try vm.allocate_java_string(value);
    context.frame.push(.ref_value(reference));
    return;
}

fn load_method_type_constant(context: &Context, vm: &VM, descriptor_index: u16): void ! InstructionError {
    if descriptor_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    var descriptor: []const u8 = "".bytes();
    switch context.constant_pool[descriptor_index as usize] {
        .utf8(actual) => {
            descriptor = actual.bytes();
        }
        _ => throw InstructionError.invalid_constant;
    }

    const method_type_class_index = try vm.resolve_class_index("java/lang/invoke/MethodType");
    var classes = vm.method_area.classes[..];
    const reference = vm.heap.intern_method_type(method_type_class_index, &classes[method_type_class_index], descriptor);
    context.frame.push(.ref_value(reference));
    return;
}

fn load_method_handle_constant(context: &Context, vm: &VM, handle: ConstantMethodHandle): void ! InstructionError {
    if handle.reference_kind < 1 or handle.reference_kind > 9 {
        throw InstructionError.invalid_constant;
    }
    if handle.reference_index as usize >= context.constant_pool.len() {
        throw InstructionError.invalid_constant;
    }

    const method_handle_class_index = try vm.resolve_class_index("java/lang/invoke/MethodHandle");
    var classes = vm.method_area.classes[..];
    const reference = vm.heap.intern_method_handle(method_handle_class_index, &classes[method_handle_class_index], handle.reference_kind, handle.reference_index);
    context.frame.push(.ref_value(reference));
    return;
}

fn unsupported(context: &Context, vm: &VM): void ! InstructionError {
    throw InstructionError.unsupported_opcode;
}

fn nop(context: &Context): void ! InstructionError {
    return;
}

fn aconst_null(context: &Context): void ! InstructionError {
    context.frame.push(.ref_value(null_ref));
    return;
}

fn iconst_m1(context: &Context): void ! InstructionError {
    push_int(context, 0 - 1);
    return;
}

fn iconst_0(context: &Context): void ! InstructionError {
    push_int(context, 0);
    return;
}

fn iconst_1(context: &Context): void ! InstructionError {
    push_int(context, 1);
    return;
}

fn iconst_2(context: &Context): void ! InstructionError {
    push_int(context, 2);
    return;
}

fn iconst_3(context: &Context): void ! InstructionError {
    push_int(context, 3);
    return;
}

fn iconst_4(context: &Context): void ! InstructionError {
    push_int(context, 4);
    return;
}

fn iconst_5(context: &Context): void ! InstructionError {
    push_int(context, 5);
    return;
}

fn lconst_0(context: &Context): void ! InstructionError {
    context.frame.push(.long_value(0));
    return;
}

fn lconst_1(context: &Context): void ! InstructionError {
    context.frame.push(.long_value(1));
    return;
}

fn fconst_0(context: &Context): void ! InstructionError {
    context.frame.push(.float_value(0.0));
    return;
}

fn fconst_1(context: &Context): void ! InstructionError {
    context.frame.push(.float_value(1.0));
    return;
}

fn fconst_2(context: &Context): void ! InstructionError {
    context.frame.push(.float_value(2.0));
    return;
}

fn dconst_0(context: &Context): void ! InstructionError {
    context.frame.push(.double_value(0.0));
    return;
}

fn dconst_1(context: &Context): void ! InstructionError {
    context.frame.push(.double_value(1.0));
    return;
}

fn ldc(context: &Context, vm: &VM): void ! InstructionError {
    return load_constant(context, vm, context.read_u1() as u16, false);
}

fn ldc_w(context: &Context, vm: &VM): void ! InstructionError {
    return load_constant(context, vm, context.read_u2(), false);
}

fn ldc2_w(context: &Context, vm: &VM): void ! InstructionError {
    return load_constant(context, vm, context.read_u2(), true);
}

fn bipush(context: &Context): void ! InstructionError {
    push_int(context, sign_extend_u1(context.read_u1()));
    return;
}

fn sipush(context: &Context): void ! InstructionError {
    push_int(context, context.read_i2() as i32);
    return;
}

fn iload(context: &Context): void ! InstructionError {
    load_int(context, context.read_u1() as u16);
    return;
}

fn lload(context: &Context): void ! InstructionError {
    load_long(context, context.read_u1() as u16);
    return;
}

fn fload(context: &Context): void ! InstructionError {
    load_float(context, context.read_u1() as u16);
    return;
}

fn dload(context: &Context): void ! InstructionError {
    load_double(context, context.read_u1() as u16);
    return;
}

fn aload(context: &Context): void ! InstructionError {
    load_ref(context, context.read_u1() as u16);
    return;
}

fn iload_0(context: &Context): void ! InstructionError {
    load_int(context, 0);
    return;
}

fn iload_1(context: &Context): void ! InstructionError {
    load_int(context, 1);
    return;
}

fn iload_2(context: &Context): void ! InstructionError {
    load_int(context, 2);
    return;
}

fn iload_3(context: &Context): void ! InstructionError {
    load_int(context, 3);
    return;
}

fn lload_0(context: &Context): void ! InstructionError {
    load_long(context, 0);
    return;
}

fn lload_1(context: &Context): void ! InstructionError {
    load_long(context, 1);
    return;
}

fn lload_2(context: &Context): void ! InstructionError {
    load_long(context, 2);
    return;
}

fn lload_3(context: &Context): void ! InstructionError {
    load_long(context, 3);
    return;
}

fn fload_0(context: &Context): void ! InstructionError {
    load_float(context, 0);
    return;
}

fn fload_1(context: &Context): void ! InstructionError {
    load_float(context, 1);
    return;
}

fn fload_2(context: &Context): void ! InstructionError {
    load_float(context, 2);
    return;
}

fn fload_3(context: &Context): void ! InstructionError {
    load_float(context, 3);
    return;
}

fn dload_0(context: &Context): void ! InstructionError {
    load_double(context, 0);
    return;
}

fn dload_1(context: &Context): void ! InstructionError {
    load_double(context, 1);
    return;
}

fn dload_2(context: &Context): void ! InstructionError {
    load_double(context, 2);
    return;
}

fn dload_3(context: &Context): void ! InstructionError {
    load_double(context, 3);
    return;
}

fn aload_0(context: &Context): void ! InstructionError {
    load_ref(context, 0);
    return;
}

fn aload_1(context: &Context): void ! InstructionError {
    load_ref(context, 1);
    return;
}

fn aload_2(context: &Context): void ! InstructionError {
    load_ref(context, 2);
    return;
}

fn aload_3(context: &Context): void ! InstructionError {
    load_ref(context, 3);
    return;
}

fn istore(context: &Context): void ! InstructionError {
    store_int(context, context.read_u1() as u16);
    return;
}

fn lstore(context: &Context): void ! InstructionError {
    store_long(context, context.read_u1() as u16);
    return;
}

fn fstore(context: &Context): void ! InstructionError {
    store_float(context, context.read_u1() as u16);
    return;
}

fn dstore(context: &Context): void ! InstructionError {
    store_double(context, context.read_u1() as u16);
    return;
}

fn astore(context: &Context): void ! InstructionError {
    store_ref_like(context, context.read_u1() as u16);
    return;
}

fn istore_0(context: &Context): void ! InstructionError {
    store_int(context, 0);
    return;
}

fn istore_1(context: &Context): void ! InstructionError {
    store_int(context, 1);
    return;
}

fn istore_2(context: &Context): void ! InstructionError {
    store_int(context, 2);
    return;
}

fn istore_3(context: &Context): void ! InstructionError {
    store_int(context, 3);
    return;
}

fn lstore_0(context: &Context): void ! InstructionError {
    store_long(context, 0);
    return;
}

fn lstore_1(context: &Context): void ! InstructionError {
    store_long(context, 1);
    return;
}

fn lstore_2(context: &Context): void ! InstructionError {
    store_long(context, 2);
    return;
}

fn lstore_3(context: &Context): void ! InstructionError {
    store_long(context, 3);
    return;
}

fn fstore_0(context: &Context): void ! InstructionError {
    store_float(context, 0);
    return;
}

fn fstore_1(context: &Context): void ! InstructionError {
    store_float(context, 1);
    return;
}

fn fstore_2(context: &Context): void ! InstructionError {
    store_float(context, 2);
    return;
}

fn fstore_3(context: &Context): void ! InstructionError {
    store_float(context, 3);
    return;
}

fn dstore_0(context: &Context): void ! InstructionError {
    store_double(context, 0);
    return;
}

fn dstore_1(context: &Context): void ! InstructionError {
    store_double(context, 1);
    return;
}

fn dstore_2(context: &Context): void ! InstructionError {
    store_double(context, 2);
    return;
}

fn dstore_3(context: &Context): void ! InstructionError {
    store_double(context, 3);
    return;
}

fn astore_0(context: &Context): void ! InstructionError {
    store_ref_like(context, 0);
    return;
}

fn astore_1(context: &Context): void ! InstructionError {
    store_ref_like(context, 1);
    return;
}

fn astore_2(context: &Context): void ! InstructionError {
    store_ref_like(context, 2);
    return;
}

fn astore_3(context: &Context): void ! InstructionError {
    store_ref_like(context, 3);
    return;
}

fn iaload(context: &Context, vm: &VM): void ! InstructionError {
    push_int(context, expect_int(expect_array_load(context, vm)));
    return;
}

fn laload(context: &Context, vm: &VM): void ! InstructionError {
    context.frame.push(.long_value(expect_long(expect_array_load(context, vm))));
    return;
}

fn faload(context: &Context, vm: &VM): void ! InstructionError {
    context.frame.push(.float_value(expect_float(expect_array_load(context, vm))));
    return;
}

fn daload(context: &Context, vm: &VM): void ! InstructionError {
    context.frame.push(.double_value(expect_double(expect_array_load(context, vm))));
    return;
}

fn aaload(context: &Context, vm: &VM): void ! InstructionError {
    context.frame.push(.ref_value(expect_ref(expect_array_load(context, vm))));
    return;
}

fn baload(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_array_load(context, vm);
    switch value {
        .byte_value(actual) => push_int(context, actual as i32);
        .boolean_value(actual) => push_int(context, actual as i32);
        _ => unreachable;
    }
    return;
}

fn caload(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_array_load(context, vm);
    switch value {
        .char_value(actual) => push_int(context, actual as i32);
        _ => unreachable;
    }
    return;
}

fn saload(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_array_load(context, vm);
    switch value {
        .short_value(actual) => push_int(context, actual as i32);
        _ => unreachable;
    }
    return;
}

fn pop(context: &Context): void ! InstructionError {
    const ignored = context.frame.pop();
    return;
}

fn pop2(context: &Context): void ! InstructionError {
    const first = context.frame.pop();
    if !is_category2(first) {
        const second = context.frame.pop();
        const ignored = second;
    }
    return;
}

fn dup(context: &Context): void ! InstructionError {
    const value = context.frame.pop();
    context.frame.push(value);
    context.frame.push(value);
    return;
}

fn dup_x1(context: &Context): void ! InstructionError {
    const value1 = context.frame.pop();
    const value2 = context.frame.pop();
    if is_category2(value1) or is_category2(value2) {
        assert(false);
    }
    context.frame.push(value1);
    context.frame.push(value2);
    context.frame.push(value1);
    return;
}

fn dup_x2(context: &Context): void ! InstructionError {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        assert(false);
    }
    const value2 = context.frame.pop();
    if is_category2(value2) {
        context.frame.push(value1);
        context.frame.push(value2);
        context.frame.push(value1);
        return;
    }
    const value3 = context.frame.pop();
    if is_category2(value3) {
        assert(false);
    }
    context.frame.push(value1);
    context.frame.push(value3);
    context.frame.push(value2);
    context.frame.push(value1);
    return;
}

fn dup2(context: &Context): void ! InstructionError {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        context.frame.push(value1);
        context.frame.push(value1);
        return;
    }
    const value2 = context.frame.pop();
    if is_category2(value2) {
        assert(false);
    }
    context.frame.push(value2);
    context.frame.push(value1);
    context.frame.push(value2);
    context.frame.push(value1);
    return;
}

fn dup2_x1(context: &Context): void ! InstructionError {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        const value2 = context.frame.pop();
        if is_category2(value2) {
            assert(false);
        }
        context.frame.push(value1);
        context.frame.push(value2);
        context.frame.push(value1);
        return;
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
    return;
}

fn dup2_x2(context: &Context): void ! InstructionError {
    const value1 = context.frame.pop();
    if is_category2(value1) {
        const value2 = context.frame.pop();
        if is_category2(value2) {
            context.frame.push(value1);
            context.frame.push(value2);
            context.frame.push(value1);
            return;
        }
        const value3 = context.frame.pop();
        if is_category2(value3) {
            context.frame.push(value1);
            context.frame.push(value3);
            context.frame.push(value2);
            context.frame.push(value1);
            return;
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
        return;
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
    return;
}

fn swap(context: &Context): void ! InstructionError {
    const value1 = context.frame.pop();
    const value2 = context.frame.pop();
    if is_category2(value1) or is_category2(value2) {
        assert(false);
    }
    context.frame.push(value1);
    context.frame.push(value2);
    return;
}

fn iastore(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    store_array_value(context, vm, .int_value(value));
    return;
}

fn lastore(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_long(context.frame.pop());
    store_array_value(context, vm, .long_value(value));
    return;
}

fn fastore(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_float(context.frame.pop());
    store_array_value(context, vm, .float_value(value));
    return;
}

fn dastore(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_double(context.frame.pop());
    store_array_value(context, vm, .double_value(value));
    return;
}

fn aastore(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_ref(context.frame.pop());
    store_array_value(context, vm, .ref_value(value));
    return;
}

fn bastore(context: &Context, vm: &VM): void ! InstructionError {
    const raw = expect_int(context.frame.pop());
    const index = expect_int(context.frame.pop());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() or index < 0 {
        assert(false);
    }
    if vm.heap.get_element(reference, index as usize) is current {
        switch current {
            .boolean_value => {
                const low_bit: u8 = (raw & 1) as u8;
                if vm.heap.set_element(reference, index as usize, .boolean_value(low_bit)) {
                    return;
                }
            }
            .byte_value => {
                const low_bits: u8 = (raw & 255) as u8;
                if vm.heap.set_element(reference, index as usize, .byte_value(low_bits as! i8)) {
                    return;
                }
            }
            _ => unreachable;
        }
    }
    assert(false);
    return;
}

fn castore(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    store_array_value(context, vm, .char_value(low_bits));
    return;
}

fn sastore(context: &Context, vm: &VM): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    store_array_value(context, vm, .short_value(low_bits as! i16));
    return;
}

fn iadd(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 +% value2);
    return;
}

fn ladd(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 +% value2));
    return;
}

fn fadd(context: &Context): void ! InstructionError {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 + value2));
    return;
}

fn dadd(context: &Context): void ! InstructionError {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 + value2));
    return;
}

fn isub(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 -% value2);
    return;
}

fn lsub(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 -% value2));
    return;
}

fn fsub(context: &Context): void ! InstructionError {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 - value2));
    return;
}

fn dsub(context: &Context): void ! InstructionError {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 - value2));
    return;
}

fn imul(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 *% value2);
    return;
}

fn lmul(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 *% value2));
    return;
}

fn fmul(context: &Context): void ! InstructionError {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 * value2));
    return;
}

fn dmul(context: &Context): void ! InstructionError {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 * value2));
    return;
}

fn fdiv(context: &Context): void ! InstructionError {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    context.frame.push(.float_value(value1 / value2));
    return;
}

fn ddiv(context: &Context): void ! InstructionError {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    context.frame.push(.double_value(value1 / value2));
    return;
}

fn idiv(context: &Context): void ! InstructionError {
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
    return;
}

fn ldiv(context: &Context): void ! InstructionError {
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
    return;
}

fn irem(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    if value2 == 0 {
        assert(false);
    }
    push_int(context, value1 % value2);
    return;
}

fn lrem(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    if value2 == 0 {
        assert(false);
    }
    context.frame.push(.long_value(value1 % value2));
    return;
}

fn ineg(context: &Context): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    push_int(context, 0 -% value);
    return;
}

fn lneg(context: &Context): void ! InstructionError {
    const value = expect_long(context.frame.pop());
    context.frame.push(.long_value(0 -% value));
    return;
}

fn fneg(context: &Context): void ! InstructionError {
    const value = expect_float(context.frame.pop());
    const zero: f32 = 0.0;
    context.frame.push(.float_value(zero - value));
    return;
}

fn dneg(context: &Context): void ! InstructionError {
    const value = expect_double(context.frame.pop());
    context.frame.push(.double_value(0.0 - value));
    return;
}

fn ishl(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 << (value2 & 31));
    return;
}

fn lshl(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 << (value2 & 63)));
    return;
}

fn ishr(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 >> (value2 & 31));
    return;
}

fn lshr(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 >> (value2 & 63)));
    return;
}

fn iushr(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    const bits: u32 = value1 as! u32;
    push_int(context, (bits >> (value2 & 31)) as! i32);
    return;
}

fn lushr(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    const bits: u64 = value1 as! u64;
    context.frame.push(.long_value((bits >> (value2 & 63)) as! i64));
    return;
}

fn iand(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 & value2);
    return;
}

fn land(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 & value2));
    return;
}

fn ior(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, value1 | value2);
    return;
}

fn lor(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value(value1 | value2));
    return;
}

fn ixor(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    push_int(context, (value1 | value2) -% (value1 & value2));
    return;
}

fn lxor(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    context.frame.push(.long_value((value1 | value2) -% (value1 & value2)));
    return;
}

fn iinc(context: &Context): void ! InstructionError {
    const index = context.read_u1() as u16;
    const increment = sign_extend_u1(context.read_u1());
    const value = expect_int(context.frame.load(index));
    context.frame.store(index, .int_value(value +% increment));
    return;
}

fn i2l(context: &Context): void ! InstructionError {
    context.frame.push(.long_value(expect_int(context.frame.pop()) as i64));
    return;
}

fn i2f(context: &Context): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    const zero: f32 = 0.0;
    context.frame.push(.float_value(value + zero));
    return;
}

fn i2d(context: &Context): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    const zero: f64 = 0.0;
    context.frame.push(.double_value(value + zero));
    return;
}

fn l2i(context: &Context): void ! InstructionError {
    const value = expect_long(context.frame.pop());
    const low_bits: u32 = (value & 4294967295) as u32;
    push_int(context, low_bits as! i32);
    return;
}

fn l2f(context: &Context): void ! InstructionError {
    const value = expect_long(context.frame.pop());
    const zero: f32 = 0.0;
    context.frame.push(.float_value(value + zero));
    return;
}

fn l2d(context: &Context): void ! InstructionError {
    const value = expect_long(context.frame.pop());
    const zero: f64 = 0.0;
    context.frame.push(.double_value(value + zero));
    return;
}

fn f2d(context: &Context): void ! InstructionError {
    const value = expect_float(context.frame.pop());
    context.frame.push(.double_value(value as f64));
    return;
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

fn f2i(context: &Context): void ! InstructionError {
    push_int(context, jvm_f2i_value(expect_float(context.frame.pop())));
    return;
}

fn f2l(context: &Context): void ! InstructionError {
    context.frame.push(.long_value(jvm_f2l_value(expect_float(context.frame.pop()))));
    return;
}

fn d2i(context: &Context): void ! InstructionError {
    push_int(context, jvm_d2i_value(expect_double(context.frame.pop())));
    return;
}

fn d2l(context: &Context): void ! InstructionError {
    context.frame.push(.long_value(jvm_d2l_value(expect_double(context.frame.pop()))));
    return;
}

fn d2f(context: &Context): void ! InstructionError {
    context.frame.push(.float_value(expect_double(context.frame.pop()) as f32));
    return;
}

fn i2b(context: &Context): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    const low_bits: u8 = (value & 255) as u8;
    push_int(context, (low_bits as! i8) as i32);
    return;
}

fn i2c(context: &Context): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    push_int(context, low_bits as i32);
    return;
}

fn i2s(context: &Context): void ! InstructionError {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    push_int(context, (low_bits as! i16) as i32);
    return;
}

fn lcmp(context: &Context): void ! InstructionError {
    const value2 = expect_long(context.frame.pop());
    const value1 = expect_long(context.frame.pop());
    if value1 > value2 {
        push_int(context, 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 0 - 1);
    }
    return;
}

fn fcmpl(context: &Context): void ! InstructionError {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 < value2 {
        push_int(context, 0 - 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 1);
    }
    return;
}

fn fcmpg(context: &Context): void ! InstructionError {
    const value2 = expect_float(context.frame.pop());
    const value1 = expect_float(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 > value2 {
        push_int(context, 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 0 - 1);
    }
    return;
}

fn dcmpl(context: &Context): void ! InstructionError {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 < value2 {
        push_int(context, 0 - 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 1);
    }
    return;
}

fn dcmpg(context: &Context): void ! InstructionError {
    const value2 = expect_double(context.frame.pop());
    const value1 = expect_double(context.frame.pop());
    if value1 != value1 or value2 != value2 or value1 > value2 {
        push_int(context, 1);
    } else if value1 == value2 {
        push_int(context, 0);
    } else {
        push_int(context, 0 - 1);
    }
    return;
}

fn branch(context: &Context, should_branch: bool): void {
    const offset = context.read_i2() as i32;
    if should_branch {
        context.frame.next(offset);
    }
}

fn ifeq(context: &Context): void ! InstructionError {
    branch(context, expect_int(context.frame.pop()) == 0);
    return;
}

fn ifne(context: &Context): void ! InstructionError {
    branch(context, expect_int(context.frame.pop()) != 0);
    return;
}

fn iflt(context: &Context): void ! InstructionError {
    branch(context, expect_int(context.frame.pop()) < 0);
    return;
}

fn ifge(context: &Context): void ! InstructionError {
    branch(context, expect_int(context.frame.pop()) >= 0);
    return;
}

fn ifgt(context: &Context): void ! InstructionError {
    branch(context, expect_int(context.frame.pop()) > 0);
    return;
}

fn ifle(context: &Context): void ! InstructionError {
    branch(context, expect_int(context.frame.pop()) <= 0);
    return;
}

fn if_icmpeq(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 == value2);
    return;
}

fn if_icmpne(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 != value2);
    return;
}

fn if_icmplt(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 < value2);
    return;
}

fn if_icmpge(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 >= value2);
    return;
}

fn if_icmpgt(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 > value2);
    return;
}

fn if_icmple(context: &Context): void ! InstructionError {
    const value2 = expect_int(context.frame.pop());
    const value1 = expect_int(context.frame.pop());
    branch(context, value1 <= value2);
    return;
}

fn if_acmpeq(context: &Context): void ! InstructionError {
    const value2 = expect_ref(context.frame.pop());
    const value1 = expect_ref(context.frame.pop());
    branch(context, value1.equals(value2));
    return;
}

fn if_acmpne(context: &Context): void ! InstructionError {
    const value2 = expect_ref(context.frame.pop());
    const value1 = expect_ref(context.frame.pop());
    branch(context, !value1.equals(value2));
    return;
}

fn goto_(context: &Context): void ! InstructionError {
    context.frame.next(context.read_i2() as i32);
    return;
}

fn goto_w(context: &Context): void ! InstructionError {
    context.frame.next(context.read_i4());
    return;
}

fn jsr(context: &Context): void ! InstructionError {
    const return_address = context.frame.pc + 3;
    context.frame.push(.return_address_value(return_address));
    context.frame.next(context.read_i2() as i32);
    return;
}

fn ret(context: &Context): void ! InstructionError {
    const index = context.read_u1() as u16;
    context.frame.pc = expect_return_address(context.frame.load(index));
    return;
}

fn tableswitch(context: &Context): void ! InstructionError {
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
            return;
        }
        current = current + 1;
    }

    context.frame.next(default_offset);
    return;
}

fn lookupswitch(context: &Context): void ! InstructionError {
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
            return;
        }
        index = index + 1;
    }

    context.frame.next(default_offset);
    return;
}

fn jsr_w(context: &Context): void ! InstructionError {
    const return_address = context.frame.pc + 5;
    context.frame.push(.return_address_value(return_address));
    context.frame.next(context.read_i4());
    return;
}

fn ireturn(context: &Context): void ! InstructionError {
    const result: FrameResult = .return_value(context.frame.stack.pop());
    context.frame.result = result;
    return;
}

fn lreturn(context: &Context): void ! InstructionError {
    const value: Value = .long_value(expect_long(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return;
}

fn freturn(context: &Context): void ! InstructionError {
    const value: Value = .float_value(expect_float(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return;
}

fn dreturn(context: &Context): void ! InstructionError {
    const value: Value = .double_value(expect_double(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return;
}

fn areturn(context: &Context): void ! InstructionError {
    const value: Value = .ref_value(expect_ref(context.frame.pop()));
    const result: FrameResult = .return_value(value);
    context.frame.result = result;
    return;
}

fn return_(context: &Context): void ! InstructionError {
    const result: FrameResult = .return_value(none);
    context.frame.result = result;
    return;
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

fn execute_child_method_frame(context: &Context, vm: &VM, class_index: usize, method_index: usize, frame: Frame, constant_pool: []const Constant): FrameResult ! InstructionError {
    if context.runtime is runtime {
        return execute_method_frame_with_runtime(runtime.alias_handles(), vm, class_index, method_index, frame, constant_pool);
    }
    return execute_method_frame_with_vm(vm, class_index, method_index, frame, constant_pool);
}

pub fn invoke_privileged_action(context: &Context, vm: &VM, action: Reference): ?Value ! InstructionError {
    if action.is_null() {
        throw InstructionError.invalid_constant;
    }
    var action_class_index: usize = 0;
    if vm.heap.object_class_index(action) is actual_class_index {
        action_class_index = actual_class_index;
    } else {
        throw InstructionError.invalid_constant;
    }
    var run_method_index: usize = 0;
    var classes = vm.method_area.classes[..];
    if classes[action_class_index].method_index("run", "()Ljava/lang/Object;", false) is actual_run_method_index {
        run_method_index = actual_run_method_index as usize;
    } else {
        throw InstructionError.invalid_constant;
    }
    var frame = new_frame(action_class_index, run_method_index, classes[action_class_index].methods[run_method_index].max_locals, classes[action_class_index].methods[run_method_index].max_stack);
    frame.store(0, .ref_value(action));
    const result = try execute_child_method_frame(context, vm, action_class_index, run_method_index, frame, context.constant_pool);
    switch result {
        .return_value(value) => {
            const _cava_optional_4: ?Value = value;
            return _cava_optional_4;
        }
        .exception => throw InstructionError.invalid_constant;
    }
}

fn invoke_instance_method_direct(context: &Context, vm: &VM, receiver: Reference, name: string, descriptor: string, arguments: &List<Value>): ?Value ! InstructionError {
    if receiver.is_null() {
        throw InstructionError.invalid_constant;
    }
    var receiver_class_index: usize = 0;
    if vm.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        throw InstructionError.invalid_constant;
    }

    const target = try find_instance_method_by_name_in_hierarchy(context, vm, receiver_class_index, name, descriptor);
    var classes = vm.method_area.classes[..];
    const target_class = &classes[target.class_index];
    var target_methods = target_class.methods[..];
    const target_method = &target_methods[target.method_index];
    if target_method.is_native() {
        throw InstructionError.unsupported_native;
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
        .return_value(value) => {
            const _cava_optional_3: ?Value = value;
            return _cava_optional_3;
        }
        .exception => throw InstructionError.invalid_constant;
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

fn get_instance_field_by_name(context: &Context, vm: &VM, reference: Reference, class_index: usize, name: string, descriptor: string): Value ! InstructionError {
    const field = try find_field_by_name_in_hierarchy(context, vm, class_index, name, descriptor, false);
    if field_runtime_slot(vm, reference, field) is slot {
        if vm.heap.get_field(reference, slot) is value {
            return value;
        }
    }
    throw InstructionError.invalid_constant;
}

fn java_string_bytes_instruction(context: &Context, vm: &VM, reference: Reference): [:]u8 ! InstructionError {
    var value_option = vm.heap.string_bytes(reference);
    if take value_option is value {
        const bytes = value.value.clone();
        return bytes;
    }
    const string_class_index = try vm.resolve_class_index("java/lang/String");
    const value_field = try get_instance_field_by_name(context, vm, reference, string_class_index, "value", "[C");
    switch value_field {
        .ref_value(chars_reference) => {
            if vm.heap.array_length(chars_reference) is length {
                var bytes: List<u8> = [];
                var index: usize = 0;
                while index < length {
                    if vm.heap.get_element(chars_reference, index) is element {
                        switch element {
                            .char_value(ch) => bytes.push(ch as u8);
                            .byte_value(ch) => bytes.push(ch as u8);
                            _ => throw InstructionError.invalid_constant;
                        }
                    } else {
                        throw InstructionError.invalid_constant;
                    }
                    index = index + 1;
                }
                const out = byte_buffer(bytes[..]);
                return out;
            }
        }
        _ => throw InstructionError.invalid_constant;
    }
    throw InstructionError.invalid_constant;
}

pub fn invoke_reflect_constructor(context: &Context, vm: &VM, constructor: Reference, args_array: Reference): ?Value ! InstructionError {
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
        throw InstructionError.invalid_constant;
    }
    var classes = vm.method_area.classes[..];
    const target_class = &classes[target_class_index];
    var constructor_method_index: usize = 0;
    const descriptor = string.from(descriptor_bytes[..]);
    if target_class.method_index("<init>", descriptor, false) is constructor_method_index_value {
        constructor_method_index = constructor_method_index_value as usize;
    } else {
        throw InstructionError.invalid_constant;
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
        .return_value => {
            const out: Value = .ref_value(object);
            const _cava_optional_2: ?Value = out;
            return _cava_optional_2;
        }
        .exception => throw InstructionError.invalid_constant;
    }
}

fn set_java_system_property(context: &Context, vm: &VM, properties: Reference, key: string, value: string): void ! InstructionError {
    var arguments: List<Value> = [];
    const ignored_string_index = try vm.resolve_class_index("java/lang/String");
    const key_reference = try vm.allocate_java_string(key.bytes());
    const value_reference = try vm.allocate_java_string(value.bytes());
    arguments.push(.ref_value(key_reference));
    arguments.push(.ref_value(value_reference));
    const result = try invoke_instance_method_direct(context, vm, properties, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;", &arguments);
    const ignored = result;
    return;
}

pub fn initialize_java_system_properties(context: &Context, vm: &VM, properties: Reference): ?Value ! InstructionError {
    try set_java_system_property(context, vm, properties, "java.version", "1.8.0_152-ea");
    try set_java_system_property(context, vm, properties, "java.home", "");
    try set_java_system_property(context, vm, properties, "java.specification.name", "Java Platform API Specification");
    try set_java_system_property(context, vm, properties, "java.specification.version", "1.8");
    try set_java_system_property(context, vm, properties, "java.specification.vendor", "Oracle Corporation");
    try set_java_system_property(context, vm, properties, "java.vendor", "Oracle Corporation");
    try set_java_system_property(context, vm, properties, "java.vendor.url", "http://java.oracle.com/");
    try set_java_system_property(context, vm, properties, "java.vendor.url.bug", "http://bugreport.sun.com/bugreport/");
    try set_java_system_property(context, vm, properties, "java.vm.name", "Zava 64-Bit VM");
    try set_java_system_property(context, vm, properties, "java.vm.version", "1.0.0");
    try set_java_system_property(context, vm, properties, "java.vm.vendor", "Chao Yang");
    try set_java_system_property(context, vm, properties, "java.vm.info", "mixed mode");
    try set_java_system_property(context, vm, properties, "java.vm.specification.name", "Java Virtual Machine Specification");
    try set_java_system_property(context, vm, properties, "java.vm.specification.version", "1.8");
    try set_java_system_property(context, vm, properties, "java.vm.specification.vendor", "Oracle Corporation");
    try set_java_system_property(context, vm, properties, "java.runtime.name", "Java(TM) SE Runtime Environment");
    try set_java_system_property(context, vm, properties, "java.runtime.version", "1.8.0_152-ea-b05");
    try set_java_system_property(context, vm, properties, "java.class.version", "52.0");
    try set_java_system_property(context, vm, properties, "java.class.path", "src/classes;jdk/classes");
    try set_java_system_property(context, vm, properties, "java.io.tmpdir", "/var/tmp");
    try set_java_system_property(context, vm, properties, "java.library.path", "");
    try set_java_system_property(context, vm, properties, "java.ext.dirs", "");
    try set_java_system_property(context, vm, properties, "java.endorsed.dirs", "");
    try set_java_system_property(context, vm, properties, "java.awt.graphicsenv", "sun.awt.CGraphicsEnvironment");
    try set_java_system_property(context, vm, properties, "java.awt.printerjob", "sun.lwawt.macosx.CPrinterJob");
    try set_java_system_property(context, vm, properties, "awt.toolkit", "sun.lwawt.macosx.LWCToolkit");
    try set_java_system_property(context, vm, properties, "path.separator", ":");
    try set_java_system_property(context, vm, properties, "line.separator", "\n");
    try set_java_system_property(context, vm, properties, "file.separator", "/");
    try set_java_system_property(context, vm, properties, "file.encoding", "UTF-8");
    try set_java_system_property(context, vm, properties, "file.encoding.pkg", "sun.io");
    try set_java_system_property(context, vm, properties, "sun.stdout.encoding", "UTF-8");
    try set_java_system_property(context, vm, properties, "sun.stderr.encoding", "UTF-8");
    try set_java_system_property(context, vm, properties, "os.name", "Mac OS X");
    try set_java_system_property(context, vm, properties, "os.arch", "x86_64");
    try set_java_system_property(context, vm, properties, "os.version", "10.12.5");
    try set_java_system_property(context, vm, properties, "user.name", "");
    try set_java_system_property(context, vm, properties, "user.home", "");
    try set_java_system_property(context, vm, properties, "user.country", "US");
    try set_java_system_property(context, vm, properties, "user.language", "en");
    try set_java_system_property(context, vm, properties, "user.timezone", "");
    try set_java_system_property(context, vm, properties, "user.dir", "");
    try set_java_system_property(context, vm, properties, "sun.java.launcher", "SUN_STANDARD");
    try set_java_system_property(context, vm, properties, "sun.java.command", "");
    try set_java_system_property(context, vm, properties, "sun.boot.library.path", "");
    try set_java_system_property(context, vm, properties, "sun.boot.class.path", "");
    try set_java_system_property(context, vm, properties, "sun.os.patch.level", "unknown");
    try set_java_system_property(context, vm, properties, "sun.jnu.encoding", "UTF-8");
    try set_java_system_property(context, vm, properties, "sun.management.compiler", "HotSpot 64-Bit Tiered Compilers");
    try set_java_system_property(context, vm, properties, "sun.arch.data.model", "64");
    try set_java_system_property(context, vm, properties, "sun.cpu.endian", "little");
    try set_java_system_property(context, vm, properties, "sun.io.unicode.encoding", "UnicodeBig");
    try set_java_system_property(context, vm, properties, "sun.cpu.isalist", "");
    try set_java_system_property(context, vm, properties, "http.nonProxyHosts", "local|*.local|169.254/16|*.169.254/16");
    try set_java_system_property(context, vm, properties, "ftp.nonProxyHosts", "local|*.local|169.254/16|*.169.254/16");
    try set_java_system_property(context, vm, properties, "socksNonProxyHosts", "local|*.local|169.254/16|*.169.254/16");
    try set_java_system_property(context, vm, properties, "gopherProxySet", "false");
    const out: Value = .ref_value(properties);
    const _cava_optional_1: ?Value = out;
    return _cava_optional_1;
}

fn invoke_static(context: &Context, vm: &VM): void ! InstructionError {
    const resolved = try resolve_static_method(context, vm, context.read_u2());
    var classes = vm.method_area.classes[..];
    var class = &classes[resolved.class_index];
    var methods = class.methods[..];
    var method = &methods[resolved.method_index];
    if method.is_abstract() {
        throw InstructionError.unsupported_opcode;
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
        const value = try execute_native_method(context, vm, resolved.class_index, resolved.method_index, none, native_args);
        if value is actual {
            context.frame.push(actual);
        }
        return;
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

fn invoke_special(context: &Context, vm: &VM): void ! InstructionError {
    const resolved = try resolve_instance_method(context, vm, context.read_u2());
    var classes = vm.method_area.classes[..];
    const class = &classes[resolved.class_index];
    var methods = class.methods[..];
    const method = &methods[resolved.method_index];
    if method.is_abstract() {
        throw InstructionError.unsupported_opcode;
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
        throw InstructionError.invalid_constant;
    }

    if method.is_native() {
        const native_args = native_arguments(arguments);
        const value = try execute_native_method(context, vm, resolved.class_index, resolved.method_index, receiver, native_args);
        if value is actual {
            context.frame.push(actual);
        }
        return;
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

fn invoke_virtual(context: &Context, vm: &VM): void ! InstructionError {
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
        throw InstructionError.invalid_constant;
    }
    const target_name = declared_method.name.clone();
    const target_descriptor = declared_method.descriptor.clone();
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
                        return;
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
                return;
            }
        }
        if target_name == "getClass" and target_descriptor == "()Ljava/lang/Class;" {
            const native_args: List<Value> = [];
            const value = try execute_native_method(context, vm, declared.class_index, declared.method_index, receiver, native_args);
            if value is actual {
                context.frame.push(actual);
            }
            return;
        }
    }
    var receiver_class_index: usize = 0;
    if vm.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        throw InstructionError.invalid_constant;
    }
    const target = try find_instance_method_by_name_in_hierarchy(context, vm, receiver_class_index, target_name.clone(), target_descriptor.clone());
    const target_class = &classes[target.class_index];
    var target_methods = target_class.methods[..];
    const target_method = &target_methods[target.method_index];
    if target_method.is_abstract() {
        throw InstructionError.unsupported_opcode;
    }

    if target_method.is_native() {
        const native_args = native_arguments(arguments);
        const value = try execute_native_method(context, vm, target.class_index, target.method_index, receiver, native_args);
        if value is actual {
            context.frame.push(actual);
        }
        return;
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

fn invoke_interface(context: &Context, vm: &VM): void ! InstructionError {
    const declared = try resolve_interface_method(context, vm, context.read_u2());
    const count = context.read_u1();
    const zero = context.read_u1();
    if count == 0 or zero != 0 {
        throw InstructionError.invalid_constant;
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
        throw InstructionError.invalid_constant;
    }
    var receiver_class_index: usize = 0;
    if vm.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        throw InstructionError.invalid_constant;
    }
    const target_name = declared_method.name.clone();
    const target_descriptor = declared_method.descriptor.clone();
    const target = try find_instance_method_by_name_in_hierarchy(context, vm, receiver_class_index, target_name.clone(), target_descriptor.clone());
    const target_class = &classes[target.class_index];
    var target_methods = target_class.methods[..];
    const target_method = &target_methods[target.method_index];
    if target_method.is_abstract() {
        throw InstructionError.unsupported_opcode;
    }

    if target_method.is_native() {
        const native_args = native_arguments(arguments);
        const value = try execute_native_method(context, vm, target.class_index, target.method_index, receiver, native_args);
        if value is actual {
            context.frame.push(actual);
        }
        return;
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

fn new_(context: &Context, vm: &VM): void ! InstructionError {
    const class_index = try find_class_index_by_constant(context, vm, context.read_u2());
    var classes = vm.method_area.classes[..];
    try initialize_static_class(context, vm, class_index);
    const reference = vm.heap.allocate_object_with_hierarchy(class_index, classes);
    context.frame.push(.ref_value(reference));
    return;
}

fn getstatic(context: &Context, vm: &VM): void ! InstructionError {
    const field = try resolve_field(context, vm, context.read_u2());
    if !field.is_static() {
        throw InstructionError.invalid_constant;
    }
    const class_index = try vm.resolve_class_index(field.class_name.clone());
    try initialize_static_class(context, vm, class_index);
    const slot = field.slot as usize;
    var classes = vm.method_area.classes[..];
    var class = &classes[class_index];
    if slot >= class.static_vars.len() {
        throw InstructionError.invalid_constant;
    }
    const value = class.static_vars[slot];
    drop field;
    context.frame.push(value);
    return;
}

fn initialize_static_class(context: &Context, vm: &VM, class_index: usize): void ! InstructionError {
    if context.runtime is runtime {
        var decision = runtime.initializers.begin(class_index);
        while decision == InitializationDecision.waiting {
            if !runtime.pause(1) {
                throw InstructionError.invalid_constant;
            }
            decision = runtime.initializers.begin(class_index);
        }
        if decision == InitializationDecision.failed {
            throw InstructionError.invalid_constant;
        }
        if decision == InitializationDecision.complete or decision == InitializationDecision.recursive {
            return;
        }
        initialize_static_class_body(context, vm, class_index) catch (problem) {
            runtime.initializers.finish(class_index, false);
            throw problem;
        };
        runtime.initializers.finish(class_index, true);
        return;
    }
    try initialize_static_class_body(context, vm, class_index);
    return;
}

fn initialize_static_class_body(context: &Context, vm: &VM, class_index: usize): void ! InstructionError {
    if class_index >= vm.method_area.classes.len() {
        throw InstructionError.invalid_constant;
    }
    var classes = vm.method_area.classes[..];
    const class = &classes[class_index];
    if class.linked {
        return;
    }
    const class_name = class.name.clone();
    if class.super_class.len() > 0 {
        if find_loaded_class_index(classes, class.super_class.clone()) is super_index {
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
            .return_value => {}
            .exception => throw InstructionError.invalid_constant;
        }
    }
    if class_name == "java/lang/System" {
        try initialize_system_static_fields(context, vm, class_index);
    }
    if class_name == "sun/misc/VM" {
        try initialize_vm_static_fields(context, vm, class_index);
    }
    return;
}

fn initialize_system_static_fields(context: &Context, vm: &VM, system_index: usize): void ! InstructionError {
    var classes = vm.method_area.classes[..];
    const out_field_index = classes[system_index].field_index("out", "Ljava/io/PrintStream;", true);
    const err_field_index = classes[system_index].field_index("err", "Ljava/io/PrintStream;", true);
    if out_field_index == none and err_field_index == none {
        return;
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
        classes[system_index].static_vars[field.slot] = .ref_value(reference);
    }
    if err_field_index is field_index_value {
        var fields = classes[system_index].fields[..];
        const field = &fields[field_index_value as usize];
        classes[system_index].static_vars[field.slot] = .ref_value(reference);
    }
    return;
}

fn initialize_vm_static_fields(context: &Context, vm: &VM, vm_index: usize): void ! InstructionError {
    var classes = vm.method_area.classes[..];
    var vm_class = &classes[vm_index];
    if vm_class.field_index("savedProps", "Ljava/util/Properties;", true) is field_index_value {
        var fields = vm_class.fields[..];
        const field = &fields[field_index_value as usize];
        switch vm_class.static_vars[field.slot] {
            .ref_value(props_reference) => {
                if props_reference.is_null() {
                    return;
                }
                if vm.heap.object_class_index(props_reference) is props_class_index {
                    const count_field = try find_field_by_name_in_hierarchy(context, vm, props_class_index, "count", "I", false);
                    if field_runtime_slot(vm, props_reference, count_field) is count_slot {
                        const ignored_set = vm.heap.set_field(props_reference, count_slot, .int_value(1));
                    }
                }
            }
            _ => return;
        }
    }
    return;
}

fn putstatic(context: &Context, vm: &VM): void ! InstructionError {
    const field = try resolve_field(context, vm, context.read_u2());
    if !field.is_static() {
        throw InstructionError.invalid_constant;
    }
    const class_index = try vm.resolve_class_index(field.class_name.clone());
    try initialize_static_class(context, vm, class_index);
    const slot = field.slot as usize;
    var classes = vm.method_area.classes[..];
    var class = &classes[class_index];
    if slot >= class.static_vars.len() {
        throw InstructionError.invalid_constant;
    }
    class.static_vars[slot] = context.frame.pop();
    drop field;
    return;
}

fn getfield(context: &Context, vm: &VM): void ! InstructionError {
    const field = try resolve_field(context, vm, context.read_u2());
    if field.is_static() {
        throw InstructionError.invalid_constant;
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
        return;
    }
    throw InstructionError.invalid_constant;
}

fn putfield(context: &Context, vm: &VM): void ! InstructionError {
    const field = try resolve_field(context, vm, context.read_u2());
    if field.is_static() {
        throw InstructionError.invalid_constant;
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
        return;
    }
    throw InstructionError.invalid_constant;
}

fn athrow(context: &Context, vm: &VM): void ! InstructionError {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if !(try dispatch_exception(context, vm, reference)) {
        context.frame.throw_exception(reference);
    }
    return;
}

fn newarray(context: &Context, vm: &VM): void ! InstructionError {
    const count = expect_int(context.frame.pop());
    if count < 0 {
        assert(false);
    }

    const atype = context.read_u1();
    if atype < 4 or atype > 11 {
        assert(false);
    }
    const descriptor = switch atype {
        4 => "Z";
        5 => "C";
        6 => "F";
        7 => "D";
        8 => "B";
        9 => "S";
        10 => "I";
        11 => "J";
        _ => "I";
    };

    const reference = vm.heap.allocate_array(0, descriptor.bytes(), count as usize);
    context.frame.push(.ref_value(reference));
    return;
}

fn anewarray(context: &Context, vm: &VM): void ! InstructionError {
    const class_name = try constant_class_name(context, context.read_u2());
    const count = expect_int(context.frame.pop());
    if count < 0 {
        assert(false);
    }

    const descriptor = reference_array_component_descriptor(class_name);
    const array_descriptor = reference_array_descriptor(descriptor);
    const array_class_index = vm.resolve_class_index(array_descriptor.clone()) catch (problem) => 0;
    const reference = vm.heap.allocate_array(array_class_index, descriptor.bytes(), count as usize);
    context.frame.push(.ref_value(reference));
    return;
}

fn checkcast(context: &Context, vm: &VM): void ! InstructionError {
    const expected_class_index = try find_class_index_by_constant(context, vm, context.read_u2());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        context.frame.push(.ref_value(reference));
        return;
    }
    var classes = vm.method_area.classes[..];
    if vm.heap.object_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            context.frame.push(.ref_value(reference));
            return;
        }
    }
    if vm.heap.array_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            context.frame.push(.ref_value(reference));
            return;
        }
        if actual_class_index == 0 and expected_class_index < classes.len() and classes[expected_class_index].is_array {
            context.frame.push(.ref_value(reference));
            return;
        }
    }
    throw InstructionError.invalid_constant;
}

fn instanceof(context: &Context, vm: &VM): void ! InstructionError {
    const expected_class_index = try find_class_index_by_constant(context, vm, context.read_u2());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        push_int(context, 0);
        return;
    }
    var classes = vm.method_area.classes[..];
    if vm.heap.object_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            push_int(context, 1);
            return;
        }
    }
    if vm.heap.array_class_index(reference) is actual_class_index {
        if reference_assignable_to(classes, actual_class_index, expected_class_index) {
            push_int(context, 1);
            return;
        }
        if actual_class_index == 0 and expected_class_index < classes.len() and classes[expected_class_index].is_array {
            push_int(context, 1);
            return;
        }
    }
    push_int(context, 0);
    return;
}

fn monitorenter(context: &Context, vm: &VM): void ! InstructionError {
    const reference = expect_ref(context.frame.pop());
    return enter_monitor(context.runtime, vm, reference);
}

fn monitorexit(context: &Context, vm: &VM): void ! InstructionError {
    const reference = expect_ref(context.frame.pop());
    if !vm.heap.monitor_exit(reference) {
        throw InstructionError.invalid_constant;
    }
    return;
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

fn multianewarray(context: &Context, vm: &VM): void ! InstructionError {
    const descriptor = try constant_class_name(context, context.read_u2());
    const dimensions = context.read_u1();
    if dimensions == 0 {
        throw InstructionError.invalid_constant;
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
    return;
}

fn arraylength(context: &Context, vm: &VM): void ! InstructionError {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if vm.heap.array_length(reference) is length {
        push_int(context, length as i32);
        return;
    }
    assert(false);
    return;
}

fn wide(context: &Context): void ! InstructionError {
    const modified_opcode = context.read_u1();
    const index = context.read_u2();
    var advance = true;
    switch modified_opcode {
        21 => load_int(context, index);
        22 => load_long(context, index);
        23 => load_float(context, index);
        24 => load_double(context, index);
        25 => load_ref(context, index);
        54 => store_int(context, index);
        55 => store_long(context, index);
        56 => store_float(context, index);
        57 => store_double(context, index);
        58 => store_ref_like(context, index);
        132 => {
            const increment = context.read_i2() as i32;
            const value = expect_int(context.frame.load(index));
            context.frame.store(index, .int_value(value +% increment));
        }
        169 => {
            context.frame.pc = expect_return_address(context.frame.load(index));
            advance = false;
        }
        _ => unreachable;
    }

    if advance {
        context.frame.next(context.frame.offset as i32);
    }
    return;
}

fn ifnull(context: &Context): void ! InstructionError {
    branch(context, expect_ref(context.frame.pop()).is_null());
    return;
}

fn ifnonnull(context: &Context): void ! InstructionError {
    branch(context, expect_ref(context.frame.pop()).non_null());
    return;
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

pub fn fetch(raw: u8): Instruction ! InstructionError {
    const instruction = registry[raw as usize];
    if instruction.opcode == Opcode.unsupported {
        throw InstructionError.unsupported_opcode;
    }
    return instruction;
}

fn execute_frame_unavailable(context: &Context): void ! InstructionError {
    throw InstructionError.unsupported_opcode;
}

fn execute_frame_registered(context: &Context, vm: &VM): void ! InstructionError {
    const instruction = try fetch(context.code[context.frame.pc as usize]);
    if instruction.is_local {
        const execute = instruction.local_execute;
        return execute(context);
    }
    throw InstructionError.unsupported_opcode;
}

pub fn execute_frame_next(context: &Context, class_name: string, method_name: string): bool ! InstructionError {
    const pc = context.frame.pc;
    const fetched: ?Instruction = fetch(context.code[pc as usize]) catch (problem) => none;
    if fetched is instruction {
        if instruction.is_local {
            const execute = instruction.local_execute;
            trace_frame_instruction(context, class_name, method_name, instruction);
            try execute(context);
            finish_instruction(context, pc, instruction.length);
            return true;
        }
    }
    return false;
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

pub fn execute_array_next(context: &Context, class_name: string, method_name: string): bool ! InstructionError {
    const pc = context.frame.pc;
    const opcode = context.code[pc as usize];
    if !((opcode >= 46 and opcode <= 53) or (opcode >= 79 and opcode <= 86) or opcode == 190) {
        return false;
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
                    switch opcode {
                        46 => push_int(context, expect_int(loaded));
                        47 => context.frame.push(.long_value(expect_long(loaded)));
                        48 => context.frame.push(.float_value(expect_float(loaded)));
                        49 => context.frame.push(.double_value(expect_double(loaded)));
                        50 => context.frame.push(.ref_value(expect_ref(loaded)));
                        51 => {
                            switch loaded {
                                .byte_value(value) => push_int(context, value as i32);
                                .boolean_value(value) => push_int(context, value as i32);
                                _ => unreachable;
                            }
                        }
                        52 => {
                            switch loaded {
                                .char_value(value) => push_int(context, value as i32);
                                _ => unreachable;
                            }
                        }
                        53 => {
                            switch loaded {
                                .short_value(value) => push_int(context, value as i32);
                                _ => unreachable;
                            }
                        }
                        _ => unreachable;
                    }
                } else {
                    assert(false);
                }
            } else {
                switch opcode {
                    79 => { value = .int_value(expect_int(value)); }
                    80 => { value = .long_value(expect_long(value)); }
                    81 => { value = .float_value(expect_float(value)); }
                    82 => { value = .double_value(expect_double(value)); }
                    83 => { value = .ref_value(expect_ref(value)); }
                    84 => {
                        const raw = expect_int(value);
                        if runtime.arrays.get(reference, index as usize) is current {
                            switch current {
                                .boolean_value => {
                                    value = .boolean_value((raw & 1) as u8);
                                }
                                .byte_value => {
                                    value = .byte_value(((raw & 255) as u8) as! i8);
                                }
                                _ => unreachable;
                            }
                        } else {
                            assert(false);
                        }
                    }
                    85 => { value = .char_value((expect_int(value) & 65535) as u16); }
                    86 => { value = .short_value(((expect_int(value) & 65535) as u16) as! i16); }
                    _ => unreachable;
                }
                assert(runtime.arrays.set(reference, index as usize, value));
            }
        }
        finish_instruction(context, pc, 1);
        return true;
    }
    return false;
}

pub fn execute_next(context: &Context, vm: &VM): void ! InstructionError {
    const pc = context.frame.pc;
    const raw_opcode = context.code[pc as usize];
    const instruction = fetch(raw_opcode) catch (error_value) {
        if error_value == InstructionError.unsupported_opcode {
            print_instruction_gap(context, vm, pc, raw_opcode);
            panic("unsupported JVM instruction");
        }
        throw error_value;
    };

    if instruction_trace_enabled() {
        trace_instruction(context, vm, pc, instruction);
    }

    const execute = instruction.execute;
    try execute(context, vm);

    finish_instruction(context, pc, instruction.length);
    return;
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
    return switch error_value {
        InstructionError.unsupported_opcode => "unsupported opcode";
        InstructionError.unsupported_native => "unsupported native";
        InstructionError.invalid_constant => "invalid or missing constant/class/member";
        InstructionError.missing_return => "missing return";
        _ => "instruction error";
    };
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
        const fetched: ?Instruction = fetch(raw_opcode) catch (problem) {
            println("unsupported");
            yield none;
        };
        if fetched is instruction {
            println(opcode_name(instruction.opcode));
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
    return switch opcode {
        Opcode.nop => "nop";
        Opcode.aconst_null => "aconst_null";
        Opcode.iconst_m1 => "iconst_m1";
        Opcode.iconst_0 => "iconst_0";
        Opcode.iconst_1 => "iconst_1";
        Opcode.iconst_2 => "iconst_2";
        Opcode.iconst_3 => "iconst_3";
        Opcode.iconst_4 => "iconst_4";
        Opcode.iconst_5 => "iconst_5";
        Opcode.lconst_0 => "lconst_0";
        Opcode.lconst_1 => "lconst_1";
        Opcode.fconst_0 => "fconst_0";
        Opcode.fconst_1 => "fconst_1";
        Opcode.fconst_2 => "fconst_2";
        Opcode.dconst_0 => "dconst_0";
        Opcode.dconst_1 => "dconst_1";
        Opcode.bipush => "bipush";
        Opcode.sipush => "sipush";
        Opcode.ldc => "ldc";
        Opcode.ldc_w => "ldc_w";
        Opcode.ldc2_w => "ldc2_w";
        Opcode.iload => "iload";
        Opcode.lload => "lload";
        Opcode.fload => "fload";
        Opcode.dload => "dload";
        Opcode.aload => "aload";
        Opcode.iload_0 => "iload_0";
        Opcode.iload_1 => "iload_1";
        Opcode.iload_2 => "iload_2";
        Opcode.iload_3 => "iload_3";
        Opcode.lload_0 => "lload_0";
        Opcode.lload_1 => "lload_1";
        Opcode.lload_2 => "lload_2";
        Opcode.lload_3 => "lload_3";
        Opcode.fload_0 => "fload_0";
        Opcode.fload_1 => "fload_1";
        Opcode.fload_2 => "fload_2";
        Opcode.fload_3 => "fload_3";
        Opcode.dload_0 => "dload_0";
        Opcode.dload_1 => "dload_1";
        Opcode.dload_2 => "dload_2";
        Opcode.dload_3 => "dload_3";
        Opcode.aload_0 => "aload_0";
        Opcode.aload_1 => "aload_1";
        Opcode.aload_2 => "aload_2";
        Opcode.aload_3 => "aload_3";
        Opcode.iaload => "iaload";
        Opcode.laload => "laload";
        Opcode.faload => "faload";
        Opcode.daload => "daload";
        Opcode.aaload => "aaload";
        Opcode.baload => "baload";
        Opcode.caload => "caload";
        Opcode.saload => "saload";
        Opcode.istore => "istore";
        Opcode.lstore => "lstore";
        Opcode.fstore => "fstore";
        Opcode.dstore => "dstore";
        Opcode.astore => "astore";
        Opcode.istore_0 => "istore_0";
        Opcode.istore_1 => "istore_1";
        Opcode.istore_2 => "istore_2";
        Opcode.istore_3 => "istore_3";
        Opcode.lstore_0 => "lstore_0";
        Opcode.lstore_1 => "lstore_1";
        Opcode.lstore_2 => "lstore_2";
        Opcode.lstore_3 => "lstore_3";
        Opcode.fstore_0 => "fstore_0";
        Opcode.fstore_1 => "fstore_1";
        Opcode.fstore_2 => "fstore_2";
        Opcode.fstore_3 => "fstore_3";
        Opcode.dstore_0 => "dstore_0";
        Opcode.dstore_1 => "dstore_1";
        Opcode.dstore_2 => "dstore_2";
        Opcode.dstore_3 => "dstore_3";
        Opcode.astore_0 => "astore_0";
        Opcode.astore_1 => "astore_1";
        Opcode.astore_2 => "astore_2";
        Opcode.astore_3 => "astore_3";
        Opcode.iastore => "iastore";
        Opcode.lastore => "lastore";
        Opcode.fastore => "fastore";
        Opcode.dastore => "dastore";
        Opcode.aastore => "aastore";
        Opcode.bastore => "bastore";
        Opcode.castore => "castore";
        Opcode.sastore => "sastore";
        Opcode.pop => "pop";
        Opcode.pop2 => "pop2";
        Opcode.dup => "dup";
        Opcode.dup_x1 => "dup_x1";
        Opcode.dup_x2 => "dup_x2";
        Opcode.dup2 => "dup2";
        Opcode.dup2_x1 => "dup2_x1";
        Opcode.dup2_x2 => "dup2_x2";
        Opcode.swap => "swap";
        Opcode.iadd => "iadd";
        Opcode.ladd => "ladd";
        Opcode.fadd => "fadd";
        Opcode.dadd => "dadd";
        Opcode.isub => "isub";
        Opcode.lsub => "lsub";
        Opcode.fsub => "fsub";
        Opcode.dsub => "dsub";
        Opcode.imul => "imul";
        Opcode.lmul => "lmul";
        Opcode.fmul => "fmul";
        Opcode.dmul => "dmul";
        Opcode.idiv => "idiv";
        Opcode.ldiv => "ldiv";
        Opcode.fdiv => "fdiv";
        Opcode.ddiv => "ddiv";
        Opcode.irem => "irem";
        Opcode.lrem => "lrem";
        Opcode.unsupported => "unsupported";
        Opcode.ineg => "ineg";
        Opcode.lneg => "lneg";
        Opcode.fneg => "fneg";
        Opcode.dneg => "dneg";
        Opcode.ishl => "ishl";
        Opcode.lshl => "lshl";
        Opcode.ishr => "ishr";
        Opcode.lshr => "lshr";
        Opcode.iushr => "iushr";
        Opcode.lushr => "lushr";
        Opcode.iand => "iand";
        Opcode.land => "land";
        Opcode.ior => "ior";
        Opcode.lor => "lor";
        Opcode.ixor => "ixor";
        Opcode.lxor => "lxor";
        Opcode.iinc => "iinc";
        Opcode.i2l => "i2l";
        Opcode.i2f => "i2f";
        Opcode.i2d => "i2d";
        Opcode.l2i => "l2i";
        Opcode.l2f => "l2f";
        Opcode.l2d => "l2d";
        Opcode.f2i => "f2i";
        Opcode.f2l => "f2l";
        Opcode.f2d => "f2d";
        Opcode.d2i => "d2i";
        Opcode.d2l => "d2l";
        Opcode.d2f => "d2f";
        Opcode.i2b => "i2b";
        Opcode.i2c => "i2c";
        Opcode.i2s => "i2s";
        Opcode.lcmp => "lcmp";
        Opcode.fcmpl => "fcmpl";
        Opcode.fcmpg => "fcmpg";
        Opcode.dcmpl => "dcmpl";
        Opcode.dcmpg => "dcmpg";
        Opcode.ifeq => "ifeq";
        Opcode.ifne => "ifne";
        Opcode.iflt => "iflt";
        Opcode.ifge => "ifge";
        Opcode.ifgt => "ifgt";
        Opcode.ifle => "ifle";
        Opcode.if_icmpeq => "if_icmpeq";
        Opcode.if_icmpne => "if_icmpne";
        Opcode.if_icmplt => "if_icmplt";
        Opcode.if_icmpge => "if_icmpge";
        Opcode.if_icmpgt => "if_icmpgt";
        Opcode.if_icmple => "if_icmple";
        Opcode.if_acmpeq => "if_acmpeq";
        Opcode.if_acmpne => "if_acmpne";
        Opcode.goto_ => "goto";
        Opcode.jsr => "jsr";
        Opcode.ret => "ret";
        Opcode.tableswitch => "tableswitch";
        Opcode.lookupswitch => "lookupswitch";
        Opcode.ireturn => "ireturn";
        Opcode.lreturn => "lreturn";
        Opcode.freturn => "freturn";
        Opcode.dreturn => "dreturn";
        Opcode.areturn => "areturn";
        Opcode.return_ => "return";
        Opcode.getstatic => "getstatic";
        Opcode.putstatic => "putstatic";
        Opcode.getfield => "getfield";
        Opcode.putfield => "putfield";
        Opcode.invoke_virtual => "invokevirtual";
        Opcode.invoke_special => "invokespecial";
        Opcode.invoke_static => "invokestatic";
        Opcode.invoke_interface => "invokeinterface";
        Opcode.new_ => "new";
        Opcode.newarray => "newarray";
        Opcode.anewarray => "anewarray";
        Opcode.arraylength => "arraylength";
        Opcode.athrow => "athrow";
        Opcode.checkcast => "checkcast";
        Opcode.instanceof => "instanceof";
        Opcode.monitorenter => "monitorenter";
        Opcode.monitorexit => "monitorexit";
        Opcode.wide => "wide";
        Opcode.multianewarray => "multianewarray";
        Opcode.ifnull => "ifnull";
        Opcode.ifnonnull => "ifnonnull";
        Opcode.goto_w => "goto_w";
        Opcode.jsr_w => "jsr_w";
        Opcode.invoke_dynamic => "unsupported";
    };
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

pub fn execute_method(method: &Method): FrameResult ! InstructionError {
    var constant_pool: [:]Constant = [: 0][];
    var vm = new_vm();
    var code = method.code.clone();
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
            vm.clear();
            return out;
        }
    }
    vm.clear();
    throw InstructionError.missing_return;
}

fn assert_int_result(result: FrameResult, expected: i32): void {
    switch result {
        .return_value(value) => {
            if value is actual {
                switch actual {
                    .int_value(int_value) => assert(int_value == expected);
                    _ => unreachable;
                }
            } else {
                assert(false);
            }
        }
        .exception => unreachable;
    }
}

fn assert_long_result(result: FrameResult, expected: i64): void {
    switch result {
        .return_value(value) => {
            if value is actual {
                switch actual {
                    .long_value(long_value) => assert(long_value == expected);
                    _ => unreachable;
                }
            } else {
                assert(false);
            }
        }
        .exception => unreachable;
    }
}

fn assert_float_result(result: FrameResult, expected: f32): void {
    switch result {
        .return_value(value) => {
            if value is actual {
                switch actual {
                    .float_value(float_value) => assert(float_value == expected);
                    _ => unreachable;
                }
            } else {
                assert(false);
            }
        }
        .exception => unreachable;
    }
}

fn assert_double_result(result: FrameResult, expected: f64): void {
    switch result {
        .return_value(value) => {
            if value is actual {
                switch actual {
                    .double_value(double_value) => assert(double_value == expected);
                    _ => unreachable;
                }
            } else {
                assert(false);
            }
        }
        .exception => unreachable;
    }
}

fn assert_null_ref_result(result: FrameResult): void {
    switch result {
        .return_value(value) => {
            if value is actual {
                const reference = expect_ref(actual);
                assert(reference.is_null());
            } else {
                assert(false);
            }
        }
        .exception => unreachable;
    }
}

fn assert_void_result(result: FrameResult): void {
    switch result {
        .return_value(value) => assert(value == none);
        .exception => unreachable;
    }
}

fn assert_exception_result(result: FrameResult, expected: Reference): void {
    switch result {
        .return_value => unreachable;
        .exception(reference) => assert(reference.equals(expected));
    }
}

fn seed_test_vm(vm: &VM, classes: []Class): void {
    var index: usize = 0;
    while index < classes.len() {
        vm.method_area.classes.push(classes[index].clone());
        index = index + 1;
    }
}

import { Constant, ConstantMemberRef, ConstantMethodHandle, ConstantNameAndType, ConstantWide } from .classfile;
import { Context, Frame, FrameResult, new_frame } from .engine;
import { Heap, new_heap } from .heap;
import { Class, ExceptionHandler, Field, Method, Reference, ReferenceKind, Value, byte_buffer, class_access_flags, field_access_flags, method_access_flags, null_ref } from .types;

pub enum InstructionError: i32 {
    unsupported_opcode = 0,
    missing_return,
    invalid_constant,
}

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
    i2b = 145,
    i2c,
    i2s,
    lcmp = 148,
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
    ifnull = 198,
    ifnonnull,
    goto_w = 200,
    jsr_w,
}

pub struct Instruction {
    pub opcode: Opcode;
    pub length: u32;
    pub execute: ExecuteFn;
}

type ExecuteFn = fn(context: &Context): result<void, InstructionError>;

fn push_int(context: &Context, value: i32): void {
    context.frame.stack.push(.int_value(value));
}

fn expect_int(value: Value): i32 {
    switch value {
    case .int_value(actual) { return actual; }
    else { assert(false); }
    }
    return 0;
}

fn expect_ref(value: Value): Reference {
    switch value {
    case .ref_value(actual) { return actual; }
    else { assert(false); }
    }
    return null_ref;
}

fn expect_long(value: Value): i64 {
    switch value {
    case .long_value(actual) { return actual; }
    else { assert(false); }
    }
    return 0;
}

fn expect_float(value: Value): f32 {
    switch value {
    case .float_value(actual) { return actual; }
    else { assert(false); }
    }
    return 0.0;
}

fn expect_double(value: Value): f64 {
    switch value {
    case .double_value(actual) { return actual; }
    else { assert(false); }
    }
    return 0.0;
}

fn expect_return_address(value: Value): u32 {
    switch value {
    case .return_address_value(actual) { return actual; }
    else { assert(false); }
    }
    return 0;
}

fn expect_array_load(context: &Context): Value {
    const index = expect_int(context.frame.pop());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() or index < 0 {
        assert(false);
    }
    if context.heap.get_element(reference, index as usize) is value {
        return value;
    }
    assert(false);
    return .int_value(0);
}

fn store_array_value(context: &Context, value: Value): void {
    const index = expect_int(context.frame.pop());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() or index < 0 {
        assert(false);
    }
    if context.heap.set_element(reference, index as usize, value) {
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
    case .ref_value(reference) { context.frame.store(index, .ref_value(reference)); }
    case .return_address_value(address) { context.frame.store(index, .return_address_value(address)); }
    else { assert(false); }
    }
}

fn is_category2(value: Value): bool {
    switch value {
    case .long_value(actual) { const ignored = actual; return true; }
    case .double_value(actual) { const ignored = actual; return true; }
    else { return false; }
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

fn load_constant(context: &Context, index: u16, wide: bool): result<void, InstructionError> {
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
        return load_class_constant(context, index, name_index);
    }
    case .string_ref(utf8_index) {
        if wide {
            return .err(InstructionError.invalid_constant);
        }
        return load_string_constant(context, utf8_index);
    }
    case .method_type(descriptor_index) {
        if wide {
            return .err(InstructionError.invalid_constant);
        }
        return load_method_type_constant(context, descriptor_index);
    }
    case .method_handle(handle) {
        if wide {
            return .err(InstructionError.invalid_constant);
        }
        return load_method_handle_constant(context, handle);
    }
    else {
        return .err(InstructionError.invalid_constant);
    }
    }
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

fn constant_utf8(context: &Context, index: u16): result<string, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
    case .utf8(value) { return .ok(string.from(value.bytes())); }
    else { return .err(InstructionError.invalid_constant); }
    }
}

fn constant_class_name(context: &Context, index: u16): result<string, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
    case .class_ref(name_index) { return constant_utf8(context, name_index); }
    else { return .err(InstructionError.invalid_constant); }
    }
}

fn constant_utf8_equals(context: &Context, index: u16, expected: []const u8): result<bool, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
    case .utf8(value) { return .ok(bytes_equal(value.bytes(), expected)); }
    else { return .err(InstructionError.invalid_constant); }
    }
}

fn find_class_index_by_name_bytes(context: &Context, name: []const u8): result<usize, InstructionError> {
    var index: usize = 0;
    while index < context.classes.len() {
        if bytes_equal(context.classes[index].name.bytes(), name) {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn load_class_constant(context: &Context, constant_index: u16, name_index: u16): result<void, InstructionError> {
    const ignored = name_index;
    const target_class_index = try find_class_index_by_constant(context, constant_index);
    const class_class_index = try find_class_index_by_name_bytes(context, "java/lang/Class".bytes());
    var classes = context.classes;
    const class_class = &classes[class_class_index];
    const target_class = &classes[target_class_index];
    if target_class.class_object.is_null() {
        target_class.class_object = context.heap.allocate_object(class_class_index, class_class);
    }
    context.frame.push(.ref_value(target_class.class_object));
    return .ok();
}

fn load_string_constant(context: &Context, utf8_index: u16): result<void, InstructionError> {
    if utf8_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var value: []const u8 = "".bytes();
    switch context.constant_pool[utf8_index as usize] {
    case .utf8(actual) { value = actual.bytes(); }
    else { return .err(InstructionError.invalid_constant); }
    }

    const string_class_index = try find_class_index_by_name_bytes(context, "java/lang/String".bytes());
    var classes = context.classes;
    const reference = context.heap.intern_string(string_class_index, &classes[string_class_index], value);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn load_method_type_constant(context: &Context, descriptor_index: u16): result<void, InstructionError> {
    if descriptor_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var descriptor: []const u8 = "".bytes();
    switch context.constant_pool[descriptor_index as usize] {
    case .utf8(actual) { descriptor = actual.bytes(); }
    else { return .err(InstructionError.invalid_constant); }
    }

    const method_type_class_index = try find_class_index_by_name_bytes(context, "java/lang/invoke/MethodType".bytes());
    var classes = context.classes;
    const reference = context.heap.intern_method_type(method_type_class_index, &classes[method_type_class_index], descriptor);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn load_method_handle_constant(context: &Context, handle: ConstantMethodHandle): result<void, InstructionError> {
    if handle.reference_kind < 1 or handle.reference_kind > 9 {
        return .err(InstructionError.invalid_constant);
    }
    if handle.reference_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    const method_handle_class_index = try find_class_index_by_name_bytes(context, "java/lang/invoke/MethodHandle".bytes());
    var classes = context.classes;
    const reference = context.heap.intern_method_handle(method_handle_class_index, &classes[method_handle_class_index], handle.reference_kind, handle.reference_index);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn find_class_index_by_constant(context: &Context, index: u16): result<usize, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .class_ref(actual) { name_index = actual; }
    else { return .err(InstructionError.invalid_constant); }
    }

    var class_index: usize = 0;
    while class_index < context.classes.len() {
        const matches = try constant_utf8_equals(context, name_index, context.classes[class_index].name.bytes());
        if matches {
            return .ok(class_index);
        }
        class_index = class_index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_class_index(context: &Context, name: string): result<usize, InstructionError> {
    const name_bytes = name.bytes();
    var index: usize = 0;
    while index < context.classes.len() {
        if bytes_equal(context.classes[index].name.bytes(), name_bytes) {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_field_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.fields.len() {
        const name_matches = try constant_utf8_equals(context, name_index, class.fields[index].name.bytes());
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, class.fields[index].descriptor.bytes());
        if name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_field_index(class: &Class, name: string, descriptor: string): result<usize, InstructionError> {
    const name_bytes = name.bytes();
    const descriptor_bytes = descriptor.bytes();
    var index: usize = 0;
    while index < class.fields.len() {
        const field = class.fields[index];
        if bytes_equal(field.name.bytes(), name_bytes) and bytes_equal(field.descriptor.bytes(), descriptor_bytes) {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

struct ResolvedMethod {
    class_index: usize;
    method_index: usize;
}

fn find_static_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.methods.len() {
        const name_matches = try constant_utf8_equals(context, name_index, class.methods[index].name.bytes());
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, class.methods[index].descriptor.bytes());
        if class.methods[index].is_static() and name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_instance_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.methods.len() {
        const name_matches = try constant_utf8_equals(context, name_index, class.methods[index].name.bytes());
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, class.methods[index].descriptor.bytes());
        if !class.methods[index].is_static() and name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn resolve_field(context: &Context, index: u16): result<Field, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .field_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
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
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, class_index);
    var classes = context.classes;
    const actual_field_index = try find_field_index_by_constants(&classes[actual_class_index], context, name_index, descriptor_index);
    return .ok(classes[actual_class_index].fields[actual_field_index]);
}

fn resolve_static_method(context: &Context, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .method_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
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
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, class_index);
    var classes = context.classes;
    const actual_method_index = try find_static_method_index_by_constants(&classes[actual_class_index], context, name_index, descriptor_index);
    return .ok(ResolvedMethod { class_index: actual_class_index, method_index: actual_method_index });
}

fn resolve_instance_method(context: &Context, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .method_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
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
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, class_index);
    var classes = context.classes;
    const actual_method_index = try find_instance_method_index_by_constants(&classes[actual_class_index], context, name_index, descriptor_index);
    return .ok(ResolvedMethod { class_index: actual_class_index, method_index: actual_method_index });
}

fn resolve_interface_method(context: &Context, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .interface_method_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
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
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, class_index);
    var classes = context.classes;
    const actual_method_index = try find_instance_method_index_by_constants(&classes[actual_class_index], context, name_index, descriptor_index);
    return .ok(ResolvedMethod { class_index: actual_class_index, method_index: actual_method_index });
}

fn unsupported(context: &Context): result<void, InstructionError> {
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

fn ldc(context: &Context): result<void, InstructionError> {
    return load_constant(context, context.read_u1() as u16, false);
}

fn ldc_w(context: &Context): result<void, InstructionError> {
    return load_constant(context, context.read_u2(), false);
}

fn ldc2_w(context: &Context): result<void, InstructionError> {
    return load_constant(context, context.read_u2(), true);
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

fn iaload(context: &Context): result<void, InstructionError> {
    push_int(context, expect_int(expect_array_load(context)));
    return .ok();
}

fn laload(context: &Context): result<void, InstructionError> {
    context.frame.push(.long_value(expect_long(expect_array_load(context))));
    return .ok();
}

fn faload(context: &Context): result<void, InstructionError> {
    context.frame.push(.float_value(expect_float(expect_array_load(context))));
    return .ok();
}

fn daload(context: &Context): result<void, InstructionError> {
    context.frame.push(.double_value(expect_double(expect_array_load(context))));
    return .ok();
}

fn aaload(context: &Context): result<void, InstructionError> {
    context.frame.push(.ref_value(expect_ref(expect_array_load(context))));
    return .ok();
}

fn baload(context: &Context): result<void, InstructionError> {
    const value = expect_array_load(context);
    switch value {
    case .byte_value(actual) { push_int(context, actual as i32); }
    case .boolean_value(actual) { push_int(context, actual as i32); }
    else { assert(false); }
    }
    return .ok();
}

fn caload(context: &Context): result<void, InstructionError> {
    const value = expect_array_load(context);
    switch value {
    case .char_value(actual) { push_int(context, actual as i32); }
    else { assert(false); }
    }
    return .ok();
}

fn saload(context: &Context): result<void, InstructionError> {
    const value = expect_array_load(context);
    switch value {
    case .short_value(actual) { push_int(context, actual as i32); }
    else { assert(false); }
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

fn iastore(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    store_array_value(context, .int_value(value));
    return .ok();
}

fn lastore(context: &Context): result<void, InstructionError> {
    const value = expect_long(context.frame.pop());
    store_array_value(context, .long_value(value));
    return .ok();
}

fn fastore(context: &Context): result<void, InstructionError> {
    const value = expect_float(context.frame.pop());
    store_array_value(context, .float_value(value));
    return .ok();
}

fn dastore(context: &Context): result<void, InstructionError> {
    const value = expect_double(context.frame.pop());
    store_array_value(context, .double_value(value));
    return .ok();
}

fn aastore(context: &Context): result<void, InstructionError> {
    const value = expect_ref(context.frame.pop());
    store_array_value(context, .ref_value(value));
    return .ok();
}

fn bastore(context: &Context): result<void, InstructionError> {
    const raw = expect_int(context.frame.pop());
    const index = expect_int(context.frame.pop());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() or index < 0 {
        assert(false);
    }
    if context.heap.get_element(reference, index as usize) is current {
        switch current {
        case .boolean_value(actual) {
            const ignored = actual;
            const low_bit: u8 = (raw & 1) as u8;
            if context.heap.set_element(reference, index as usize, .boolean_value(low_bit)) {
                return .ok();
            }
        }
        case .byte_value(actual) {
            const ignored = actual;
            const low_bits: u8 = (raw & 255) as u8;
            if context.heap.set_element(reference, index as usize, .byte_value(low_bits as! i8)) {
                return .ok();
            }
        }
        else { assert(false); }
        }
    }
    assert(false);
    return .ok();
}

fn castore(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    store_array_value(context, .char_value(low_bits));
    return .ok();
}

fn sastore(context: &Context): result<void, InstructionError> {
    const value = expect_int(context.frame.pop());
    const low_bits: u16 = (value & 65535) as u16;
    store_array_value(context, .short_value(low_bits as! i16));
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
    } else {
        if value1 == value2 {
            push_int(context, 0);
        } else {
            push_int(context, 0 - 1);
        }
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

fn method_argument_count(descriptor: []const u8): result<usize, InstructionError> {
    if descriptor.len() < 2 or descriptor[0] != 40 {
        return .err(InstructionError.invalid_constant);
    }

    var index: usize = 1;
    var count: usize = 0;
    while index < descriptor.len() and descriptor[index] != 41 {
        while index < descriptor.len() and descriptor[index] == 91 {
            index = index + 1;
        }
        if index >= descriptor.len() {
            return .err(InstructionError.invalid_constant);
        }
        if descriptor[index] == 76 {
            while index < descriptor.len() and descriptor[index] != 59 {
                index = index + 1;
            }
            if index >= descriptor.len() {
                return .err(InstructionError.invalid_constant);
            }
        }
        index = index + 1;
        count = count + 1;
    }

    if index >= descriptor.len() or descriptor[index] != 41 {
        return .err(InstructionError.invalid_constant);
    }
    return .ok(count);
}

fn value_local_width(value: Value): u16 {
    if is_category2(value) {
        return 2;
    }
    return 1;
}

fn find_loaded_class_index(classes: []Class, name: []const u8): ?usize {
    var index: usize = 0;
    while index < classes.len() {
        if bytes_equal(classes[index].name.bytes(), name) {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn class_matches(classes: []Class, actual_index: usize, expected_index: usize): bool {
    var current = actual_index;
    while current < classes.len() {
        if current == expected_index {
            return true;
        }

        var interface_index: usize = 0;
        while interface_index < classes[current].interfaces.len() {
            if bytes_equal(classes[current].interfaces[interface_index].bytes(), classes[expected_index].name.bytes()) {
                return true;
            }
            interface_index = interface_index + 1;
        }

        if find_loaded_class_index(classes, classes[current].super_class.bytes()) is super_index {
            current = super_index;
        } else {
            return false;
        }
    }
    return false;
}

fn class_named(classes: []Class, index: usize, name: []const u8): bool {
    if index >= classes.len() {
        return false;
    }
    return bytes_equal(classes[index].name.bytes(), name);
}

fn reference_assignable_to(classes: []Class, actual_index: usize, expected_index: usize): bool {
    if actual_index >= classes.len() or expected_index >= classes.len() {
        return false;
    }
    if actual_index == expected_index {
        return true;
    }

    if classes[expected_index].is_interface() {
        var interface_index: usize = 0;
        while interface_index < classes[actual_index].interfaces.len() {
            if find_loaded_class_index(classes, classes[actual_index].interfaces[interface_index].bytes()) is actual_interface_index {
                if reference_assignable_to(classes, actual_interface_index, expected_index) {
                    return true;
                }
            } else {
                if bytes_equal(classes[actual_index].interfaces[interface_index].bytes(), classes[expected_index].name.bytes()) {
                    return true;
                }
            }
            interface_index = interface_index + 1;
        }
        if find_loaded_class_index(classes, classes[actual_index].super_class.bytes()) is super_index {
            return reference_assignable_to(classes, super_index, expected_index);
        }
        return false;
    }

    if classes[actual_index].is_array {
        if class_named(classes, expected_index, "java/lang/Object".bytes()) {
            return true;
        }
        if classes[expected_index].is_array {
            return bytes_equal(classes[actual_index].component_type.bytes(), classes[expected_index].component_type.bytes());
        }
        return false;
    }

    if find_loaded_class_index(classes, classes[actual_index].super_class.bytes()) is super_index {
        return reference_assignable_to(classes, super_index, expected_index);
    }
    return false;
}

fn handler_matches(context: &Context, handler: ExceptionHandler, exception: Reference): result<bool, InstructionError> {
    if handler.catch_type == 0 {
        return .ok(true);
    }
    var exception_class_index: usize = 0;
    if context.heap.object_class_index(exception) is actual_exception_class_index {
        exception_class_index = actual_exception_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    const catch_class_index = try find_class_index_by_constant(context, handler.catch_type);
    return .ok(class_matches(context.classes, exception_class_index, catch_class_index));
}

fn dispatch_exception(context: &Context, exception: Reference): result<bool, InstructionError> {
    if context.class_index >= context.classes.len() {
        return .ok(false);
    }
    if context.method_index >= context.classes[context.class_index].methods.len() {
        return .ok(false);
    }

    const pc = context.frame.pc as u16;
    var classes = context.classes;
    var index: usize = 0;
    while index < classes[context.class_index].methods[context.method_index].exception_handlers.len() {
        const handler = classes[context.class_index].methods[context.method_index].exception_handlers[index];
        if pc >= handler.start_pc and pc < handler.end_pc {
            if try handler_matches(context, handler, exception) {
                context.frame.clear();
                context.frame.push(.ref_value(exception));
                context.frame.pc = handler.handle_pc as u32;
                context.frame.offset = 1;
                context.frame.result = none;
                return .ok(true);
            }
        }
        index = index + 1;
    }
    return .ok(false);
}

fn apply_method_result(context: &Context, result: FrameResult): result<void, InstructionError> {
    switch result {
    case .return_value(value) {
        if value is actual {
            context.frame.push(actual);
        }
    }
    case .exception(reference) {
        if !(try dispatch_exception(context, reference)) {
            context.frame.throw_exception(reference);
        }
    }
    }
    return .ok();
}

fn execute_method_frame(class_index: usize, method_index: usize, frame: Frame, constant_pool: []const Constant, classes: []Class, heap: &Heap): result<FrameResult, InstructionError> {
    var context = Context { class_index: class_index, method_index: method_index, frame: frame, code: classes[class_index].methods[method_index].code[..], constant_pool: constant_pool, classes: classes, heap: heap };

    while context.frame.pc < classes[class_index].methods[method_index].code_len {
        try execute_next(&context);
        if context.frame.result is result {
            const out = result;
            drop context;
            return .ok(out);
        }
    }
    drop context;
    return .err(InstructionError.missing_return);
}

fn invoke_static(context: &Context): result<void, InstructionError> {
    const resolved = try resolve_static_method(context, context.read_u2());
    var classes = context.classes;
    if classes[resolved.class_index].methods[resolved.method_index].is_native() or classes[resolved.class_index].methods[resolved.method_index].is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    const argument_count = try method_argument_count(classes[resolved.class_index].methods[resolved.method_index].descriptor.bytes());
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }

    var frame = new_frame(resolved.class_index, resolved.method_index, classes[resolved.class_index].methods[resolved.method_index].max_locals, classes[resolved.class_index].methods[resolved.method_index].max_stack);
    var local_index: u16 = 0;
    var argument_index = arguments.len();
    while argument_index > 0 {
        argument_index = argument_index - 1;
        const value = arguments[argument_index];
        frame.store(local_index, value);
        local_index = local_index + value_local_width(value);
    }
    drop arguments;

    const result = try execute_method_frame(resolved.class_index, resolved.method_index, frame, context.constant_pool, context.classes, context.heap);
    return apply_method_result(context, result);
}

fn invoke_special(context: &Context): result<void, InstructionError> {
    const resolved = try resolve_instance_method(context, context.read_u2());
    var classes = context.classes;
    if classes[resolved.class_index].methods[resolved.method_index].is_native() or classes[resolved.class_index].methods[resolved.method_index].is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    const argument_count = try method_argument_count(classes[resolved.class_index].methods[resolved.method_index].descriptor.bytes());
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }

    const receiver = expect_ref(context.frame.pop());
    if receiver.is_null() {
        assert(false);
    }

    var frame = new_frame(resolved.class_index, resolved.method_index, classes[resolved.class_index].methods[resolved.method_index].max_locals, classes[resolved.class_index].methods[resolved.method_index].max_stack);
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

    const result = try execute_method_frame(resolved.class_index, resolved.method_index, frame, context.constant_pool, context.classes, context.heap);
    return apply_method_result(context, result);
}

fn invoke_virtual(context: &Context): result<void, InstructionError> {
    const declared = try resolve_instance_method(context, context.read_u2());
    var classes = context.classes;
    const argument_count = try method_argument_count(classes[declared.class_index].methods[declared.method_index].descriptor.bytes());
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }

    const receiver = expect_ref(context.frame.pop());
    if receiver.is_null() {
        assert(false);
    }
    var receiver_class_index: usize = 0;
    if context.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var target_method_index: usize = 0;
    const target_name = classes[declared.class_index].methods[declared.method_index].name.bytes();
    const target_descriptor = classes[declared.class_index].methods[declared.method_index].descriptor.bytes();
    const target_method_index_option = classes[receiver_class_index].method_index(target_name, target_descriptor, false);
    if target_method_index_option is actual_target_method_index {
        target_method_index = actual_target_method_index as usize;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    if classes[receiver_class_index].methods[target_method_index].is_native() or classes[receiver_class_index].methods[target_method_index].is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    var frame = new_frame(receiver_class_index, target_method_index, classes[receiver_class_index].methods[target_method_index].max_locals, classes[receiver_class_index].methods[target_method_index].max_stack);
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

    const result = try execute_method_frame(receiver_class_index, target_method_index, frame, context.constant_pool, context.classes, context.heap);
    return apply_method_result(context, result);
}

fn invoke_interface(context: &Context): result<void, InstructionError> {
    const declared = try resolve_interface_method(context, context.read_u2());
    const count = context.read_u1();
    const zero = context.read_u1();
    if count == 0 or zero != 0 {
        return .err(InstructionError.invalid_constant);
    }

    var classes = context.classes;
    const argument_count = try method_argument_count(classes[declared.class_index].methods[declared.method_index].descriptor.bytes());
    var arguments: List<Value> = [];
    var index: usize = 0;
    while index < argument_count {
        arguments.push(context.frame.pop());
        index = index + 1;
    }

    const receiver = expect_ref(context.frame.pop());
    if receiver.is_null() {
        assert(false);
    }
    var receiver_class_index: usize = 0;
    if context.heap.object_class_index(receiver) is actual_receiver_class_index {
        receiver_class_index = actual_receiver_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var target_method_index: usize = 0;
    const target_name = classes[declared.class_index].methods[declared.method_index].name.bytes();
    const target_descriptor = classes[declared.class_index].methods[declared.method_index].descriptor.bytes();
    const target_method_index_option = classes[receiver_class_index].method_index(target_name, target_descriptor, false);
    if target_method_index_option is actual_target_method_index {
        target_method_index = actual_target_method_index as usize;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    if classes[receiver_class_index].methods[target_method_index].is_native() or classes[receiver_class_index].methods[target_method_index].is_abstract() {
        return .err(InstructionError.unsupported_opcode);
    }

    var frame = new_frame(receiver_class_index, target_method_index, classes[receiver_class_index].methods[target_method_index].max_locals, classes[receiver_class_index].methods[target_method_index].max_stack);
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

    const result = try execute_method_frame(receiver_class_index, target_method_index, frame, context.constant_pool, context.classes, context.heap);
    return apply_method_result(context, result);
}

fn new_(context: &Context): result<void, InstructionError> {
    const class_index = try find_class_index_by_constant(context, context.read_u2());
    var classes = context.classes;
    const reference = context.heap.allocate_object(class_index, &classes[class_index]);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn getstatic(context: &Context): result<void, InstructionError> {
    const field = try resolve_field(context, context.read_u2());
    if !field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const class_index = try find_class_index(context, string.from(field.class_name.bytes()));
    const slot = field.slot as usize;
    if slot >= context.classes[class_index].static_vars.len() {
        return .err(InstructionError.invalid_constant);
    }
    context.frame.push(context.classes[class_index].static_vars[slot]);
    return .ok();
}

fn putstatic(context: &Context): result<void, InstructionError> {
    const field = try resolve_field(context, context.read_u2());
    if !field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const class_index = try find_class_index(context, string.from(field.class_name.bytes()));
    const slot = field.slot as usize;
    if slot >= context.classes[class_index].static_vars.len() {
        return .err(InstructionError.invalid_constant);
    }
    context.classes[class_index].static_vars[slot] = context.frame.pop();
    return .ok();
}

fn getfield(context: &Context): result<void, InstructionError> {
    const field = try resolve_field(context, context.read_u2());
    if field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if context.heap.get_field(reference, field.slot) is value {
        context.frame.push(value);
        return .ok();
    }
    return .err(InstructionError.invalid_constant);
}

fn putfield(context: &Context): result<void, InstructionError> {
    const field = try resolve_field(context, context.read_u2());
    if field.is_static() {
        return .err(InstructionError.invalid_constant);
    }
    const value = context.frame.pop();
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if context.heap.set_field(reference, field.slot, value) {
        return .ok();
    }
    return .err(InstructionError.invalid_constant);
}

fn athrow(context: &Context): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if !(try dispatch_exception(context, reference)) {
        context.frame.throw_exception(reference);
    }
    return .ok();
}

fn newarray(context: &Context): result<void, InstructionError> {
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

    const reference = context.heap.allocate_array(0, descriptor, count as usize);
    context.frame.push(.ref_value(reference));
    return .ok();
}

fn reference_array_component_descriptor(class_name: string): string {
    const name_bytes = class_name.bytes();
    if name_bytes.len() > 0 and name_bytes[0] == 91 {
        return string.from(name_bytes);
    }

    var bytes = [: name_bytes.len() + 2]u8;
    bytes.push(76);
    var index: usize = 0;
    while index < name_bytes.len() {
        bytes.push(name_bytes[index]);
        index = index + 1;
    }
    bytes.push(59);
    const out = string.from(bytes[..]);
    drop bytes;
    return out;
}

fn anewarray(context: &Context): result<void, InstructionError> {
    const class_name = try constant_class_name(context, context.read_u2());
    const count = expect_int(context.frame.pop());
    if count < 0 {
        assert(false);
    }

    const descriptor = reference_array_component_descriptor(class_name);
    const reference = context.heap.allocate_array(0, descriptor, count as usize);
    context.frame.push(.ref_value(reference));
    drop descriptor;
    drop class_name;
    return .ok();
}

fn checkcast(context: &Context): result<void, InstructionError> {
    const expected_class_index = try find_class_index_by_constant(context, context.read_u2());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        context.frame.push(.ref_value(reference));
        return .ok();
    }
    if context.heap.object_class_index(reference) is actual_class_index {
        if reference_assignable_to(context.classes, actual_class_index, expected_class_index) {
            context.frame.push(.ref_value(reference));
            return .ok();
        }
    }
    assert(false);
    return .ok();
}

fn instanceof(context: &Context): result<void, InstructionError> {
    const expected_class_index = try find_class_index_by_constant(context, context.read_u2());
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        push_int(context, 0);
        return .ok();
    }
    if context.heap.object_class_index(reference) is actual_class_index {
        if reference_assignable_to(context.classes, actual_class_index, expected_class_index) {
            push_int(context, 1);
            return .ok();
        }
    }
    push_int(context, 0);
    return .ok();
}

fn monitorenter(context: &Context): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    return .ok();
}

fn monitorexit(context: &Context): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    return .ok();
}

fn arraylength(context: &Context): result<void, InstructionError> {
    const reference = expect_ref(context.frame.pop());
    if reference.is_null() {
        assert(false);
    }
    if context.heap.array_length(reference) is length {
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

const registry: [256]Instruction = [
    { opcode: .nop, length: 1, execute: nop }, // 0x00 nop
    { opcode: .aconst_null, length: 1, execute: aconst_null }, // 0x01 aconst_null
    { opcode: .iconst_m1, length: 1, execute: iconst_m1 }, // 0x02 iconst_m1
    { opcode: .iconst_0, length: 1, execute: iconst_0 }, // 0x03 iconst_0
    { opcode: .iconst_1, length: 1, execute: iconst_1 }, // 0x04 iconst_1
    { opcode: .iconst_2, length: 1, execute: iconst_2 }, // 0x05 iconst_2
    { opcode: .iconst_3, length: 1, execute: iconst_3 }, // 0x06 iconst_3
    { opcode: .iconst_4, length: 1, execute: iconst_4 }, // 0x07 iconst_4
    { opcode: .iconst_5, length: 1, execute: iconst_5 }, // 0x08 iconst_5
    { opcode: .lconst_0, length: 1, execute: lconst_0 }, // 0x09 lconst_0
    { opcode: .lconst_1, length: 1, execute: lconst_1 }, // 0x0A lconst_1
    { opcode: .fconst_0, length: 1, execute: fconst_0 }, // 0x0B fconst_0
    { opcode: .fconst_1, length: 1, execute: fconst_1 }, // 0x0C fconst_1
    { opcode: .fconst_2, length: 1, execute: fconst_2 }, // 0x0D fconst_2
    { opcode: .dconst_0, length: 1, execute: dconst_0 }, // 0x0E dconst_0
    { opcode: .dconst_1, length: 1, execute: dconst_1 }, // 0x0F dconst_1
    { opcode: .bipush, length: 2, execute: bipush }, // 0x10 bipush
    { opcode: .sipush, length: 3, execute: sipush }, // 0x11 sipush
    { opcode: .ldc, length: 2, execute: ldc }, // 0x12 ldc
    { opcode: .ldc_w, length: 3, execute: ldc_w }, // 0x13 ldc_w
    { opcode: .ldc2_w, length: 3, execute: ldc2_w }, // 0x14 ldc2_w
    { opcode: .iload, length: 2, execute: iload }, // 0x15 iload
    { opcode: .lload, length: 2, execute: lload }, // 0x16 lload
    { opcode: .fload, length: 2, execute: fload }, // 0x17 fload
    { opcode: .dload, length: 2, execute: dload }, // 0x18 dload
    { opcode: .aload, length: 2, execute: aload }, // 0x19 aload
    { opcode: .iload_0, length: 1, execute: iload_0 }, // 0x1A iload_0
    { opcode: .iload_1, length: 1, execute: iload_1 }, // 0x1B iload_1
    { opcode: .iload_2, length: 1, execute: iload_2 }, // 0x1C iload_2
    { opcode: .iload_3, length: 1, execute: iload_3 }, // 0x1D iload_3
    { opcode: .lload_0, length: 1, execute: lload_0 }, // 0x1E lload_0
    { opcode: .lload_1, length: 1, execute: lload_1 }, // 0x1F lload_1
    { opcode: .lload_2, length: 1, execute: lload_2 }, // 0x20 lload_2
    { opcode: .lload_3, length: 1, execute: lload_3 }, // 0x21 lload_3
    { opcode: .fload_0, length: 1, execute: fload_0 }, // 0x22 fload_0
    { opcode: .fload_1, length: 1, execute: fload_1 }, // 0x23 fload_1
    { opcode: .fload_2, length: 1, execute: fload_2 }, // 0x24 fload_2
    { opcode: .fload_3, length: 1, execute: fload_3 }, // 0x25 fload_3
    { opcode: .dload_0, length: 1, execute: dload_0 }, // 0x26 dload_0
    { opcode: .dload_1, length: 1, execute: dload_1 }, // 0x27 dload_1
    { opcode: .dload_2, length: 1, execute: dload_2 }, // 0x28 dload_2
    { opcode: .dload_3, length: 1, execute: dload_3 }, // 0x29 dload_3
    { opcode: .aload_0, length: 1, execute: aload_0 }, // 0x2A aload_0
    { opcode: .aload_1, length: 1, execute: aload_1 }, // 0x2B aload_1
    { opcode: .aload_2, length: 1, execute: aload_2 }, // 0x2C aload_2
    { opcode: .aload_3, length: 1, execute: aload_3 }, // 0x2D aload_3
    { opcode: .iaload, length: 1, execute: iaload }, // 0x2E iaload
    { opcode: .laload, length: 1, execute: laload }, // 0x2F laload
    { opcode: .faload, length: 1, execute: faload }, // 0x30 faload
    { opcode: .daload, length: 1, execute: daload }, // 0x31 daload
    { opcode: .aaload, length: 1, execute: aaload }, // 0x32 aaload
    { opcode: .baload, length: 1, execute: baload }, // 0x33 baload
    { opcode: .caload, length: 1, execute: caload }, // 0x34 caload
    { opcode: .saload, length: 1, execute: saload }, // 0x35 saload
    { opcode: .istore, length: 2, execute: istore }, // 0x36 istore
    { opcode: .lstore, length: 2, execute: lstore }, // 0x37 lstore
    { opcode: .fstore, length: 2, execute: fstore }, // 0x38 fstore
    { opcode: .dstore, length: 2, execute: dstore }, // 0x39 dstore
    { opcode: .astore, length: 2, execute: astore }, // 0x3A astore
    { opcode: .istore_0, length: 1, execute: istore_0 }, // 0x3B istore_0
    { opcode: .istore_1, length: 1, execute: istore_1 }, // 0x3C istore_1
    { opcode: .istore_2, length: 1, execute: istore_2 }, // 0x3D istore_2
    { opcode: .istore_3, length: 1, execute: istore_3 }, // 0x3E istore_3
    { opcode: .lstore_0, length: 1, execute: lstore_0 }, // 0x3F lstore_0
    { opcode: .lstore_1, length: 1, execute: lstore_1 }, // 0x40 lstore_1
    { opcode: .lstore_2, length: 1, execute: lstore_2 }, // 0x41 lstore_2
    { opcode: .lstore_3, length: 1, execute: lstore_3 }, // 0x42 lstore_3
    { opcode: .fstore_0, length: 1, execute: fstore_0 }, // 0x43 fstore_0
    { opcode: .fstore_1, length: 1, execute: fstore_1 }, // 0x44 fstore_1
    { opcode: .fstore_2, length: 1, execute: fstore_2 }, // 0x45 fstore_2
    { opcode: .fstore_3, length: 1, execute: fstore_3 }, // 0x46 fstore_3
    { opcode: .dstore_0, length: 1, execute: dstore_0 }, // 0x47 dstore_0
    { opcode: .dstore_1, length: 1, execute: dstore_1 }, // 0x48 dstore_1
    { opcode: .dstore_2, length: 1, execute: dstore_2 }, // 0x49 dstore_2
    { opcode: .dstore_3, length: 1, execute: dstore_3 }, // 0x4A dstore_3
    { opcode: .astore_0, length: 1, execute: astore_0 }, // 0x4B astore_0
    { opcode: .astore_1, length: 1, execute: astore_1 }, // 0x4C astore_1
    { opcode: .astore_2, length: 1, execute: astore_2 }, // 0x4D astore_2
    { opcode: .astore_3, length: 1, execute: astore_3 }, // 0x4E astore_3
    { opcode: .iastore, length: 1, execute: iastore }, // 0x4F iastore
    { opcode: .lastore, length: 1, execute: lastore }, // 0x50 lastore
    { opcode: .fastore, length: 1, execute: fastore }, // 0x51 fastore
    { opcode: .dastore, length: 1, execute: dastore }, // 0x52 dastore
    { opcode: .aastore, length: 1, execute: aastore }, // 0x53 aastore
    { opcode: .bastore, length: 1, execute: bastore }, // 0x54 bastore
    { opcode: .castore, length: 1, execute: castore }, // 0x55 castore
    { opcode: .sastore, length: 1, execute: sastore }, // 0x56 sastore
    { opcode: .pop, length: 1, execute: pop }, // 0x57 pop
    { opcode: .pop2, length: 1, execute: pop2 }, // 0x58 pop2
    { opcode: .dup, length: 1, execute: dup }, // 0x59 dup
    { opcode: .dup_x1, length: 1, execute: dup_x1 }, // 0x5A dup_x1
    { opcode: .dup_x2, length: 1, execute: dup_x2 }, // 0x5B dup_x2
    { opcode: .dup2, length: 1, execute: dup2 }, // 0x5C dup2
    { opcode: .dup2_x1, length: 1, execute: dup2_x1 }, // 0x5D dup2_x1
    { opcode: .dup2_x2, length: 1, execute: dup2_x2 }, // 0x5E dup2_x2
    { opcode: .swap, length: 1, execute: swap }, // 0x5F swap
    { opcode: .iadd, length: 1, execute: iadd }, // 0x60 iadd
    { opcode: .ladd, length: 1, execute: ladd }, // 0x61 ladd
    { opcode: .fadd, length: 1, execute: fadd }, // 0x62 fadd
    { opcode: .dadd, length: 1, execute: dadd }, // 0x63 dadd
    { opcode: .isub, length: 1, execute: isub }, // 0x64 isub
    { opcode: .lsub, length: 1, execute: lsub }, // 0x65 lsub
    { opcode: .fsub, length: 1, execute: fsub }, // 0x66 fsub
    { opcode: .dsub, length: 1, execute: dsub }, // 0x67 dsub
    { opcode: .imul, length: 1, execute: imul }, // 0x68 imul
    { opcode: .lmul, length: 1, execute: lmul }, // 0x69 lmul
    { opcode: .fmul, length: 1, execute: fmul }, // 0x6A fmul
    { opcode: .dmul, length: 1, execute: dmul }, // 0x6B dmul
    { opcode: .idiv, length: 1, execute: idiv }, // 0x6C idiv
    { opcode: .ldiv, length: 1, execute: ldiv }, // 0x6D ldiv
    { opcode: .fdiv, length: 1, execute: fdiv }, // 0x6E fdiv
    { opcode: .ddiv, length: 1, execute: ddiv }, // 0x6F ddiv
    { opcode: .irem, length: 1, execute: irem }, // 0x70 irem
    { opcode: .lrem, length: 1, execute: lrem }, // 0x71 lrem
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x72 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x73 unsupported
    { opcode: .ineg, length: 1, execute: ineg }, // 0x74 ineg
    { opcode: .lneg, length: 1, execute: lneg }, // 0x75 lneg
    { opcode: .fneg, length: 1, execute: fneg }, // 0x76 fneg
    { opcode: .dneg, length: 1, execute: dneg }, // 0x77 dneg
    { opcode: .ishl, length: 1, execute: ishl }, // 0x78 ishl
    { opcode: .lshl, length: 1, execute: lshl }, // 0x79 lshl
    { opcode: .ishr, length: 1, execute: ishr }, // 0x7A ishr
    { opcode: .lshr, length: 1, execute: lshr }, // 0x7B lshr
    { opcode: .iushr, length: 1, execute: iushr }, // 0x7C iushr
    { opcode: .lushr, length: 1, execute: lushr }, // 0x7D lushr
    { opcode: .iand, length: 1, execute: iand }, // 0x7E iand
    { opcode: .land, length: 1, execute: land }, // 0x7F land
    { opcode: .ior, length: 1, execute: ior }, // 0x80 ior
    { opcode: .lor, length: 1, execute: lor }, // 0x81 lor
    { opcode: .ixor, length: 1, execute: ixor }, // 0x82 ixor
    { opcode: .lxor, length: 1, execute: lxor }, // 0x83 lxor
    { opcode: .iinc, length: 3, execute: iinc }, // 0x84 iinc
    { opcode: .i2l, length: 1, execute: i2l }, // 0x85 i2l
    { opcode: .i2f, length: 1, execute: i2f }, // 0x86 i2f
    { opcode: .i2d, length: 1, execute: i2d }, // 0x87 i2d
    { opcode: .l2i, length: 1, execute: l2i }, // 0x88 l2i
    { opcode: .l2f, length: 1, execute: l2f }, // 0x89 l2f
    { opcode: .l2d, length: 1, execute: l2d }, // 0x8A l2d
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8B unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8C unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8D unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8E unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8F unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x90 unsupported
    { opcode: .i2b, length: 1, execute: i2b }, // 0x91 i2b
    { opcode: .i2c, length: 1, execute: i2c }, // 0x92 i2c
    { opcode: .i2s, length: 1, execute: i2s }, // 0x93 i2s
    { opcode: .lcmp, length: 1, execute: lcmp }, // 0x94 lcmp
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x95 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x96 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x97 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x98 unsupported
    { opcode: .ifeq, length: 3, execute: ifeq }, // 0x99 ifeq
    { opcode: .ifne, length: 3, execute: ifne }, // 0x9A ifne
    { opcode: .iflt, length: 3, execute: iflt }, // 0x9B iflt
    { opcode: .ifge, length: 3, execute: ifge }, // 0x9C ifge
    { opcode: .ifgt, length: 3, execute: ifgt }, // 0x9D ifgt
    { opcode: .ifle, length: 3, execute: ifle }, // 0x9E ifle
    { opcode: .if_icmpeq, length: 3, execute: if_icmpeq }, // 0x9F if_icmpeq
    { opcode: .if_icmpne, length: 3, execute: if_icmpne }, // 0xA0 if_icmpne
    { opcode: .if_icmplt, length: 3, execute: if_icmplt }, // 0xA1 if_icmplt
    { opcode: .if_icmpge, length: 3, execute: if_icmpge }, // 0xA2 if_icmpge
    { opcode: .if_icmpgt, length: 3, execute: if_icmpgt }, // 0xA3 if_icmpgt
    { opcode: .if_icmple, length: 3, execute: if_icmple }, // 0xA4 if_icmple
    { opcode: .if_acmpeq, length: 3, execute: if_acmpeq }, // 0xA5 if_acmpeq
    { opcode: .if_acmpne, length: 3, execute: if_acmpne }, // 0xA6 if_acmpne
    { opcode: .goto_, length: 3, execute: goto_ }, // 0xA7 goto
    { opcode: .jsr, length: 3, execute: jsr }, // 0xA8 jsr
    { opcode: .ret, length: 2, execute: ret }, // 0xA9 ret
    { opcode: .tableswitch, length: 0, execute: tableswitch }, // 0xAA tableswitch
    { opcode: .lookupswitch, length: 0, execute: lookupswitch }, // 0xAB lookupswitch
    { opcode: .ireturn, length: 1, execute: ireturn }, // 0xAC ireturn
    { opcode: .lreturn, length: 1, execute: lreturn }, // 0xAD lreturn
    { opcode: .freturn, length: 1, execute: freturn }, // 0xAE freturn
    { opcode: .dreturn, length: 1, execute: dreturn }, // 0xAF dreturn
    { opcode: .areturn, length: 1, execute: areturn }, // 0xB0 areturn
    { opcode: .return_, length: 1, execute: return_ }, // 0xB1 return
    { opcode: .getstatic, length: 3, execute: getstatic }, // 0xB2 getstatic
    { opcode: .putstatic, length: 3, execute: putstatic }, // 0xB3 putstatic
    { opcode: .getfield, length: 3, execute: getfield }, // 0xB4 getfield
    { opcode: .putfield, length: 3, execute: putfield }, // 0xB5 putfield
    { opcode: .invoke_virtual, length: 3, execute: invoke_virtual }, // 0xB6 invokevirtual
    { opcode: .invoke_special, length: 3, execute: invoke_special }, // 0xB7 invokespecial
    { opcode: .invoke_static, length: 3, execute: invoke_static }, // 0xB8 invokestatic
    { opcode: .invoke_interface, length: 5, execute: invoke_interface }, // 0xB9 invokeinterface
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xBA unsupported
    { opcode: .new_, length: 3, execute: new_ }, // 0xBB new
    { opcode: .newarray, length: 2, execute: newarray }, // 0xBC newarray
    { opcode: .anewarray, length: 3, execute: anewarray }, // 0xBD anewarray
    { opcode: .arraylength, length: 1, execute: arraylength }, // 0xBE arraylength
    { opcode: .athrow, length: 1, execute: athrow }, // 0xBF athrow
    { opcode: .checkcast, length: 3, execute: checkcast }, // 0xC0 checkcast
    { opcode: .instanceof, length: 3, execute: instanceof }, // 0xC1 instanceof
    { opcode: .monitorenter, length: 1, execute: monitorenter }, // 0xC2 monitorenter
    { opcode: .monitorexit, length: 1, execute: monitorexit }, // 0xC3 monitorexit
    { opcode: .wide, length: 0, execute: wide }, // 0xC4 wide
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC5 unsupported
    { opcode: .ifnull, length: 3, execute: ifnull }, // 0xC6 ifnull
    { opcode: .ifnonnull, length: 3, execute: ifnonnull }, // 0xC7 ifnonnull
    { opcode: .goto_w, length: 5, execute: goto_w }, // 0xC8 goto_w
    { opcode: .jsr_w, length: 5, execute: jsr_w }, // 0xC9 jsr_w
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xCA unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xCB unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xCC unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xCD unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xCE unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xCF unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD0 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD1 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD2 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD3 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD4 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD5 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD6 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD7 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD8 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xD9 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xDA unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xDB unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xDC unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xDD unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xDE unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xDF unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE0 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE1 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE2 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE3 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE4 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE5 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE6 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE7 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE8 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xE9 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xEA unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xEB unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xEC unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xED unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xEE unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xEF unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF0 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF1 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF2 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF3 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF4 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF5 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF6 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF7 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF8 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xF9 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xFA unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xFB unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xFC unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xFD unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xFE unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xFF unsupported
];

pub fn fetch(raw: u8): result<Instruction, InstructionError> {
    const instruction = registry[raw as usize];
    if instruction.opcode == Opcode.unsupported {
        return .err(InstructionError.unsupported_opcode);
    }
    return .ok(instruction);
}

pub fn execute_next(context: &Context): result<void, InstructionError> {
    const pc = context.frame.pc;
    const instruction = try fetch(context.code[pc as usize]);

    const execute = instruction.execute;
    try execute(context);

    if context.frame.result == none and context.frame.pc == pc {
        context.frame.pc = context.frame.pc + instruction.length;
    }
    context.frame.offset = 1;
    return .ok();
}

pub fn execute_method(method: &Method): result<FrameResult, InstructionError> {
    var constant_pool: [:]Constant = [: 0] [];
    var classes: [:]Class = [: 0] [];
    var heap = new_heap();
    var context = Context { class_index: 0, method_index: 0, frame: new_frame(0, 0, method.max_locals, method.max_stack), code: method.code[..], constant_pool: constant_pool[..], classes: classes[..], heap: &heap };

    while context.frame.pc < method.code_len {
        try execute_next(&context);
        if context.frame.result is result {
            const out = result;
            drop context;
            return .ok(out);
        }
    }
    drop context;
    return .err(InstructionError.missing_return);
}

fn assert_int_result(result: FrameResult, expected: i32): void {
    switch result {
    case .return_value(value) {
        if value is actual {
            switch actual {
            case .int_value(int_value) { assert(int_value == expected); }
            else { assert(false); }
            }
        } else {
            assert(false);
        }
    }
    case .exception(reference) {
        const ignored = reference;
        assert(false);
    }
    }
}

fn assert_long_result(result: FrameResult, expected: i64): void {
    switch result {
    case .return_value(value) {
        if value is actual {
            switch actual {
            case .long_value(long_value) { assert(long_value == expected); }
            else { assert(false); }
            }
        } else {
            assert(false);
        }
    }
    case .exception(reference) {
        const ignored = reference;
        assert(false);
    }
    }
}

fn assert_float_result(result: FrameResult, expected: f32): void {
    switch result {
    case .return_value(value) {
        if value is actual {
            switch actual {
            case .float_value(float_value) { assert(float_value == expected); }
            else { assert(false); }
            }
        } else {
            assert(false);
        }
    }
    case .exception(reference) {
        const ignored = reference;
        assert(false);
    }
    }
}

fn assert_double_result(result: FrameResult, expected: f64): void {
    switch result {
    case .return_value(value) {
        if value is actual {
            switch actual {
            case .double_value(double_value) { assert(double_value == expected); }
            else { assert(false); }
            }
        } else {
            assert(false);
        }
    }
    case .exception(reference) {
        const ignored = reference;
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
    case .exception(reference) {
        const ignored = reference;
        assert(false);
    }
    }
}

fn assert_void_result(result: FrameResult): void {
    switch result {
    case .return_value(value) { assert(value == none); }
    case .exception(reference) {
        const ignored = reference;
        assert(false);
    }
    }
}

fn assert_exception_result(result: FrameResult, expected: Reference): void {
    switch result {
    case .return_value(value) {
        const ignored = value;
        assert(false);
    }
    case .exception(reference) {
        assert(reference.equals(expected));
    }
    }
}

test "instruction executes iconst and ireturn" {
    const code: [2]u8 = [4, 172];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "answer",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 2,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 1);
    drop method;
}

test "instruction executes bipush sipush and ireturn" {
    const byte_code: [3]u8 = [16, 254, 172];
    const short_code: [4]u8 = [17, 1, 2, 172];
    var byte_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "byteValue",
        descriptor: "()I",
        code: byte_buffer(byte_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };
    var short_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "shortValue",
        descriptor: "()I",
        code: byte_buffer(short_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const byte_result = try execute_method(&byte_method);
    const short_result = try execute_method(&short_method);
    assert_int_result(byte_result, 0 - 2);
    assert_int_result(short_result, 258);
    drop byte_method;
    drop short_method;
}

test "instruction executes ldc numeric constants" {
    const code: [13]u8 = [
        18, 1, // ldc #1 integer
        19, 0, 2, // ldc_w #2 integer
        20, 0, 3, // ldc2_w #3 long
        18, 5, // ldc #5 float
        20, 0, 6, // ldc2_w #6 double
    ];
    const constant_pool: [8]Constant = [
        .unusable(0),
        .integer(42),
        .integer(67),
        .long(ConstantWide { high_bytes: 0, low_bytes: 42 }),
        .unusable(0),
        .float(0x40000000),
        .double(ConstantWide { high_bytes: 0x40080000, low_bytes: 0 }),
        .unusable(0),
    ];
    var classes: [:]Class = [: 0] [];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 5),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    var step: usize = 0;
    while step < 5 {
        const step_result = execute_next(&context);
        switch step_result {
        case .ok {}
        case .err(error_value) {
            const ignored = error_value;
            assert(false);
        }
        }
        step = step + 1;
    }

    assert_double_result(.return_value(context.frame.pop()), 3.0);
    assert_float_result(.return_value(context.frame.pop()), 2.0);
    assert_long_result(.return_value(context.frame.pop()), 42);
    assert_int_result(.return_value(context.frame.pop()), 67);
    assert_int_result(.return_value(context.frame.pop()), 42);
    drop context;
}

test "instruction caches ldc class constants" {
    const code: [4]u8 = [
        18, 2, // ldc #2 Example.class
        18, 2, // ldc #2 Example.class
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
    ];
    var example_class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
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
    var class_class = Class {
        name: string.from("java/lang/Class".bytes()),
        descriptor: "Ljava/lang/Class;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Class.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var classes: [2]Class = [example_class, class_class];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context);
        switch step_result {
        case .ok {}
        case .err(error_value) {
            const ignored = error_value;
            assert(false);
        }
        }
        step = step + 1;
    }

    var context_classes = context.classes;
    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(context_classes[0].class_object.equals(first));
    assert(heap.objects.len() == 1);
    assert(heap.objects[0].object.class_index == 1);
    drop context;
}

test "instruction interns ldc string constants" {
    const code: [4]u8 = [
        18, 2, // ldc #2 "hello"
        18, 2, // ldc #2 "hello"
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("hello"),
        .string_ref(1),
    ];
    var main_class = Class {
        name: string.from("Main".bytes()),
        descriptor: "LMain;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Main.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var string_class = Class {
        name: string.from("java/lang/String".bytes()),
        descriptor: "Ljava/lang/String;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "String.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var classes: [2]Class = [main_class, string_class];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context);
        switch step_result {
        case .ok {}
        case .err(error_value) {
            const ignored = error_value;
            assert(false);
        }
        }
        step = step + 1;
    }

    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(heap.objects.len() == 1);
    assert(heap.objects[0].object.class_index == 1);
    assert(heap.strings.len() == 1);
    assert(heap.strings[0].value.bytes() == "hello".bytes());
    assert(heap.strings[0].reference.equals(first));
    drop context;
}

test "instruction interns ldc method type constants" {
    const code: [4]u8 = [
        18, 2, // ldc #2 (I)V
        18, 2, // ldc #2 (I)V
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("(I)V"),
        .method_type(1),
    ];
    var main_class = Class {
        name: string.from("Main".bytes()),
        descriptor: "LMain;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Main.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var method_type_class = Class {
        name: string.from("java/lang/invoke/MethodType".bytes()),
        descriptor: "Ljava/lang/invoke/MethodType;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "MethodType.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var classes: [2]Class = [main_class, method_type_class];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context);
        switch step_result {
        case .ok {}
        case .err(error_value) {
            const ignored = error_value;
            assert(false);
        }
        }
        step = step + 1;
    }

    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(heap.objects.len() == 1);
    assert(heap.objects[0].object.class_index == 1);
    assert(heap.method_types.len() == 1);
    assert(heap.method_types[0].descriptor.bytes() == "(I)V".bytes());
    assert(heap.method_types[0].reference.equals(first));
    drop context;
}

test "instruction interns ldc method handle constants" {
    const code: [4]u8 = [
        18, 7, // ldc #7 REF_invokeStatic Main.run:()I
        18, 7, // ldc #7 REF_invokeStatic Main.run:()I
    ];
    const constant_pool: [8]Constant = [
        .unusable(0),
        .utf8("Main"),
        .class_ref(1),
        .utf8("run"),
        .utf8("()I"),
        .name_and_type(ConstantNameAndType { name_index: 3, descriptor_index: 4 }),
        .method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 5 }),
        .method_handle(ConstantMethodHandle { reference_kind: 6, reference_index: 6 }),
    ];
    var main_class = Class {
        name: string.from("Main".bytes()),
        descriptor: "LMain;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Main.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var method_handle_class = Class {
        name: string.from("java/lang/invoke/MethodHandle".bytes()),
        descriptor: "Ljava/lang/invoke/MethodHandle;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "MethodHandle.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var classes: [2]Class = [main_class, method_handle_class];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 2),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    var step: usize = 0;
    while step < 2 {
        const step_result = execute_next(&context);
        switch step_result {
        case .ok {}
        case .err(error_value) {
            const ignored = error_value;
            assert(false);
        }
        }
        step = step + 1;
    }

    const second = expect_ref(context.frame.pop());
    const first = expect_ref(context.frame.pop());
    assert(first.equals(second));
    assert(heap.objects.len() == 1);
    assert(heap.objects[0].object.class_index == 1);
    assert(heap.method_handles.len() == 1);
    assert(heap.method_handles[0].reference_kind == 6);
    assert(heap.method_handles[0].reference_index == 6);
    assert(heap.method_handles[0].reference.equals(first));
    drop context;
}

test "instruction executes field access ops" {
    const code: [12]u8 = [
        179, 0, 6, // putstatic Example.staticValue:I
        178, 0, 6, // getstatic Example.staticValue:I
        181, 0, 9, // putfield Example.instanceValue:I
        180, 0, 9, // getfield Example.instanceValue:I
    ];
    const constant_pool: [10]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
        .utf8("staticValue"),
        .utf8("I"),
        .name_and_type(ConstantNameAndType { name_index: 3, descriptor_index: 4 }),
        .field_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 5 }),
        .utf8("instanceValue"),
        .name_and_type(ConstantNameAndType { name_index: 7, descriptor_index: 4 }),
        .field_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 8 }),
    ];
    const static_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(8),
        name: "staticValue",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(1),
        name: "instanceValue",
        descriptor: "I",
        index: 1,
        slot: 0,
    };
    var class = Class {
        name: string.from("Example".bytes()),
        descriptor: "LExample;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [static_field, instance_field],
        methods: [],
        instance_vars: 1,
        static_vars: [.int_value(0)],
        source_file: "Example.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    var classes: [1]Class = [class];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 4),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };
    var context_classes = context.classes;
    const reference = context.heap.allocate_object(0, &context_classes[0]);

    context.frame.push(.int_value(41));
    const put_static = execute_next(&context);
    switch put_static {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }

    const get_static = execute_next(&context);
    switch get_static {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }

    context.frame.push(.ref_value(reference));
    context.frame.push(.int_value(1));
    const put_instance = execute_next(&context);
    switch put_instance {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }

    context.frame.push(.ref_value(reference));
    const get_instance = execute_next(&context);
    switch get_instance {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }

    assert_int_result(.return_value(context.frame.pop()), 1);
    assert_int_result(.return_value(context.frame.pop()), 41);
    drop context;
}

test "instruction executes invokestatic int method" {
    const constant_pool: [7]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
        .utf8("add"),
        .utf8("(II)I"),
        .name_and_type(ConstantNameAndType { name_index: 3, descriptor_index: 4 }),
        .method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 5 }),
    ];
    const caller_code: [6]u8 = [
        5, // iconst_2
        6, // iconst_3
        184, 0, 6, // invokestatic Example.add:(II)I
        172, // ireturn
    ];
    const add_code: [4]u8 = [
        26, // iload_0
        27, // iload_1
        96, // iadd
        172, // ireturn
    ];
    var classes: [1]Class = [
        Class {
            name: string.from("Example".bytes()),
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 2,
                    max_locals: 0,
                    code_len: 6,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(8),
                    name: "add",
                    descriptor: "(II)I",
                    code: byte_buffer(add_code[..]),
                    max_stack: 2,
                    max_locals: 2,
                    code_len: 4,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 2,
                    return_descriptor: "I",
                },
            ],
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
        },
    ];

    var heap = new_heap();
    const result = try execute_method_frame(0, 0, new_frame(0, 0, 0, 2), constant_pool[..], classes[..], &heap);
    assert_int_result(result, 5);
    drop classes;
}

test "instruction executes new object allocation" {
    const code: [3]u8 = [
        187, 0, 2, // new Example
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
    ];
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(1),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var classes: [1]Class = [
        Class {
            name: string.from("Example".bytes()),
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [instance_field],
            methods: [],
            instance_vars: 1,
            static_vars: [],
            source_file: "Example.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 1),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    const execute_result = execute_next(&context);
    switch execute_result {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }
    const reference = expect_ref(context.frame.pop());
    assert(context.heap.has_object(reference));
    if context.heap.get_field(reference, 0) is value {
        assert_int_result(.return_value(value), 0);
    } else {
        assert(false);
    }
    drop context;
}

test "instruction executes invokespecial constructor initialization" {
    const constant_pool: [11]Constant = [
        .unusable(0),
        .utf8("Example"),
        .class_ref(1),
        .utf8("value"),
        .utf8("I"),
        .name_and_type(ConstantNameAndType { name_index: 3, descriptor_index: 4 }),
        .field_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 5 }),
        .utf8("<init>"),
        .utf8("(I)V"),
        .name_and_type(ConstantNameAndType { name_index: 7, descriptor_index: 8 }),
        .method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 9 }),
    ];
    const caller_code: [9]u8 = [
        187, 0, 2, // new Example
        89, // dup
        8, // iconst_5
        183, 0, 10, // invokespecial Example.<init>:(I)V
        176, // areturn
    ];
    const init_code: [6]u8 = [
        42, // aload_0
        27, // iload_1
        181, 0, 6, // putfield Example.value:I
        177, // return
    ];
    const instance_field = Field {
        class_name: "Example",
        access_flags: field_access_flags(1),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var classes: [1]Class = [
        Class {
            name: string.from("Example".bytes()),
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [instance_field],
            methods: [
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()LExample;",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 3,
                    max_locals: 0,
                    code_len: 9,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "LExample;",
                },
                Method {
                    class_name: "Example",
                    access_flags: method_access_flags(0),
                    name: "<init>",
                    descriptor: "(I)V",
                    code: byte_buffer(init_code[..]),
                    max_stack: 2,
                    max_locals: 2,
                    code_len: 6,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "V",
                },
            ],
            instance_vars: 1,
            static_vars: [],
            source_file: "Example.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();
    const result = try execute_method_frame(0, 0, new_frame(0, 0, 0, 3), constant_pool[..], classes[..], &heap);
    switch result {
    case .return_value(value) {
        if value is actual {
            const reference = expect_ref(actual);
            if heap.get_field(reference, 0) is field_value {
                assert_int_result(.return_value(field_value), 5);
            } else {
                assert(false);
            }
        } else {
            assert(false);
        }
    }
    case .exception(reference) {
        const ignored = reference;
        assert(false);
    }
    }
    drop classes;
}

test "instruction executes invokevirtual override dispatch" {
    const constant_pool: [9]Constant = [
        .unusable(0),
        .utf8("Base"),
        .class_ref(1),
        .utf8("Child"),
        .class_ref(3),
        .utf8("value"),
        .utf8("()I"),
        .name_and_type(ConstantNameAndType { name_index: 5, descriptor_index: 6 }),
        .method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 7 }),
    ];
    const caller_code: [7]u8 = [
        187, 0, 4, // new Child
        182, 0, 8, // invokevirtual Base.value:()I
        172, // ireturn
    ];
    const base_value_code: [2]u8 = [
        4, // iconst_1
        172, // ireturn
    ];
    const child_value_code: [2]u8 = [
        5, // iconst_2
        172, // ireturn
    ];
    var classes: [2]Class = [
        Class {
            name: string.from("Base".bytes()),
            descriptor: "LBase;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Base",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 7,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Base",
                    access_flags: method_access_flags(0),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(base_value_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Base.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Child".bytes()),
            descriptor: "LChild;",
            access_flags: class_access_flags(0x0021),
            super_class: "Base",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Child",
                    access_flags: method_access_flags(0),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(child_value_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Child.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();
    const result = try execute_method_frame(0, 0, new_frame(0, 0, 0, 1), constant_pool[..], classes[..], &heap);
    assert_int_result(result, 2);
    drop classes;
}

test "instruction executes invokeinterface implementation dispatch" {
    const constant_pool: [9]Constant = [
        .unusable(0),
        .utf8("Iface"),
        .class_ref(1),
        .utf8("Impl"),
        .class_ref(3),
        .utf8("value"),
        .utf8("()I"),
        .name_and_type(ConstantNameAndType { name_index: 5, descriptor_index: 6 }),
        .interface_method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 7 }),
    ];
    const caller_code: [9]u8 = [
        187, 0, 4, // new Impl
        185, 0, 8, 1, 0, // invokeinterface Iface.value:()I
        172, // ireturn
    ];
    const impl_value_code: [2]u8 = [
        6, // iconst_3
        172, // ireturn
    ];
    const interface_code: [0]u8 = [];
    var classes: [2]Class = [
        Class {
            name: string.from("Iface".bytes()),
            descriptor: "LIface;",
            access_flags: class_access_flags(0x0601),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Iface",
                    access_flags: method_access_flags(0x0401),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(interface_code[..]),
                    max_stack: 0,
                    max_locals: 1,
                    code_len: 0,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Iface.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Impl".bytes()),
            descriptor: "LImpl;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: ["Iface"],
            fields: [],
            methods: [
                Method {
                    class_name: "Impl",
                    access_flags: method_access_flags(8),
                    name: "caller",
                    descriptor: "()I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 9,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Impl",
                    access_flags: method_access_flags(0),
                    name: "value",
                    descriptor: "()I",
                    code: byte_buffer(impl_value_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
        exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Impl.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();
    const result = try execute_method_frame(1, 0, new_frame(1, 0, 0, 1), constant_pool[..], classes[..], &heap);
    assert_int_result(result, 3);
    drop classes;
}

test "instruction executes int local shorthand load store and add" {
    const code: [9]u8 = [
        5, // iconst_2
        59, // istore_0
        16, 40, // bipush 40
        60, // istore_1
        26, // iload_0
        27, // iload_1
        96, // iadd
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "sumShortForms",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 2,
        code_len: 9,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes int local operand load store and add" {
    const code: [13]u8 = [
        16, 41, // bipush 41
        54, 2, // istore 2
        4, // iconst_1
        54, 3, // istore 3
        21, 2, // iload 2
        21, 3, // iload 3
        96, // iadd
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "sumOperandForms",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 4,
        code_len: 13,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes int subtract multiply and negate" {
    const code: [10]u8 = [
        16, 50, // bipush 50
        16, 8, // bipush 8
        100, // isub
        4, // iconst_1
        104, // imul
        116, // ineg
        116, // ineg
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intArithmetic",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes float load store arithmetic and return" {
    const code: [14]u8 = [
        13, // fconst_2
        67, // fstore_0
        34, // fload_0
        12, // fconst_1
        98, // fadd
        13, // fconst_2
        106, // fmul
        12, // fconst_1
        102, // fsub
        12, // fconst_1
        110, // fdiv
        118, // fneg
        118, // fneg
        174, // freturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "floatArithmetic",
        descriptor: "()F",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const result = try execute_method(&method);
    assert_float_result(result, 5.0);
    drop method;
}

test "instruction executes double load store arithmetic and return" {
    const code: [18]u8 = [
        15, // dconst_1
        57, 2, // dstore 2
        24, 2, // dload 2
        15, // dconst_1
        99, // dadd
        15, // dconst_1
        99, // dadd
        15, // dconst_1
        103, // dsub
        15, // dconst_1
        107, // dmul
        15, // dconst_1
        111, // ddiv
        119, // dneg
        119, // dneg
        175, // dreturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "doubleArithmetic",
        descriptor: "()D",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 4,
        code_len: 18,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const result = try execute_method(&method);
    assert_double_result(result, 2.0);
    drop method;
}

test "instruction executes integer division and remainder normal paths" {
    const code: [13]u8 = [
        16, 43, // bipush 43
        5, // iconst_2
        108, // idiv
        16, 43, // bipush 43
        5, // iconst_2
        112, // irem
        96, // iadd
        16, 10, // bipush 10
        96, // iadd
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intDivRem",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 3,
        max_locals: 0,
        code_len: 13,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 32);
    drop method;
}

test "instruction executes long division and remainder normal paths" {
    const code: [14]u8 = [
        16, 42, // bipush 42
        133, // i2l
        5, // iconst_2
        133, // i2l
        109, // ldiv
        16, 43, // bipush 43
        133, // i2l
        5, // iconst_2
        133, // i2l
        113, // lrem
        97, // ladd
        173, // lreturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longDivRem",
        descriptor: "()J",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const result = try execute_method(&method);
    assert_long_result(result, 22);
    drop method;
}

test "instruction executes stack manipulation ops" {
    const first_code: [7]u8 = [
        16, 41, // bipush 41
        4, // iconst_1
        90, // dup_x1
        87, // pop
        96, // iadd
        172, // ireturn
    ];
    var first_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDupX1",
        descriptor: "()I",
        code: byte_buffer(first_code[..]),
        max_stack: 3,
        max_locals: 0,
        code_len: 7,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const first_result = try execute_method(&first_method);
    assert_int_result(first_result, 42);
    drop first_method;

    const second_code: [11]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        89, // dup
        87, // pop
        95, // swap
        100, // isub
        116, // ineg
        7, // iconst_4
        96, // iadd
        172, // ireturn
    ];
    var second_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDupSwap",
        descriptor: "()I",
        code: byte_buffer(second_code[..]),
        max_stack: 3,
        max_locals: 0,
        code_len: 11,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const second_result = try execute_method(&second_method);
    assert_int_result(second_result, 42);
    drop second_method;

    const third_code: [6]u8 = [
        4, // iconst_1
        5, // iconst_2
        88, // pop2
        16, 42, // bipush 42
        172, // ireturn
    ];
    var third_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackPop2",
        descriptor: "()I",
        code: byte_buffer(third_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 6,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const third_result = try execute_method(&third_method);
    assert_int_result(third_result, 42);
    drop third_method;

    const fourth_code: [8]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        3, // iconst_0
        91, // dup_x2
        87, // pop
        96, // iadd
        172, // ireturn
    ];
    var fourth_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDupX2",
        descriptor: "()I",
        code: byte_buffer(fourth_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const fourth_result = try execute_method(&fourth_method);
    assert_int_result(fourth_result, 42);
    drop fourth_method;

    const fifth_code: [8]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        92, // dup2
        96, // iadd
        96, // iadd
        96, // iadd
        172, // ireturn
    ];
    var fifth_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDup2",
        descriptor: "()I",
        code: byte_buffer(fifth_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const fifth_result = try execute_method(&fifth_method);
    assert_int_result(fifth_result, 84);
    drop fifth_method;

    const sixth_code: [10]u8 = [
        16, 40, // bipush 40
        3, // iconst_0
        5, // iconst_2
        93, // dup2_x1
        87, // pop
        87, // pop
        95, // swap
        96, // iadd
        172, // ireturn
    ];
    var sixth_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDup2X1",
        descriptor: "()I",
        code: byte_buffer(sixth_code[..]),
        max_stack: 5,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const sixth_result = try execute_method(&sixth_method);
    assert_int_result(sixth_result, 42);
    drop sixth_method;

    const seventh_code: [10]u8 = [
        16, 40, // bipush 40
        5, // iconst_2
        3, // iconst_0
        3, // iconst_0
        94, // dup2_x2
        87, // pop
        87, // pop
        96, // iadd
        172, // ireturn
    ];
    var seventh_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "stackDup2X2",
        descriptor: "()I",
        code: byte_buffer(seventh_code[..]),
        max_stack: 6,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const seventh_result = try execute_method(&seventh_method);
    assert_int_result(seventh_result, 42);
    drop seventh_method;
}

test "instruction executes iinc shifts and bitwise int ops" {
    const code: [24]u8 = [
        16, 50, // bipush 50
        59, // istore_0
        132, 0, 248, // iinc 0, -8
        26, // iload_0
        4, // iconst_1
        120, // ishl
        4, // iconst_1
        122, // ishr
        16, 63, // bipush 63
        126, // iand
        16, 10, // bipush 10
        128, // ior
        16, 15, // bipush 15
        130, // ixor
        16, 15, // bipush 15
        130, // ixor
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intBitwise",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 1,
        code_len: 24,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes wide local access and iinc" {
    const code: [17]u8 = [
        16, 40, // bipush 40
        196, 54, 1, 4, // wide istore 260
        196, 132, 1, 4, 0, 2, // wide iinc 260, 2
        196, 21, 1, 4, // wide iload 260
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "wideLocals",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 261,
        code_len: 17,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes logical right shifts" {
    const int_code: [4]u8 = [
        2, // iconst_m1
        4, // iconst_1
        124, // iushr
        172, // ireturn
    ];
    var int_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intLogicalRightShift",
        descriptor: "()I",
        code: byte_buffer(int_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const int_result = try execute_method(&int_method);
    assert_int_result(int_result, 2147483647);
    drop int_method;

    const long_code: [7]u8 = [
        9, // lconst_0
        10, // lconst_1
        101, // lsub
        16, 63, // bipush 63
        125, // lushr
        173, // lreturn
    ];
    var long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longLogicalRightShift",
        descriptor: "()J",
        code: byte_buffer(long_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 7,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const long_result = try execute_method(&long_method);
    assert_long_result(long_result, 1);
    drop long_method;
}

test "instruction executes int and long conversions" {
    const int_to_long_code: [3]u8 = [
        2, // iconst_m1
        133, // i2l
        173, // lreturn
    ];
    var int_to_long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToLong",
        descriptor: "()J",
        code: byte_buffer(int_to_long_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const int_to_long_result = try execute_method(&int_to_long_method);
    assert_long_result(int_to_long_result, 0 - 1);
    drop int_to_long_method;

    const long_to_int_code: [8]u8 = [
        10, // lconst_1
        16, 32, // bipush 32
        121, // lshl
        10, // lconst_1
        129, // lor
        136, // l2i
        172, // ireturn
    ];
    var long_to_int_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longToInt",
        descriptor: "()I",
        code: byte_buffer(long_to_int_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const long_to_int_result = try execute_method(&long_to_int_method);
    assert_int_result(long_to_int_result, 1);
    drop long_to_int_method;
}

test "instruction executes integer to float and double conversions" {
    const int_to_float_code: [4]u8 = [
        16, 42, // bipush 42
        134, // i2f
        174, // freturn
    ];
    var int_to_float_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToFloat",
        descriptor: "()F",
        code: byte_buffer(int_to_float_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const int_to_float_result = try execute_method(&int_to_float_method);
    assert_float_result(int_to_float_result, 42.0);
    drop int_to_float_method;

    const int_to_double_code: [4]u8 = [
        16, 42, // bipush 42
        135, // i2d
        175, // dreturn
    ];
    var int_to_double_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToDouble",
        descriptor: "()D",
        code: byte_buffer(int_to_double_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const int_to_double_result = try execute_method(&int_to_double_method);
    assert_double_result(int_to_double_result, 42.0);
    drop int_to_double_method;

    const long_to_float_code: [5]u8 = [
        16, 42, // bipush 42
        133, // i2l
        137, // l2f
        174, // freturn
    ];
    var long_to_float_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longToFloat",
        descriptor: "()F",
        code: byte_buffer(long_to_float_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 5,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const long_to_float_result = try execute_method(&long_to_float_method);
    assert_float_result(long_to_float_result, 42.0);
    drop long_to_float_method;

    const long_to_double_code: [5]u8 = [
        16, 42, // bipush 42
        133, // i2l
        138, // l2d
        175, // dreturn
    ];
    var long_to_double_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longToDouble",
        descriptor: "()D",
        code: byte_buffer(long_to_double_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 5,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const long_to_double_result = try execute_method(&long_to_double_method);
    assert_double_result(long_to_double_result, 42.0);
    drop long_to_double_method;
}

test "instruction executes int byte char and short conversions" {
    const byte_code: [5]u8 = [
        17, 0, 128, // sipush 128
        145, // i2b
        172, // ireturn
    ];
    var byte_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToByte",
        descriptor: "()I",
        code: byte_buffer(byte_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 5,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const byte_result = try execute_method(&byte_method);
    assert_int_result(byte_result, 0 - 128);
    drop byte_method;

    const char_code: [3]u8 = [
        2, // iconst_m1
        146, // i2c
        172, // ireturn
    ];
    var char_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToChar",
        descriptor: "()I",
        code: byte_buffer(char_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const char_result = try execute_method(&char_method);
    assert_int_result(char_result, 65535);
    drop char_method;

    const short_code: [6]u8 = [
        4, // iconst_1
        16, 15, // bipush 15
        120, // ishl
        147, // i2s
        172, // ireturn
    ];
    var short_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intToShort",
        descriptor: "()I",
        code: byte_buffer(short_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 6,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const short_result = try execute_method(&short_method);
    assert_int_result(short_result, 0 - 32768);
    drop short_method;
}

test "instruction executes unary int branches" {
    const code: [45]u8 = [
        3, // iconst_0
        153, 0, 6, // ifeq ok1
        16, 0, // bipush 0
        172, // ireturn
        4, // iconst_1
        154, 0, 6, // ifne ok2
        16, 0, // bipush 0
        172, // ireturn
        2, // iconst_m1
        155, 0, 6, // iflt ok3
        16, 0, // bipush 0
        172, // ireturn
        3, // iconst_0
        156, 0, 6, // ifge ok4
        16, 0, // bipush 0
        172, // ireturn
        4, // iconst_1
        157, 0, 6, // ifgt ok5
        16, 0, // bipush 0
        172, // ireturn
        3, // iconst_0
        158, 0, 6, // ifle ok6
        16, 0, // bipush 0
        172, // ireturn
        16, 42, // bipush 42
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "unaryBranches",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 45,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes int compare branches and goto loop" {
    const code: [31]u8 = [
        3, // iconst_0
        59, // istore_0
        3, // iconst_0
        60, // istore_1
        26, // iload_0
        16, 7, // bipush 7
        162, 0, 13, // if_icmpge end
        27, // iload_1
        26, // iload_0
        96, // iadd
        60, // istore_1
        132, 0, 1, // iinc 0, 1
        167, 255, 243, // goto loop
        27, // iload_1
        16, 21, // bipush 21
        160, 0, 6, // if_icmpne fail
        16, 42, // bipush 42
        172, // ireturn
        3, // iconst_0
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "compareLoop",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 2,
        code_len: 31,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes table and lookup switches" {
    const table_code: [40]u8 = [
        4, // iconst_1
        170, // tableswitch
        0, 0, // padding
        0, 0, 0, 27, // default
        0, 0, 0, 0, // low
        0, 0, 0, 2, // high
        0, 0, 0, 30, // case 0
        0, 0, 0, 33, // case 1
        0, 0, 0, 36, // case 2
        16, 0, 172, // default: return 0
        16, 10, 172, // case 0: return 10
        16, 42, 172, // case 1: return 42
        16, 7, 172, // case 2: return 7
    ];
    var table_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "tableSwitch",
        descriptor: "()I",
        code: byte_buffer(table_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 40,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const table_result = try execute_method(&table_method);
    assert_int_result(table_result, 42);
    drop table_method;

    const lookup_code: [37]u8 = [
        5, // iconst_2
        171, // lookupswitch
        0, 0, // padding
        0, 0, 0, 27, // default
        0, 0, 0, 2, // npairs
        255, 255, 255, 255, // match -1
        0, 0, 0, 30, // case -1
        0, 0, 0, 2, // match 2
        0, 0, 0, 33, // case 2
        16, 0, 172, // default: return 0
        16, 10, 172, // case -1: return 10
        16, 42, 172, // case 2: return 42
    ];
    var lookup_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "lookupSwitch",
        descriptor: "()I",
        code: byte_buffer(lookup_code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 37,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const lookup_result = try execute_method(&lookup_method);
    assert_int_result(lookup_result, 42);
    drop lookup_method;
}

test "instruction executes jsr ret and jsr_w subroutines" {
    const jsr_code: [9]u8 = [
        168, 0, 6, // jsr subroutine
        16, 42, // bipush 42
        172, // ireturn
        75, // astore_0
        169, 0, // ret 0
    ];
    var jsr_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "jsrRet",
        descriptor: "()I",
        code: byte_buffer(jsr_code[..]),
        max_stack: 1,
        max_locals: 1,
        code_len: 9,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const jsr_result = try execute_method(&jsr_method);
    assert_int_result(jsr_result, 42);
    drop jsr_method;

    const wide_ret_code: [14]u8 = [
        168, 0, 6, // jsr subroutine
        16, 42, // bipush 42
        172, // ireturn
        196, 58, 1, 4, // wide astore 260
        196, 169, 1, 4, // wide ret 260
    ];
    var wide_ret_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "wideRet",
        descriptor: "()I",
        code: byte_buffer(wide_ret_code[..]),
        max_stack: 1,
        max_locals: 261,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const wide_ret_result = try execute_method(&wide_ret_method);
    assert_int_result(wide_ret_result, 42);
    drop wide_ret_method;

    const jsr_w_code: [11]u8 = [
        201, 0, 0, 0, 8, // jsr_w subroutine
        16, 42, // bipush 42
        172, // ireturn
        75, // astore_0
        169, 0, // ret 0
    ];
    var jsr_w_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "jsrWide",
        descriptor: "()I",
        code: byte_buffer(jsr_w_code[..]),
        max_stack: 1,
        max_locals: 1,
        code_len: 11,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const jsr_w_result = try execute_method(&jsr_w_method);
    assert_int_result(jsr_w_result, 42);
    drop jsr_w_method;
}

test "instruction executes nop and goto_w" {
    const code: [12]u8 = [
        0, // nop
        200, 0, 0, 0, 8, // goto_w target
        16, 0, // bipush skipped
        172, // ireturn skipped
        16, 42, // bipush target
        172, // ireturn target
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "nopGotoWide",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 1,
        max_locals: 0,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes reference load store and returns" {
    const ref_code: [4]u8 = [
        1, // aconst_null
        76, // astore_1
        43, // aload_1
        176, // areturn
    ];
    var ref_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "returnNull",
        descriptor: "()Ljava/lang/Object;",
        code: byte_buffer(ref_code[..]),
        max_stack: 1,
        max_locals: 2,
        code_len: 4,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "Ljava/lang/Object;",
    };

    const ref_result = try execute_method(&ref_method);
    assert_null_ref_result(ref_result);
    drop ref_method;

    const void_code: [1]u8 = [
        177, // return
    ];
    var void_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "returnVoid",
        descriptor: "()V",
        code: byte_buffer(void_code[..]),
        max_stack: 0,
        max_locals: 0,
        code_len: 1,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "V",
    };

    const void_result = try execute_method(&void_method);
    assert_void_result(void_result);
    drop void_method;
}

test "instruction executes athrow with existing exception reference" {
    const code: [1]u8 = [191];
    var constant_pool: [:]Constant = [: 0] [];
    var classes: [:]Class = [: 0] [];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 1),
        code: code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };
    const exception = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    context.frame.push(.ref_value(exception));

    const execute_result = execute_next(&context);
    switch execute_result {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }

    if context.frame.result is result {
        assert_exception_result(result, exception);
    } else {
        assert(false);
    }
    drop context;
}

test "instruction dispatches local exception handler" {
    const code: [5]u8 = [
        42, // aload_0
        191, // athrow
        76, // astore_1 handler
        8, // iconst_5
        172, // ireturn
    ];
    var constant_pool: [:]Constant = [: 0] [];
    const handler = ExceptionHandler {
        start_pc: 0,
        end_pc: 2,
        handle_pc: 2,
        catch_type: 0,
    };
    var classes: [2]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(8),
                    name: "catchLocal",
                    descriptor: "(Ljava/lang/Throwable;)I",
                    code: byte_buffer(code[..]),
                    max_stack: 1,
                    max_locals: 2,
                    code_len: 5,
                    exception_count: 1,
                    exception_handlers: [handler],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Throwable".bytes()),
            descriptor: "LThrowable;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Throwable.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();
    var frame = new_frame(0, 0, 2, 1);
    const exception = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    frame.store(0, .ref_value(exception));

    const result = try execute_method_frame(0, 0, frame, constant_pool[..], classes[..], &heap);
    assert_int_result(result, 5);
    drop classes;
}

test "instruction dispatches propagated call exception handler" {
    const constant_pool: [7]Constant = [
        .unusable(0),
        .utf8("Helper"),
        .class_ref(1),
        .utf8("throwIt"),
        .utf8("(Ljava/lang/Throwable;)I"),
        .name_and_type(ConstantNameAndType { name_index: 3, descriptor_index: 4 }),
        .method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 5 }),
    ];
    const caller_code: [7]u8 = [
        42, // aload_0
        184, 0, 6, // invokestatic Helper.throwIt
        76, // astore_1 handler
        6, // iconst_3
        172, // ireturn
    ];
    const callee_code: [2]u8 = [
        42, // aload_0
        191, // athrow
    ];
    const caller_handler = ExceptionHandler {
        start_pc: 1,
        end_pc: 4,
        handle_pc: 4,
        catch_type: 0,
    };
    var classes: [3]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(8),
                    name: "catchCall",
                    descriptor: "(Ljava/lang/Throwable;)I",
                    code: byte_buffer(caller_code[..]),
                    max_stack: 1,
                    max_locals: 2,
                    code_len: 7,
                    exception_count: 1,
                    exception_handlers: [caller_handler],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Helper".bytes()),
            descriptor: "LHelper;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Helper",
                    access_flags: method_access_flags(8),
                    name: "throwIt",
                    descriptor: "(Ljava/lang/Throwable;)I",
                    code: byte_buffer(callee_code[..]),
                    max_stack: 1,
                    max_locals: 1,
                    code_len: 2,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 1,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Helper.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Throwable".bytes()),
            descriptor: "LThrowable;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Throwable.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();
    var frame = new_frame(0, 0, 2, 1);
    const exception = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    frame.store(0, .ref_value(exception));

    const result = try execute_method_frame(0, 0, frame, constant_pool[..], classes[..], &heap);
    assert_int_result(result, 3);
    drop classes;
}

test "instruction executes int array creation load store and length" {
    const code: [18]u8 = [
        6, // iconst_3
        188, 10, // newarray int
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        16, 41, // bipush 41
        79, // iastore
        42, // aload_0
        4, // iconst_1
        46, // iaload
        42, // aload_0
        190, // arraylength
        96, // iadd
        5, // iconst_2
        100, // isub
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "intArray",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 18,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes anewarray reference array creation" {
    const code: [8]u8 = [
        5, // iconst_2
        189, 0, 2, // anewarray java/lang/Object
        75, // astore_0
        42, // aload_0
        190, // arraylength
        172, // ireturn
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("java/lang/Object"),
        .class_ref(1),
    ];
    var classes: [1]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "referenceArray",
                    descriptor: "()I",
                    code: byte_buffer(code[..]),
                    max_stack: 2,
                    max_locals: 1,
                    code_len: 8,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();

    const result = try execute_method_frame(0, 0, new_frame(0, 0, classes[0].methods[0].max_locals, classes[0].methods[0].max_stack), constant_pool[..], classes[..], &heap);
    assert_int_result(result, 2);
    switch heap.arrays[0].array.elements[0] {
    case .ref_value(reference) { assert(reference.is_null()); }
    else { assert(false); }
    }
    drop classes;
}

test "instruction executes checkcast and instanceof normal paths" {
    const pass_code: [10]u8 = [
        187, 0, 2, // new Child
        192, 0, 4, // checkcast Base
        193, 0, 6, // instanceof Iface
        172, // ireturn
    ];
    const null_code: [5]u8 = [
        1, // aconst_null
        193, 0, 4, // instanceof Base
        172, // ireturn
    ];
    const miss_code: [7]u8 = [
        187, 0, 8, // new Other
        193, 0, 6, // instanceof Iface
        172, // ireturn
    ];
    const constant_pool: [9]Constant = [
        .unusable(0),
        .utf8("Child"),
        .class_ref(1),
        .utf8("Base"),
        .class_ref(3),
        .utf8("Iface"),
        .class_ref(5),
        .utf8("Other"),
        .class_ref(7),
    ];
    var classes: [5]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "pass",
                    descriptor: "()I",
                    code: byte_buffer(pass_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 10,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "nullCheck",
                    descriptor: "()I",
                    code: byte_buffer(null_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 5,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "miss",
                    descriptor: "()I",
                    code: byte_buffer(miss_code[..]),
                    max_stack: 1,
                    max_locals: 0,
                    code_len: 7,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Base".bytes()),
            descriptor: "LBase;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Base.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Child".bytes()),
            descriptor: "LChild;",
            access_flags: class_access_flags(0x0021),
            super_class: "Base",
            interfaces: ["Iface"],
            fields: [],
            methods: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Child.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Iface".bytes()),
            descriptor: "LIface;",
            access_flags: class_access_flags(0x0601),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Iface.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: string.from("Other".bytes()),
            descriptor: "LOther;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Other.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();

    const pass_result = try execute_method_frame(0, 0, new_frame(0, 0, classes[0].methods[0].max_locals, classes[0].methods[0].max_stack), constant_pool[..], classes[..], &heap);
    const null_result = try execute_method_frame(0, 1, new_frame(0, 1, classes[0].methods[1].max_locals, classes[0].methods[1].max_stack), constant_pool[..], classes[..], &heap);
    const miss_result = try execute_method_frame(0, 2, new_frame(0, 2, classes[0].methods[2].max_locals, classes[0].methods[2].max_stack), constant_pool[..], classes[..], &heap);
    assert_int_result(pass_result, 1);
    assert_int_result(null_result, 0);
    assert_int_result(miss_result, 0);
    drop classes;
}

test "instruction executes monitorenter and monitorexit normal paths" {
    const code: [8]u8 = [
        187, 0, 2, // new Main
        89, // dup
        194, // monitorenter
        195, // monitorexit
        4, // iconst_1
        172, // ireturn
    ];
    const constant_pool: [3]Constant = [
        .unusable(0),
        .utf8("Main"),
        .class_ref(1),
    ];
    var classes: [1]Class = [
        Class {
            name: string.from("Main".bytes()),
            descriptor: "LMain;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [
                Method {
                    class_name: "Main",
                    access_flags: method_access_flags(0),
                    name: "monitor",
                    descriptor: "()I",
                    code: byte_buffer(code[..]),
                    max_stack: 2,
                    max_locals: 0,
                    code_len: 8,
                    exception_count: 0,
                    exception_handlers: [],
                    local_var_count: 0,
                    line_number_count: 0,
                    parameter_count: 0,
                    return_descriptor: "I",
                },
            ],
            instance_vars: 0,
            static_vars: [],
            source_file: "Main.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
    ];
    var heap = new_heap();

    const result = try execute_method_frame(0, 0, new_frame(0, 0, classes[0].methods[0].max_locals, classes[0].methods[0].max_stack), constant_pool[..], classes[..], &heap);
    assert_int_result(result, 1);
    assert(heap.objects.len() == 1);
    drop classes;
}

test "instruction executes wide and floating array load store ops" {
    const long_code: [14]u8 = [
        5, // iconst_2
        188, 11, // newarray long
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        16, 42, // bipush 42
        133, // i2l
        80, // lastore
        42, // aload_0
        4, // iconst_1
        47, // laload
        173, // lreturn
    ];
    var long_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longArray",
        descriptor: "()J",
        code: byte_buffer(long_code[..]),
        max_stack: 4,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const long_result = try execute_method(&long_method);
    assert_long_result(long_result, 42);
    drop long_method;

    const float_code: [12]u8 = [
        5, // iconst_2
        188, 6, // newarray float
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        13, // fconst_2
        81, // fastore
        42, // aload_0
        4, // iconst_1
        48, // faload
        174, // freturn
    ];
    var float_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "floatArray",
        descriptor: "()F",
        code: byte_buffer(float_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "F",
    };

    const float_result = try execute_method(&float_method);
    assert_float_result(float_result, 2.0);
    drop float_method;

    const double_code: [12]u8 = [
        5, // iconst_2
        188, 7, // newarray double
        75, // astore_0
        42, // aload_0
        4, // iconst_1
        15, // dconst_1
        82, // dastore
        42, // aload_0
        4, // iconst_1
        49, // daload
        175, // dreturn
    ];
    var double_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "doubleArray",
        descriptor: "()D",
        code: byte_buffer(double_code[..]),
        max_stack: 4,
        max_locals: 1,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "D",
    };

    const double_result = try execute_method(&double_method);
    assert_double_result(double_result, 1.0);
    drop double_method;
}

test "instruction executes narrow array load store ops" {
    const byte_code: [14]u8 = [
        4, // iconst_1
        188, 8, // newarray byte
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        17, 0, 255, // sipush 255
        84, // bastore
        42, // aload_0
        3, // iconst_0
        51, // baload
        172, // ireturn
    ];
    var byte_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "byteArray",
        descriptor: "()I",
        code: byte_buffer(byte_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const byte_result = try execute_method(&byte_method);
    assert_int_result(byte_result, 0 - 1);
    drop byte_method;

    const char_code: [14]u8 = [
        4, // iconst_1
        188, 5, // newarray char
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        17, 0, 255, // sipush 255
        85, // castore
        42, // aload_0
        3, // iconst_0
        52, // caload
        172, // ireturn
    ];
    var char_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "charArray",
        descriptor: "()I",
        code: byte_buffer(char_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const char_result = try execute_method(&char_method);
    assert_int_result(char_result, 255);
    drop char_method;

    const short_code: [14]u8 = [
        4, // iconst_1
        188, 9, // newarray short
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        17, 128, 0, // sipush -32768
        86, // sastore
        42, // aload_0
        3, // iconst_0
        53, // saload
        172, // ireturn
    ];
    var short_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "shortArray",
        descriptor: "()I",
        code: byte_buffer(short_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 14,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const short_result = try execute_method(&short_method);
    assert_int_result(short_result, 0 - 32768);
    drop short_method;

    const boolean_code: [12]u8 = [
        4, // iconst_1
        188, 4, // newarray boolean
        75, // astore_0
        42, // aload_0
        3, // iconst_0
        4, // iconst_1
        84, // bastore
        42, // aload_0
        3, // iconst_0
        51, // baload
        172, // ireturn
    ];
    var boolean_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "booleanArray",
        descriptor: "()I",
        code: byte_buffer(boolean_code[..]),
        max_stack: 3,
        max_locals: 1,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const boolean_result = try execute_method(&boolean_method);
    assert_int_result(boolean_result, 1);
    drop boolean_method;
}

test "instruction executes reference array load store ops" {
    const store_code: [1]u8 = [83];
    var constant_pool: [:]Constant = [: 0] [];
    var classes: [:]Class = [: 0] [];
    var heap = new_heap();
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 3),
        code: store_code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };
    const reference = context.heap.allocate_array(0, "Ljava/lang/Object;", 1);

    context.frame.push(.ref_value(reference));
    push_int(&context, 0);
    context.frame.push(.ref_value(null_ref));
    const store_result = execute_next(&context);
    switch store_result {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }

    const load_code: [1]u8 = [50];
    context.frame.clear();
    context.frame.pc = 0;
    context.frame.offset = 1;
    context.code = load_code[..];
    context.frame.push(.ref_value(reference));
    push_int(&context, 0);
    const load_result = execute_next(&context);
    switch load_result {
    case .ok {}
    case .err(error_value) {
        const ignored = error_value;
        assert(false);
    }
    }

    const loaded = expect_ref(context.frame.pop());
    assert(loaded.is_null());
    drop context;
}

test "instruction executes reference comparison and null branches" {
    const code: [29]u8 = [
        1, // aconst_null
        75, // astore_0
        42, // aload_0
        198, 0, 5, // ifnull ok1
        3, // iconst_0
        172, // ireturn
        42, // aload_0
        199, 0, 18, // ifnonnull fail
        1, // aconst_null
        42, // aload_0
        165, 0, 5, // if_acmpeq ok2
        3, // iconst_0
        172, // ireturn
        42, // aload_0
        1, // aconst_null
        166, 0, 6, // if_acmpne fail
        16, 42, // bipush 42
        172, // ireturn
        3, // iconst_0
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "refBranches",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 2,
        max_locals: 1,
        code_len: 29,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
    drop method;
}

test "instruction executes long local arithmetic and return" {
    const code: [12]u8 = [
        10, // lconst_1
        64, // lstore_1
        31, // lload_1
        31, // lload_1
        97, // ladd
        31, // lload_1
        101, // lsub
        31, // lload_1
        105, // lmul
        117, // lneg
        117, // lneg
        173, // lreturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longArithmetic",
        descriptor: "()J",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 3,
        code_len: 12,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const result = try execute_method(&method);
    assert_long_result(result, 1);
    drop method;
}

test "instruction executes long shifts and bitwise ops" {
    const shift_code: [8]u8 = [
        10, // lconst_1
        16, 6, // bipush 6
        121, // lshl
        16, 1, // bipush 1
        123, // lshr
        173, // lreturn
    ];
    var shift_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longBitwise",
        descriptor: "()J",
        code: byte_buffer(shift_code[..]),
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const shift_result = try execute_method(&shift_method);
    assert_long_result(shift_result, 32);
    drop shift_method;

    const bitwise_code: [10]u8 = [
        10, // lconst_1
        9, // lconst_0
        127, // land
        10, // lconst_1
        129, // lor
        10, // lconst_1
        131, // lxor
        10, // lconst_1
        131, // lxor
        173, // lreturn
    ];
    var bitwise_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longBitwise",
        descriptor: "()J",
        code: byte_buffer(bitwise_code[..]),
        max_stack: 2,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const bitwise_result = try execute_method(&bitwise_method);
    assert_long_result(bitwise_result, 1);
    drop bitwise_method;
}

test "instruction executes long operand load store and compare" {
    const code: [17]u8 = [
        10, // lconst_1
        55, 2, // lstore 2
        22, 2, // lload 2
        10, // lconst_1
        148, // lcmp
        153, 0, 5, // ifeq ok1
        3, // iconst_0
        172, // ireturn
        9, // lconst_0
        22, 2, // lload 2
        148, // lcmp
        172, // ireturn
    ];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "longCompare",
        descriptor: "()I",
        code: byte_buffer(code[..]),
        max_stack: 4,
        max_locals: 4,
        code_len: 17,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 0 - 1);
    drop method;
}

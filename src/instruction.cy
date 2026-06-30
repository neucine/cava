import { Context, Frame, FrameResult, new_frame } from .engine;
import { Method, Reference, Value, method_access_flags, null_ref } from .types;

pub enum InstructionError: i32 {
    unsupported_opcode = 0,
    missing_return,
}

pub enum Opcode: i32 {
    unsupported = 0,
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
    bipush = 16,
    sipush = 17,
    iload = 21,
    lload,
    aload = 25,
    iload_0 = 26,
    iload_1,
    iload_2,
    iload_3,
    lload_0,
    lload_1,
    lload_2,
    lload_3,
    aload_0 = 42,
    aload_1,
    aload_2,
    aload_3,
    istore = 54,
    lstore,
    astore = 58,
    istore_0 = 59,
    istore_1,
    istore_2,
    istore_3,
    lstore_0,
    lstore_1,
    lstore_2,
    lstore_3,
    astore_0 = 75,
    astore_1,
    astore_2,
    astore_3,
    pop = 87,
    pop2,
    dup,
    dup_x1,
    swap = 95,
    iadd = 96,
    ladd,
    isub = 100,
    lsub,
    imul = 104,
    lmul,
    ineg = 116,
    lneg,
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
    ireturn = 172,
    lreturn,
    areturn = 176,
    return_ = 177,
    ifnull = 198,
    ifnonnull,
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

fn load_int(context: &Context, index: u16): void {
    push_int(context, expect_int(context.frame.load(index)));
}

fn load_long(context: &Context, index: u16): void {
    context.frame.push(.long_value(expect_long(context.frame.load(index))));
}

fn store_int(context: &Context, index: u16): void {
    context.frame.store(index, .int_value(expect_int(context.frame.pop())));
}

fn store_long(context: &Context, index: u16): void {
    context.frame.store(index, .long_value(expect_long(context.frame.pop())));
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

fn unsupported(context: &Context): result<void, InstructionError> {
    return .err(InstructionError.unsupported_opcode);
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
    context.frame.push(value1);
    context.frame.push(value2);
    context.frame.push(value1);
    return .ok();
}

fn swap(context: &Context): result<void, InstructionError> {
    const value1 = context.frame.pop();
    const value2 = context.frame.pop();
    context.frame.push(value1);
    context.frame.push(value2);
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

fn ifnull(context: &Context): result<void, InstructionError> {
    branch(context, expect_ref(context.frame.pop()).is_null());
    return .ok();
}

fn ifnonnull(context: &Context): result<void, InstructionError> {
    branch(context, expect_ref(context.frame.pop()).non_null());
    return .ok();
}

const registry: [256]Instruction = [
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x00 unsupported
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
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x0B unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x0C unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x0D unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x0E unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x0F unsupported
    { opcode: .bipush, length: 2, execute: bipush }, // 0x10 bipush
    { opcode: .sipush, length: 3, execute: sipush }, // 0x11 sipush
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x12 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x13 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x14 unsupported
    { opcode: .iload, length: 2, execute: iload }, // 0x15 iload
    { opcode: .lload, length: 2, execute: lload }, // 0x16 lload
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x17 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x18 unsupported
    { opcode: .aload, length: 2, execute: aload }, // 0x19 aload
    { opcode: .iload_0, length: 1, execute: iload_0 }, // 0x1A iload_0
    { opcode: .iload_1, length: 1, execute: iload_1 }, // 0x1B iload_1
    { opcode: .iload_2, length: 1, execute: iload_2 }, // 0x1C iload_2
    { opcode: .iload_3, length: 1, execute: iload_3 }, // 0x1D iload_3
    { opcode: .lload_0, length: 1, execute: lload_0 }, // 0x1E lload_0
    { opcode: .lload_1, length: 1, execute: lload_1 }, // 0x1F lload_1
    { opcode: .lload_2, length: 1, execute: lload_2 }, // 0x20 lload_2
    { opcode: .lload_3, length: 1, execute: lload_3 }, // 0x21 lload_3
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x22 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x23 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x24 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x25 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x26 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x27 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x28 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x29 unsupported
    { opcode: .aload_0, length: 1, execute: aload_0 }, // 0x2A aload_0
    { opcode: .aload_1, length: 1, execute: aload_1 }, // 0x2B aload_1
    { opcode: .aload_2, length: 1, execute: aload_2 }, // 0x2C aload_2
    { opcode: .aload_3, length: 1, execute: aload_3 }, // 0x2D aload_3
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x2E unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x2F unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x30 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x31 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x32 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x33 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x34 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x35 unsupported
    { opcode: .istore, length: 2, execute: istore }, // 0x36 istore
    { opcode: .lstore, length: 2, execute: lstore }, // 0x37 lstore
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x38 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x39 unsupported
    { opcode: .astore, length: 2, execute: astore }, // 0x3A astore
    { opcode: .istore_0, length: 1, execute: istore_0 }, // 0x3B istore_0
    { opcode: .istore_1, length: 1, execute: istore_1 }, // 0x3C istore_1
    { opcode: .istore_2, length: 1, execute: istore_2 }, // 0x3D istore_2
    { opcode: .istore_3, length: 1, execute: istore_3 }, // 0x3E istore_3
    { opcode: .lstore_0, length: 1, execute: lstore_0 }, // 0x3F lstore_0
    { opcode: .lstore_1, length: 1, execute: lstore_1 }, // 0x40 lstore_1
    { opcode: .lstore_2, length: 1, execute: lstore_2 }, // 0x41 lstore_2
    { opcode: .lstore_3, length: 1, execute: lstore_3 }, // 0x42 lstore_3
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x43 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x44 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x45 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x46 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x47 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x48 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x49 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x4A unsupported
    { opcode: .astore_0, length: 1, execute: astore_0 }, // 0x4B astore_0
    { opcode: .astore_1, length: 1, execute: astore_1 }, // 0x4C astore_1
    { opcode: .astore_2, length: 1, execute: astore_2 }, // 0x4D astore_2
    { opcode: .astore_3, length: 1, execute: astore_3 }, // 0x4E astore_3
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x4F unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x50 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x51 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x52 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x53 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x54 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x55 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x56 unsupported
    { opcode: .pop, length: 1, execute: pop }, // 0x57 pop
    { opcode: .pop2, length: 1, execute: pop2 }, // 0x58 pop2
    { opcode: .dup, length: 1, execute: dup }, // 0x59 dup
    { opcode: .dup_x1, length: 1, execute: dup_x1 }, // 0x5A dup_x1
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x5B unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x5C unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x5D unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x5E unsupported
    { opcode: .swap, length: 1, execute: swap }, // 0x5F swap
    { opcode: .iadd, length: 1, execute: iadd }, // 0x60 iadd
    { opcode: .ladd, length: 1, execute: ladd }, // 0x61 ladd
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x62 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x63 unsupported
    { opcode: .isub, length: 1, execute: isub }, // 0x64 isub
    { opcode: .lsub, length: 1, execute: lsub }, // 0x65 lsub
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x66 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x67 unsupported
    { opcode: .imul, length: 1, execute: imul }, // 0x68 imul
    { opcode: .lmul, length: 1, execute: lmul }, // 0x69 lmul
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x6A unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x6B unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x6C unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x6D unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x6E unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x6F unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x70 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x71 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x72 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x73 unsupported
    { opcode: .ineg, length: 1, execute: ineg }, // 0x74 ineg
    { opcode: .lneg, length: 1, execute: lneg }, // 0x75 lneg
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x76 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x77 unsupported
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
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x85 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x86 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x87 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x88 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x89 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8A unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8B unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8C unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8D unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8E unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x8F unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x90 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x91 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x92 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0x93 unsupported
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
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xA8 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xA9 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xAA unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xAB unsupported
    { opcode: .ireturn, length: 1, execute: ireturn }, // 0xAC ireturn
    { opcode: .lreturn, length: 1, execute: lreturn }, // 0xAD lreturn
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xAE unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xAF unsupported
    { opcode: .areturn, length: 1, execute: areturn }, // 0xB0 areturn
    { opcode: .return_, length: 1, execute: return_ }, // 0xB1 return
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB2 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB3 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB4 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB5 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB6 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB7 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB8 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xB9 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xBA unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xBB unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xBC unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xBD unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xBE unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xBF unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC0 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC1 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC2 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC3 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC4 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC5 unsupported
    { opcode: .ifnull, length: 3, execute: ifnull }, // 0xC6 ifnull
    { opcode: .ifnonnull, length: 3, execute: ifnonnull }, // 0xC7 ifnonnull
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC8 unsupported
    { opcode: .unsupported, length: 0, execute: unsupported }, // 0xC9 unsupported
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
    var context = Context { class_index: 0, method_index: 0, frame: new_frame(0, 0, method.max_locals, method.max_stack), code: method.code };

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

test "instruction executes iconst and ireturn" {
    const code: [2]u8 = [4, 172];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "answer",
        descriptor: "()I",
        code: code[..],
        max_stack: 1,
        max_locals: 0,
        code_len: 2,
        exception_count: 0,
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
        code: byte_code[..],
        max_stack: 1,
        max_locals: 0,
        code_len: 3,
        exception_count: 0,
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
        code: short_code[..],
        max_stack: 1,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
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
        code: code[..],
        max_stack: 2,
        max_locals: 2,
        code_len: 9,
        exception_count: 0,
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
        code: code[..],
        max_stack: 2,
        max_locals: 4,
        code_len: 13,
        exception_count: 0,
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
        code: code[..],
        max_stack: 2,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 42);
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
        code: first_code[..],
        max_stack: 3,
        max_locals: 0,
        code_len: 7,
        exception_count: 0,
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
        code: second_code[..],
        max_stack: 3,
        max_locals: 0,
        code_len: 11,
        exception_count: 0,
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
        code: third_code[..],
        max_stack: 2,
        max_locals: 0,
        code_len: 6,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const third_result = try execute_method(&third_method);
    assert_int_result(third_result, 42);
    drop third_method;
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
        code: code[..],
        max_stack: 2,
        max_locals: 1,
        code_len: 24,
        exception_count: 0,
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
        code: int_code[..],
        max_stack: 2,
        max_locals: 0,
        code_len: 4,
        exception_count: 0,
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
        code: long_code[..],
        max_stack: 2,
        max_locals: 0,
        code_len: 7,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "J",
    };

    const long_result = try execute_method(&long_method);
    assert_long_result(long_result, 1);
    drop long_method;
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
        code: code[..],
        max_stack: 1,
        max_locals: 0,
        code_len: 45,
        exception_count: 0,
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
        code: code[..],
        max_stack: 2,
        max_locals: 2,
        code_len: 31,
        exception_count: 0,
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
        code: ref_code[..],
        max_stack: 1,
        max_locals: 2,
        code_len: 4,
        exception_count: 0,
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
        code: void_code[..],
        max_stack: 0,
        max_locals: 0,
        code_len: 1,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "V",
    };

    const void_result = try execute_method(&void_method);
    assert_void_result(void_result);
    drop void_method;
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
        code: code[..],
        max_stack: 2,
        max_locals: 1,
        code_len: 29,
        exception_count: 0,
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
        code: code[..],
        max_stack: 4,
        max_locals: 3,
        code_len: 12,
        exception_count: 0,
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
        code: shift_code[..],
        max_stack: 4,
        max_locals: 0,
        code_len: 8,
        exception_count: 0,
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
        code: bitwise_code[..],
        max_stack: 2,
        max_locals: 0,
        code_len: 10,
        exception_count: 0,
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
        code: code[..],
        max_stack: 4,
        max_locals: 4,
        code_len: 17,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };

    const result = try execute_method(&method);
    assert_int_result(result, 0 - 1);
    drop method;
}

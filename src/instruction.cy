import { Context, Frame, FrameResult, new_frame } from .engine;
import { Method, Value, method_access_flags } from .types;

pub enum InstructionError: i32 {
    unsupported_opcode = 0,
    missing_return,
}

pub enum Opcode: i32 {
    unsupported = 0,
    iconst_m1 = 2,
    iconst_0,
    iconst_1,
    iconst_2,
    iconst_3,
    iconst_4,
    iconst_5,
    bipush = 16,
    sipush = 17,
    ireturn = 172,
}

pub struct Instruction {
    pub opcode: Opcode;
    pub length: u32;
    pub execute: ExecuteFn;
}

type ExecuteFn = fn(context: &Context): result<void, InstructionError>;
type InstructionRegistry = [256]Instruction;

fn push_int(context: &Context, value: i32): void {
    context.frame.stack.push(.int_value(value));
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

fn bipush(context: &Context): result<void, InstructionError> {
    push_int(context, sign_extend_u1(context.read_u1()));
    return .ok();
}

fn sipush(context: &Context): result<void, InstructionError> {
    push_int(context, context.read_i2() as i32);
    return .ok();
}

fn ireturn(context: &Context): result<void, InstructionError> {
    const result: FrameResult = .return_value(context.frame.stack.pop());
    context.frame.result = result;
    return .ok();
}

const registry = InstructionRegistry [
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x00 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x01 unsupported
    Instruction { opcode: Opcode.iconst_m1, length: 1, execute: iconst_m1 }, // 0x02 iconst_m1
    Instruction { opcode: Opcode.iconst_0, length: 1, execute: iconst_0 }, // 0x03 iconst_0
    Instruction { opcode: Opcode.iconst_1, length: 1, execute: iconst_1 }, // 0x04 iconst_1
    Instruction { opcode: Opcode.iconst_2, length: 1, execute: iconst_2 }, // 0x05 iconst_2
    Instruction { opcode: Opcode.iconst_3, length: 1, execute: iconst_3 }, // 0x06 iconst_3
    Instruction { opcode: Opcode.iconst_4, length: 1, execute: iconst_4 }, // 0x07 iconst_4
    Instruction { opcode: Opcode.iconst_5, length: 1, execute: iconst_5 }, // 0x08 iconst_5
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x09 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x0A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x0B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x0C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x0D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x0E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x0F unsupported
    Instruction { opcode: Opcode.bipush, length: 2, execute: bipush }, // 0x10 bipush
    Instruction { opcode: Opcode.sipush, length: 3, execute: sipush }, // 0x11 sipush
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x12 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x13 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x14 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x15 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x16 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x17 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x18 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x19 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x1A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x1B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x1C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x1D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x1E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x1F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x20 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x21 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x22 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x23 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x24 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x25 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x26 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x27 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x28 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x29 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x2A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x2B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x2C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x2D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x2E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x2F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x30 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x31 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x32 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x33 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x34 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x35 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x36 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x37 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x38 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x39 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x3A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x3B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x3C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x3D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x3E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x3F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x40 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x41 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x42 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x43 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x44 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x45 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x46 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x47 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x48 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x49 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x4A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x4B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x4C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x4D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x4E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x4F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x50 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x51 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x52 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x53 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x54 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x55 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x56 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x57 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x58 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x59 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x5A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x5B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x5C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x5D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x5E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x5F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x60 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x61 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x62 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x63 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x64 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x65 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x66 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x67 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x68 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x69 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x6A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x6B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x6C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x6D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x6E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x6F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x70 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x71 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x72 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x73 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x74 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x75 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x76 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x77 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x78 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x79 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x7A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x7B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x7C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x7D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x7E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x7F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x80 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x81 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x82 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x83 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x84 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x85 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x86 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x87 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x88 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x89 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x8A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x8B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x8C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x8D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x8E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x8F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x90 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x91 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x92 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x93 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x94 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x95 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x96 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x97 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x98 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x99 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x9A unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x9B unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x9C unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x9D unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x9E unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0x9F unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA0 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA1 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA2 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA3 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA4 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA5 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA6 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA7 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA8 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xA9 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xAA unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xAB unsupported
    Instruction { opcode: Opcode.ireturn, length: 1, execute: ireturn }, // 0xAC ireturn
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xAD unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xAE unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xAF unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB0 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB1 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB2 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB3 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB4 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB5 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB6 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB7 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB8 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xB9 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xBA unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xBB unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xBC unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xBD unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xBE unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xBF unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC0 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC1 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC2 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC3 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC4 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC5 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC6 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC7 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC8 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xC9 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xCA unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xCB unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xCC unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xCD unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xCE unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xCF unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD0 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD1 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD2 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD3 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD4 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD5 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD6 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD7 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD8 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xD9 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xDA unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xDB unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xDC unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xDD unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xDE unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xDF unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE0 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE1 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE2 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE3 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE4 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE5 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE6 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE7 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE8 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xE9 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xEA unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xEB unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xEC unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xED unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xEE unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xEF unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF0 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF1 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF2 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF3 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF4 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF5 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF6 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF7 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF8 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xF9 unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xFA unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xFB unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xFC unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xFD unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xFE unsupported
    Instruction { opcode: Opcode.unsupported, length: 0, execute: unsupported }, // 0xFF unsupported
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
    const code = method.code.bytes();
    var context = Context { class_index: 0, method_index: 0, frame: new_frame(0, 0, method.max_locals, method.max_stack), code: code };

    while context.frame.pc < method.code_len {
        try execute_next(&context);
        if context.frame.result is result {
            return .ok(result);
        }
    }
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

test "instruction executes iconst and ireturn" {
    var code: [:]u8 = [4, 172];
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "answer",
        descriptor: "()I",
        code: string.from(code[..]),
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
}

test "instruction executes bipush sipush and ireturn" {
    var byte_code: [:]u8 = [16, 254, 172];
    var short_code: [:]u8 = [17, 1, 2, 172];
    var byte_method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "byteValue",
        descriptor: "()I",
        code: string.from(byte_code[..]),
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
        code: string.from(short_code[..]),
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
}

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
}

type InstructionRegistry = [256]Instruction;

const registry: InstructionRegistry = InstructionRegistry [
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.iconst_m1, length: 1 },
    Instruction { opcode: Opcode.iconst_0, length: 1 },
    Instruction { opcode: Opcode.iconst_1, length: 1 },
    Instruction { opcode: Opcode.iconst_2, length: 1 },
    Instruction { opcode: Opcode.iconst_3, length: 1 },
    Instruction { opcode: Opcode.iconst_4, length: 1 },
    Instruction { opcode: Opcode.iconst_5, length: 1 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.bipush, length: 2 },
    Instruction { opcode: Opcode.sipush, length: 3 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.ireturn, length: 1 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 },
    Instruction { opcode: Opcode.unsupported, length: 0 }
];

pub fn fetch(raw: u8): result<Instruction, InstructionError> {
    const instruction = registry[raw as usize];
    if instruction.opcode == Opcode.unsupported {
        return .err(InstructionError.unsupported_opcode);
    }
    return .ok(instruction);
}

fn push_int(frame: &Frame, value: i32): void {
    frame.push(.int_value(value));
}

fn sign_extend_u1(value: u8): i32 {
    if value > 127 {
        return (value as i32) - 256;
    }
    return value as i32;
}

pub fn execute_next(context: &Context, frame: &Frame, code: []const u8): result<void, InstructionError> {
    const pc = frame.pc;
    const instruction = try fetch(code[pc as usize]);

    switch instruction.opcode {
    case Opcode.unsupported { return .err(InstructionError.unsupported_opcode); }
    case Opcode.iconst_m1 { push_int(frame, 0 - 1); }
    case Opcode.iconst_0 { push_int(frame, 0); }
    case Opcode.iconst_1 { push_int(frame, 1); }
    case Opcode.iconst_2 { push_int(frame, 2); }
    case Opcode.iconst_3 { push_int(frame, 3); }
    case Opcode.iconst_4 { push_int(frame, 4); }
    case Opcode.iconst_5 { push_int(frame, 5); }
    case Opcode.bipush { push_int(frame, sign_extend_u1(context.read_u1(frame, code))); }
    case Opcode.sipush { push_int(frame, context.read_i2(frame, code) as i32); }
    case Opcode.ireturn { frame.return_value(frame.pop()); }
    }

    if frame.result == none and frame.pc == pc {
        frame.pc = frame.pc + instruction.length;
    }
    frame.offset = 1;
    return .ok();
}

pub fn execute_method(method: &Method): result<FrameResult, InstructionError> {
    var frame = new_frame(0, 0, method.max_locals, method.max_stack);
    var context = Context { class_index: 0, method_index: 0 };
    const code = method.code.bytes();

    while frame.pc < method.code_len {
        try execute_next(&context, &frame, code);
        if frame.result is result {
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

import { Method, Reference, Value, method_access_flags } from .types;

const max_call_stack: usize = 512;

pub enum ThreadStatus: i32 {
    started = 0,
    sleeping,
    parking,
    waiting,
    interrupted,
}

pub union FrameResult {
    return_value: ?Value;
    exception: Reference;
}

pub struct Frame {
    pub class_index: usize;
    pub method_index: usize;
    pub pc: u32;
    pub local_vars: List<Value>;
    pub stack: List<Value>;
    pub offset: u32;
    pub result: ?FrameResult;

    pub fn depth(self: &Frame): usize {
        return self.stack.len();
    }

    pub fn push(self: &Frame, value: Value): void {
        self.stack.push(value);
    }

    pub fn pop(self: &Frame): Value {
        return self.stack.pop();
    }

    pub fn clear(self: &Frame): void {
        self.stack.clear();
    }

    pub fn load(self: &Frame, index: u16): Value {
        return self.local_vars[index as usize];
    }

    pub fn store(self: &Frame, index: u16, value: Value): void {
        self.local_vars[index as usize] = value;
    }

    pub fn next(self: &Frame, offset: i32): void {
        if offset < 0 {
            self.pc = self.pc - ((0 - offset) as u32);
            return;
        }
        self.pc = self.pc + (offset as u32);
    }

    pub fn return_value(self: &Frame, value: ?Value): void {
        const result: FrameResult = .return_value(value);
        self.result = result;
    }

    pub fn throw_exception(self: &Frame, exception: Reference): void {
        const result: FrameResult = .exception(exception);
        self.result = result;
    }
}

pub fn new_frame(class_index: usize, method_index: usize, max_locals: u16, max_stack: u16): Frame {
    var local_vars: List<Value> = [];
    var local_index: u16 = 0;
    while local_index < max_locals {
        local_vars.push(.int_value(0));
        local_index = local_index + 1;
    }

    const ignored = max_stack;
    return Frame {
        class_index: class_index,
        method_index: method_index,
        pc: 0,
        local_vars: local_vars,
        stack: [],
        offset: 1,
        result: none,
    };
}

pub struct Thread {
    pub id: u64;
    pub name: string;
    pub stack: List<Frame>;
    pub daemon: bool;
    pub status: ThreadStatus;
    pub result: ?FrameResult;

    pub fn depth(self: &Thread): usize {
        return self.stack.len();
    }

    pub fn has_active(self: &Thread): bool {
        return self.stack.len() > 0;
    }

    pub fn active_index(self: &Thread): ?usize {
        if self.stack.len() == 0 {
            return none;
        }
        return self.stack.len() - 1;
    }

    pub fn push_frame(self: &Thread, frame: Frame): bool {
        if self.stack.len() >= max_call_stack {
            return false;
        }
        self.stack.push(frame);
        return true;
    }

    pub fn pop_frame(self: &Thread): ?Frame {
        if self.stack.len() == 0 {
            return none;
        }
        return self.stack.pop();
    }
}

pub fn new_thread(id: u64, name: string): Thread {
    return Thread {
        id: id,
        name: name,
        stack: [],
        daemon: false,
        status: ThreadStatus.started,
        result: none,
    };
}

pub struct Context {
    pub class_index: usize;
    pub method_index: usize;
    pub frame: Frame;
    pub code: []const u8;

    pub fn read_u1(self: &Context): u8 {
        const index = (self.frame.pc + self.frame.offset) as usize;
        const value = self.code[index];
        self.frame.offset = self.frame.offset + 1;
        return value;
    }

    pub fn read_u2(self: &Context): u16 {
        const high = self.read_u1() as u16;
        const low = self.read_u1() as u16;
        return (high << 8) | low;
    }

    pub fn read_i2(self: &Context): i16 {
        const value = self.read_u2();
        if value > 32767 {
            return ((value as i32) - 65536) as i16;
        }
        return value as i16;
    }

    pub fn read_i4(self: &Context): i32 {
        const first = self.read_u1() as i32;
        const second = self.read_u1() as i32;
        const third = self.read_u1() as i32;
        const fourth = self.read_u1() as i32;
        return (first << 24) | (second << 16) | (third << 8) | fourth;
    }

    pub fn padding(self: &Context): void {
        while ((self.frame.pc + self.frame.offset) % 4) != 0 {
            self.frame.offset = self.frame.offset + 1;
        }
    }
}

fn assert_int_value(value: Value, expected: i32): void {
    switch value {
    case .int_value(actual) { assert(actual == expected); }
    case .byte_value(actual) { const ignored = actual; assert(false); }
    case .short_value(actual) { const ignored = actual; assert(false); }
    case .char_value(actual) { const ignored = actual; assert(false); }
    case .long_value(actual) { const ignored = actual; assert(false); }
    case .float_value(actual) { const ignored = actual; assert(false); }
    case .double_value(actual) { const ignored = actual; assert(false); }
    case .boolean_value(actual) { const ignored = actual; assert(false); }
    case .return_address_value(actual) { const ignored = actual; assert(false); }
    case .ref_value(actual) { const ignored = actual; assert(false); }
    }
}

test "frame manages locals operand stack and pc" {
    var frame = new_frame(2, 3, 2, 4);
    assert(frame.class_index == 2);
    assert(frame.method_index == 3);
    assert(frame.pc == 0);
    assert(frame.offset == 1);
    assert(frame.local_vars.len() == 2);
    assert(frame.depth() == 0);

    frame.store(0, .int_value(41));
    frame.push(frame.load(0));
    frame.push(.int_value(1));
    assert(frame.depth() == 2);
    assert_int_value(frame.pop(), 1);
    assert_int_value(frame.pop(), 41);

    frame.next(5);
    assert(frame.pc == 5);
    frame.next(0 - 2);
    assert(frame.pc == 3);

    const return_value: Value = .int_value(42);
    frame.return_value(return_value);
    if frame.result is result {
        switch result {
        case .return_value(value) {
            if value is actual {
                assert_int_value(actual, 42);
            } else {
                assert(false);
            }
        }
        case .exception(reference) {
            const ignored = reference;
            assert(false);
        }
        }
    } else {
        assert(false);
    }
}

test "thread pushes and pops frames" {
    var thread = new_thread(7, string.from("main".bytes()));
    assert(thread.id == 7);
    assert(thread.status == ThreadStatus.started);
    assert(thread.depth() == 0);
    assert(!thread.has_active());

    assert(thread.push_frame(new_frame(0, 1, 1, 1)));
    assert(thread.push_frame(new_frame(0, 2, 1, 1)));
    assert(thread.depth() == 2);
    assert(thread.has_active());
    if thread.active_index() is active {
        assert(thread.stack[active].method_index == 2);
    } else {
        assert(false);
    }

    if thread.pop_frame() is frame {
        assert(frame.method_index == 2);
    } else {
        assert(false);
    }
    assert(thread.depth() == 1);

    const popped = thread.pop_frame();
    const empty = thread.pop_frame();
    assert(popped != none);
    assert(empty == none);
}

test "context reads big endian operands and padding" {
    var method = Method {
        class_name: "Main",
        access_flags: method_access_flags(0),
        name: "run",
        descriptor: "()I",
        code: "0123456789AB".bytes(),
        max_stack: 4,
        max_locals: 1,
        code_len: 10,
        exception_count: 0,
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "I",
    };
    var context = Context { class_index: 0, method_index: 0, frame: new_frame(0, 0, 1, 4), code: method.code };

    assert(context.read_u1() == 49);
    assert(context.frame.offset == 2);
    assert(context.read_u2() == 0x3233);
    assert(context.frame.offset == 4);

    context.frame.pc = 5;
    context.frame.offset = 1;
    context.padding();
    assert(context.frame.offset == 3);
    assert(context.read_i4() == 0x38394142);

    const negative_code: [3]u8 = [0, 255, 243];
    var negative_context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: negative_code[..],
    };
    assert(negative_context.read_i2() == (0 - 13));
    drop negative_context;
}

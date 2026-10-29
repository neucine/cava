import { ClassFile, Constant } from .classfile;
import { execute_next, execute_frame_next, execute_array_next, find_class_index_by_constant, print_instruction_error_context } from .instruction;
import { SyncStatus } from std.sync;
import { class_matches } from .method_area;
import { VM, new_vm } from .vm;
import { Class, ExceptionHandler, InstructionError, Reference, Value } from .types;
import { Runtime } from .runtime;
import { enter_method_monitor, exit_method_monitor } from .method_monitor;

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

    pub fn clear_all(self: &Frame): void {
        self.local_vars.clear();
        self.stack.clear();
    }

    pub fn load(self: &Frame, index: u16): Value {
        return self.local_vars[index];
    }

    pub fn store(self: &Frame, index: u16, value: Value): void {
        self.local_vars[index] = value;
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
    pub runtime: ?Runtime;
    pub class_index: usize;
    pub method_index: usize;
    pub frame: Frame;
    pub code: []const u8;
    pub constant_pool: []const Constant;

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

pub fn execution_exit_code(error_value: InstructionError): i32 {
    if error_value == InstructionError.unsupported_opcode {
        return 20;
    }
    if error_value == InstructionError.unsupported_native {
        return 21;
    }
    if error_value == InstructionError.invalid_constant {
        return 22;
    }
    if error_value == InstructionError.missing_return {
        return 23;
    }
    return 24;
}

pub fn print_execution_error(error_value: InstructionError): void {
    if error_value == InstructionError.unsupported_opcode {
        println("execution failed: unsupported opcode");
    } else if error_value == InstructionError.unsupported_native {
        println("execution failed: unsupported native");
    } else if error_value == InstructionError.invalid_constant {
        println("execution failed: invalid or missing constant/class/member");
    } else if error_value == InstructionError.missing_return {
        println("execution failed: missing return");
    } else {
        println("execution failed");
    }
}

fn handler_matches(context: &Context, vm: &VM, handler: ExceptionHandler, exception: Reference): bool ! InstructionError {
    if handler.catch_type == 0 {
        return true;
    }
    var exception_class_index: usize = 0;
    if vm.heap.object_class_index(exception) is actual_exception_class_index {
        exception_class_index = actual_exception_class_index;
    } else {
        throw InstructionError.invalid_constant;
    }
    const catch_class_index = try find_class_index_by_constant(context, vm, handler.catch_type);
    return class_matches(vm.method_area.classes[..], exception_class_index, catch_class_index);
}

pub fn dispatch_exception(context: &Context, vm: &VM, exception: Reference): bool ! InstructionError {
    var classes = vm.method_area.classes[..];
    if context.class_index >= classes.len() {
        return false;
    }
    if context.method_index >= classes[context.class_index].methods.len() {
        return false;
    }

    const pc = context.frame.pc as u16;
    var index: usize = 0;
    while index < classes[context.class_index].methods[context.method_index].exception_handlers.len() {
        const handler = classes[context.class_index].methods[context.method_index].exception_handlers[index];
        if pc >= handler.start_pc and pc < handler.end_pc {
            if try handler_matches(context, vm, handler, exception) {
                context.frame.clear();
                context.frame.push(.ref_value(exception));
                context.frame.pc = handler.handle_pc as u32;
                context.frame.offset = 1;
                context.frame.result = none;
                return true;
            }
        }
        index = index + 1;
    }
    return false;
}

pub fn apply_method_result(context: &Context, vm: &VM, result: FrameResult): void ! InstructionError {
    switch result {
        .return_value(value) => {
            if value is actual {
                context.frame.push(actual);
            }
        }
        .exception(reference) => {
            if !(try dispatch_exception(context, vm, reference)) {
                context.frame.throw_exception(reference);
            }
        }
    }
    return;
}

fn execute_shared_step(vm: &VM, context: &Context): ?InstructionError {
    execute_next(context, vm) catch (problem) {
        print_instruction_error_context(context, vm, problem);
        return problem;
    };
    return none;
}

fn execute_parallel_context(context: &Context, runtime: &const Runtime, class_name: string, method_name: string): FrameResult ! InstructionError {
    while context.frame.pc < context.code.len() as u32 {
        var handled = try execute_frame_next(context, class_name, method_name);
        if !handled {
            handled = try execute_array_next(context, class_name, method_name);
        }
        if !handled {
            const step = runtime.state.with_result<&Context, ?InstructionError>(context, execute_shared_step) catch (status) {
                throw InstructionError.invalid_constant;
            };
            if step is problem {
                throw problem;
            }
        }
        if context.frame.result is result {
            return result;
        }
    }
    throw InstructionError.missing_return;
}

fn execute_method_frame_with_context(runtime: ?Runtime, vm: &VM, class_index: usize, method_index: usize, frame: Frame, constant_pool: []const Constant): FrameResult ! InstructionError {
    var active_frame = frame;
    const method = &vm.method_area.classes[class_index].methods[method_index];
    var receiver: ?Reference = none;
    if method.is_synchronized() and !method.is_static() and active_frame.local_vars.len() > 0 {
        receiver = expect_ref_for_engine(active_frame.load(0));
    }
    const monitor = try enter_method_monitor(runtime, vm, class_index, method_index, receiver);
    const result = execute_method_frame_body(runtime, vm, class_index, method_index, active_frame, constant_pool);
    try exit_method_monitor(vm, monitor);
    return result;
}

fn execute_method_frame_body(runtime: ?Runtime, vm: &VM, class_index: usize, method_index: usize, frame: Frame, constant_pool: []const Constant): FrameResult ! InstructionError {
    var runtime_pool = constant_pool;
    var vm_classes = vm.method_area.classes[..];
    var class_view = vm_classes;
    const class = &class_view[class_index];
    const method = &class.methods[method_index];
    if class_index < class_view.len() and class.constant_pool.len() > 0 {
        runtime_pool = class.constant_pool[..];
    }

    if class.name == "java/lang/Class$Atomic" {
        if method.name == "<clinit>" and method.descriptor == "()V" {
            frame.clear_all();
            const completed_1: FrameResult = .return_value(none);
            return completed_1;
        }
        if method.name == "casReflectionData" or method.name == "casAnnotationType" or method.name == "casAnnotationData" {
            frame.clear_all();
            const value: Value = .boolean_value(1);
            const completed_2: FrameResult = .return_value(value);
            return completed_2;
        }
    }

    if class.name == "java/text/DecimalFormatSymbols" and method.name == "getInstance" {
        const reference = vm.heap.allocate_object_with_hierarchy(class_index, class_view);
        if class.field_index("zeroDigit", "C", false) is field_index {
            const field = &class.fields[field_index];
            const ignored_set = vm.heap.set_field(reference, field.slot, .char_value(48));
        }
        frame.clear_all();
        const value: Value = .ref_value(reference);
        const completed_3: FrameResult = .return_value(value);
        return completed_3;
    }

    if class.name == "java/io/PrintStream" {
        const method_name = method.name;
        const descriptor = method.descriptor;
        if method_name == "write" and descriptor == "(Ljava/lang/String;)V" {
            const value = frame.load(1);
            try vm.print_java_string(expect_ref_for_engine(value), false);
            frame.clear_all();
            const completed_4: FrameResult = .return_value(none);
            return completed_4;
        }
        if method_name == "newLine" and descriptor == "()V" {
            println("");
            frame.clear_all();
            const completed_5: FrameResult = .return_value(none);
            return completed_5;
        }
    }

    const code_snapshot = method.code.clone();
    var pool_snapshot: List<Constant> = [];
    var pool_index: usize = 0;
    while pool_index < runtime_pool.len() {
        pool_snapshot.push(runtime_pool[pool_index]);
        pool_index = pool_index + 1;
    }
    var context = Context {
        runtime: runtime,
        class_index: class_index,
        method_index: method_index,
        frame: frame,
        code: code_snapshot[..],
        constant_pool: pool_snapshot[..]
    };

    if context.runtime is active_runtime {
        const class_name = class.name.clone();
        const method_name = method.name.clone();
        assert(active_runtime.state.unlock() == SyncStatus.ok);
        const result = execute_parallel_context(&context, &active_runtime, class_name, method_name);
        assert(active_runtime.state.lock() == SyncStatus.ok);
        return result;
    }
    while context.frame.pc < context.code.len() as u32 {
        execute_next(&context, vm) catch (error_value) {
            print_instruction_error_context(&context, vm, error_value);
            throw error_value;
        };
        if context.frame.result is result {
            const out = result;
            return out;
        }
    }
    throw InstructionError.missing_return;
}

pub fn execute_method_frame_with_vm(vm: &VM, class_index: usize, method_index: usize, frame: Frame, constant_pool: []const Constant): FrameResult ! InstructionError {
    return execute_method_frame_with_context(none, vm, class_index, method_index, frame, constant_pool);
}

pub fn execute_method_frame_with_runtime(runtime: Runtime, vm: &VM, class_index: usize, method_index: usize, frame: Frame, constant_pool: []const Constant): FrameResult ! InstructionError {
    return execute_method_frame_with_context(runtime.alias_handles(), vm, class_index, method_index, frame, constant_pool);
}

pub fn execute_method_area_with_vm(vm: &VM, class_index: usize, method_index: usize, constant_pool: []const Constant, java_args: []const string): FrameResult ! InstructionError {
    const max_locals = vm.method_area.method_max_locals(class_index, method_index);
    const max_stack = vm.method_area.method_max_stack(class_index, method_index);
    var frame = new_frame(class_index, method_index, max_locals, max_stack);
    if vm.method_area.classes[class_index].methods[method_index].is_static() and vm.method_area.classes[class_index].methods[method_index].descriptor == "([Ljava/lang/String;)V" {
        const args_class_index = vm.method_area.define_array_class("[Ljava/lang/String;");
        const args_reference = vm.heap.allocate_array(args_class_index, "Ljava/lang/String;".bytes(), java_args.len());
        var arg_index: usize = 0;
        while arg_index < java_args.len() {
            const arg_reference = try vm.allocate_java_string(java_args[arg_index].bytes());
            const ignored_set = vm.heap.set_element(args_reference, arg_index, .ref_value(arg_reference));
            arg_index = arg_index + 1;
        }
        frame.store(0, .ref_value(args_reference));
    }
    return execute_method_frame_with_vm(vm, class_index, method_index, frame, constant_pool);
}

pub fn execute_method_area_with_runtime(runtime: Runtime, vm: &VM, class_index: usize, method_index: usize, constant_pool: []const Constant, java_args: []const string): FrameResult ! InstructionError {
    const max_locals = vm.method_area.method_max_locals(class_index, method_index);
    const max_stack = vm.method_area.method_max_stack(class_index, method_index);
    var frame = new_frame(class_index, method_index, max_locals, max_stack);
    if vm.method_area.classes[class_index].methods[method_index].is_static() and vm.method_area.classes[class_index].methods[method_index].descriptor == "([Ljava/lang/String;)V" {
        const args_class_index = vm.method_area.define_array_class("[Ljava/lang/String;");
        const args_reference = vm.heap.allocate_array(args_class_index, "Ljava/lang/String;".bytes(), java_args.len());
        var arg_index: usize = 0;
        while arg_index < java_args.len() {
            const arg_reference = try vm.allocate_java_string(java_args[arg_index].bytes());
            const ignored_set = vm.heap.set_element(args_reference, arg_index, .ref_value(arg_reference));
            arg_index = arg_index + 1;
        }
        frame.store(0, .ref_value(args_reference));
    }
    return execute_method_frame_with_runtime(runtime, vm, class_index, method_index, frame, constant_pool);
}

pub fn execute_classfile_method_area_with_vm(vm: &VM, class_index: usize, method_index: usize, classfile: &ClassFile, java_args: []const string): FrameResult ! InstructionError {
    return execute_method_area_with_vm(vm, class_index, method_index, classfile.constant_pool[..], java_args);
}

fn expect_ref_for_engine(value: Value): Reference {
    return switch value {
        .ref_value(actual) => actual;
        _ => Reference.init_null();
    };
}

fn assert_int_value(value: Value, expected: i32): void {
    switch value {
        .int_value(actual) => {
            assert(actual == expected);
        }
        .byte_value => unreachable;
        .short_value => unreachable;
        .char_value => unreachable;
        .long_value => unreachable;
        .float_value => unreachable;
        .double_value => unreachable;
        .boolean_value => unreachable;
        .return_address_value => unreachable;
        .ref_value => unreachable;
    }
}

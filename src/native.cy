import { Context } from .engine;
import { InstructionError, Reference, Value } from .types;

fn ref_arg(arguments: []Value, index: usize): Reference {
    switch arguments[index] {
    case .ref_value(actual) { return actual; }
    else { return Reference.init_null(); }
    }
}

fn int_arg(arguments: []Value, index: usize): i32 {
    switch arguments[index] {
    case .int_value(actual) { return actual; }
    case .boolean_value(actual) { return actual as i32; }
    case .byte_value(actual) { return actual as i32; }
    case .short_value(actual) { return actual as i32; }
    case .char_value(actual) { return actual as i32; }
    else { return 0; }
    }
}

fn long_arg(arguments: []Value, index: usize): i64 {
    switch arguments[index] {
    case .long_value(actual) { return actual; }
    else { return 0; }
    }
}

fn float_arg(arguments: []Value, index: usize): f32 {
    switch arguments[index] {
    case .float_value(actual) { return actual; }
    else { return 0.0; }
    }
}

fn double_arg(arguments: []Value, index: usize): f64 {
    switch arguments[index] {
    case .double_value(actual) { return actual; }
    else { return 0.0; }
    }
}

fn receiver_ref(receiver: ?Reference): result<Reference, InstructionError> {
    if receiver is actual {
        return .ok(actual);
    }
    return .err(InstructionError.invalid_constant);
}

fn return_value(value: Value): result<?Value, InstructionError> {
    return .ok(value);
}

fn identity_hash_code(reference: Reference): i32 {
    if reference.slot is slot {
        const mixed = (slot as u64) +% (reference.generation *% 1103515245);
        return (mixed & 2147483647) as i32;
    }
    return 0;
}

fn arraycopy(context: &Context, src: Reference, src_pos: i32, dest: Reference, dest_pos: i32, length: i32): result<void, InstructionError> {
    if src_pos < 0 or dest_pos < 0 or length < 0 {
        return .err(InstructionError.invalid_constant);
    }
    const src_start = src_pos as usize;
    const dest_start = dest_pos as usize;
    const count = length as usize;
    var src_len: usize = 0;
    if context.heap.array_length(src) is actual_src_len {
        src_len = actual_src_len;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var dest_len: usize = 0;
    if context.heap.array_length(dest) is actual_dest_len {
        dest_len = actual_dest_len;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    if src_start + count > src_len or dest_start + count > dest_len {
        return .err(InstructionError.invalid_constant);
    }

    if src.equals(dest) and dest_start > src_start {
        var index = count;
        while index > 0 {
            index = index - 1;
            var value: Value = .int_value(0);
            if context.heap.get_element(src, src_start + index) is actual_value {
                value = actual_value;
            } else {
                return .err(InstructionError.invalid_constant);
            }
            if !context.heap.set_element(dest, dest_start + index, value) {
                return .err(InstructionError.invalid_constant);
            }
        }
        return .ok();
    }

    var index: usize = 0;
    while index < count {
        var value: Value = .int_value(0);
        if context.heap.get_element(src, src_start + index) is actual_value {
            value = actual_value;
        } else {
            return .err(InstructionError.invalid_constant);
        }
        if !context.heap.set_element(dest, dest_start + index, value) {
            return .err(InstructionError.invalid_constant);
        }
        index = index + 1;
    }
    return .ok();
}

struct JavaLangSystem {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn setIn0(context: &Context, input: Reference): result<?Value, InstructionError> {
        const ignored_input = input;
        return .ok(none);
    }

    pub fn setOut0(context: &Context, output: Reference): result<?Value, InstructionError> {
        const ignored_output = output;
        return .ok(none);
    }

    pub fn setErr0(context: &Context, error_stream: Reference): result<?Value, InstructionError> {
        const ignored_error_stream = error_stream;
        return .ok(none);
    }

    pub fn arraycopy(context: &Context, src: Reference, src_pos: i32, dest: Reference, dest_pos: i32, length: i32): result<?Value, InstructionError> {
        try arraycopy(context, src, src_pos, dest, dest_pos, length);
        return .ok(none);
    }

    pub fn identityHashCode(context: &Context, reference: Reference): result<?Value, InstructionError> {
        return return_value(.int_value(identity_hash_code(reference)));
    }
}

struct JavaLangObject {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn hashCode(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        return return_value(.int_value(identity_hash_code(receiver)));
    }

    pub fn getClass(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if context.heap.object_class_index(receiver) is actual_class_index {
            return return_value(.ref_value(context.classes[actual_class_index].class_object));
        }
        if context.heap.array_class_index(receiver) is actual_class_index {
            return return_value(.ref_value(context.classes[actual_class_index].class_object));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn notify(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return .ok(none);
    }

    pub fn notifyAll(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return .ok(none);
    }

    pub fn wait(context: &Context, receiver: Reference, millis: i64): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_millis = millis;
        return .ok(none);
    }
}

struct JavaLangString {
    pub fn intern(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        return return_value(.ref_value(receiver));
    }
}

struct JavaLangFloat {
    pub fn floatToRawIntBits(context: &Context, value: f32): result<?Value, InstructionError> {
        return return_value(.int_value(value as! i32));
    }

    pub fn intBitsToFloat(context: &Context, value: i32): result<?Value, InstructionError> {
        return return_value(.float_value(value as! f32));
    }
}

struct JavaLangDouble {
    pub fn doubleToRawLongBits(context: &Context, value: f64): result<?Value, InstructionError> {
        return return_value(.long_value(value as! i64));
    }

    pub fn longBitsToDouble(context: &Context, value: i64): result<?Value, InstructionError> {
        return return_value(.double_value(value as! f64));
    }
}

struct JavaLangThread {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn isAlive(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.boolean_value(0));
    }

    pub fn setPriority0(context: &Context, receiver: Reference, priority: i32): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_priority = priority;
        return .ok(none);
    }

    pub fn start0(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return .ok(none);
    }

    pub fn sleep(context: &Context, millis: i64): result<?Value, InstructionError> {
        const ignored_millis = millis;
        return .ok(none);
    }

    pub fn interrupt0(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return .ok(none);
    }

    pub fn isInterrupted(context: &Context, receiver: Reference, clear_interrupted: i32): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_clear_interrupted = clear_interrupted;
        return return_value(.boolean_value(0));
    }
}

struct JavaLangThrowable {
    pub fn getStackTraceDepth(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.int_value(0));
    }

    pub fn fillInStackTrace(context: &Context, receiver: Reference, dummy: i32): result<?Value, InstructionError> {
        const ignored_dummy = dummy;
        return return_value(.ref_value(receiver));
    }
}

struct JavaLangRuntime {
    pub fn availableProcessors(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.int_value(1));
    }
}

struct SunMiscVM {
    pub fn initialize(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }
}

struct SunMiscUnsafe {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn arrayBaseOffset(context: &Context, class: Reference): result<?Value, InstructionError> {
        const ignored_class = class;
        return return_value(.int_value(0));
    }

    pub fn arrayIndexScale(context: &Context, class: Reference): result<?Value, InstructionError> {
        const ignored_class = class;
        return return_value(.int_value(1));
    }

    pub fn addressSize(context: &Context): result<?Value, InstructionError> {
        return return_value(.int_value(8));
    }
}

pub fn execute_native_method(context: &Context, class_index: usize, method_index: usize, receiver: ?Reference, arguments: []Value): result<?Value, InstructionError> {
    const class_name = context.classes[class_index].name.bytes();
    const method_name = context.classes[class_index].methods[method_index].name.bytes();
    const descriptor = context.classes[class_index].methods[method_index].descriptor.bytes();

    if class_name == "java/lang/System".bytes() {
        if method_name == "registerNatives".bytes() and descriptor == "()V".bytes() { return JavaLangSystem.registerNatives(context); }
        if method_name == "setIn0".bytes() and descriptor == "(Ljava/io/InputStream;)V".bytes() { return JavaLangSystem.setIn0(context, ref_arg(arguments, 0)); }
        if method_name == "setOut0".bytes() and descriptor == "(Ljava/io/PrintStream;)V".bytes() { return JavaLangSystem.setOut0(context, ref_arg(arguments, 0)); }
        if method_name == "setErr0".bytes() and descriptor == "(Ljava/io/PrintStream;)V".bytes() { return JavaLangSystem.setErr0(context, ref_arg(arguments, 0)); }
        if method_name == "arraycopy".bytes() and descriptor == "(Ljava/lang/Object;ILjava/lang/Object;II)V".bytes() { return JavaLangSystem.arraycopy(context, ref_arg(arguments, 0), int_arg(arguments, 1), ref_arg(arguments, 2), int_arg(arguments, 3), int_arg(arguments, 4)); }
        if method_name == "identityHashCode".bytes() and descriptor == "(Ljava/lang/Object;)I".bytes() { return JavaLangSystem.identityHashCode(context, ref_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Object".bytes() {
        if method_name == "registerNatives".bytes() and descriptor == "()V".bytes() { return JavaLangObject.registerNatives(context); }
        if method_name == "hashCode".bytes() and descriptor == "()I".bytes() { return JavaLangObject.hashCode(context, try receiver_ref(receiver)); }
        if method_name == "getClass".bytes() and descriptor == "()Ljava/lang/Class;".bytes() { return JavaLangObject.getClass(context, try receiver_ref(receiver)); }
        if method_name == "notify".bytes() and descriptor == "()V".bytes() { return JavaLangObject.notify(context, try receiver_ref(receiver)); }
        if method_name == "notifyAll".bytes() and descriptor == "()V".bytes() { return JavaLangObject.notifyAll(context, try receiver_ref(receiver)); }
        if method_name == "wait".bytes() and descriptor == "(J)V".bytes() { return JavaLangObject.wait(context, try receiver_ref(receiver), long_arg(arguments, 0)); }
    }

    if class_name == "java/lang/String".bytes() {
        if method_name == "intern".bytes() and descriptor == "()Ljava/lang/String;".bytes() { return JavaLangString.intern(context, try receiver_ref(receiver)); }
    }

    if class_name == "java/lang/Float".bytes() {
        if method_name == "floatToRawIntBits".bytes() and descriptor == "(F)I".bytes() { return JavaLangFloat.floatToRawIntBits(context, float_arg(arguments, 0)); }
        if method_name == "intBitsToFloat".bytes() and descriptor == "(I)F".bytes() { return JavaLangFloat.intBitsToFloat(context, int_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Double".bytes() {
        if method_name == "doubleToRawLongBits".bytes() and descriptor == "(D)J".bytes() { return JavaLangDouble.doubleToRawLongBits(context, double_arg(arguments, 0)); }
        if method_name == "longBitsToDouble".bytes() and descriptor == "(J)D".bytes() { return JavaLangDouble.longBitsToDouble(context, long_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Thread".bytes() {
        if method_name == "registerNatives".bytes() and descriptor == "()V".bytes() { return JavaLangThread.registerNatives(context); }
        if method_name == "isAlive".bytes() and descriptor == "()Z".bytes() { return JavaLangThread.isAlive(context, try receiver_ref(receiver)); }
        if method_name == "setPriority0".bytes() and descriptor == "(I)V".bytes() { return JavaLangThread.setPriority0(context, try receiver_ref(receiver), int_arg(arguments, 0)); }
        if method_name == "start0".bytes() and descriptor == "()V".bytes() { return JavaLangThread.start0(context, try receiver_ref(receiver)); }
        if method_name == "sleep".bytes() and descriptor == "(J)V".bytes() { return JavaLangThread.sleep(context, long_arg(arguments, 0)); }
        if method_name == "interrupt0".bytes() and descriptor == "()V".bytes() { return JavaLangThread.interrupt0(context, try receiver_ref(receiver)); }
        if method_name == "isInterrupted".bytes() and descriptor == "(Z)Z".bytes() { return JavaLangThread.isInterrupted(context, try receiver_ref(receiver), int_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Throwable".bytes() {
        if method_name == "getStackTraceDepth".bytes() and descriptor == "()I".bytes() { return JavaLangThrowable.getStackTraceDepth(context, try receiver_ref(receiver)); }
        if method_name == "fillInStackTrace".bytes() and descriptor == "(I)Ljava/lang/Throwable;".bytes() { return JavaLangThrowable.fillInStackTrace(context, try receiver_ref(receiver), int_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Runtime".bytes() {
        if method_name == "availableProcessors".bytes() and descriptor == "()I".bytes() { return JavaLangRuntime.availableProcessors(context, try receiver_ref(receiver)); }
    }

    if class_name == "sun/misc/VM".bytes() {
        if method_name == "initialize".bytes() and descriptor == "()V".bytes() { return SunMiscVM.initialize(context); }
    }

    if class_name == "sun/misc/Unsafe".bytes() {
        if method_name == "registerNatives".bytes() and descriptor == "()V".bytes() { return SunMiscUnsafe.registerNatives(context); }
        if method_name == "arrayBaseOffset".bytes() and descriptor == "(Ljava/lang/Class;)I".bytes() { return SunMiscUnsafe.arrayBaseOffset(context, ref_arg(arguments, 0)); }
        if method_name == "arrayIndexScale".bytes() and descriptor == "(Ljava/lang/Class;)I".bytes() { return SunMiscUnsafe.arrayIndexScale(context, ref_arg(arguments, 0)); }
        if method_name == "addressSize".bytes() and descriptor == "()I".bytes() { return SunMiscUnsafe.addressSize(context); }
    }

    return .err(InstructionError.unsupported_native);
}

import { Context } from .engine;
import { InstructionError, Reference, Value } from .types;
import { monotonic_ns, now_ns, ns_to_ms } from std.time;

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

    pub fn currentTimeMillis(context: &Context): result<?Value, InstructionError> {
        switch now_ns() {
        case .ok(ns) { return return_value(.long_value(ns_to_ms(ns))); }
        case .err(error_value) {
            const ignored_error = error_value;
            return .err(InstructionError.invalid_constant);
        }
        }
    }

    pub fn nanoTime(context: &Context): result<?Value, InstructionError> {
        switch monotonic_ns() {
        case .ok(ns) { return return_value(.long_value(ns)); }
        case .err(error_value) {
            const ignored_error = error_value;
            return .err(InstructionError.invalid_constant);
        }
        }
    }

    pub fn mapLibraryName(context: &Context, name: Reference): result<?Value, InstructionError> {
        return return_value(.ref_value(name));
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

struct JavaLangClass {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }
}

struct JavaLangClassLoader {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
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

struct JavaIoFileDescriptor {
    pub fn initIDs(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }
}

struct JavaIoFileInputStream {
    pub fn initIDs(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }
}

struct JavaIoFileOutputStream {
    pub fn initIDs(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }
}

struct JavaIoUnixFileSystem {
    pub fn initIDs(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }
}

struct JavaUtilConcurrentAtomicAtomicLong {
    pub fn VMSupportsCS8(context: &Context): result<?Value, InstructionError> {
        return return_value(.boolean_value(1));
    }
}

struct JavaUtilZipZipFile {
    pub fn initIDs(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }
}

fn method_is(method_name: string, method_descriptor: string, name: string, descriptor: string): bool {
    return method_name == name and method_descriptor == descriptor;
}

pub fn execute_native_method(context: &Context, class_index: usize, method_index: usize, receiver: ?Reference, arguments: []Value): result<?Value, InstructionError> {
    const class_name = context.classes[class_index].name;
    const method_name = context.classes[class_index].methods[method_index].name;
    const descriptor = context.classes[class_index].methods[method_index].descriptor;

    if class_name == "java/lang/System" {
        if method_is(method_name, descriptor, "registerNatives", "()V") { return JavaLangSystem.registerNatives(context); }
        if method_is(method_name, descriptor, "setIn0", "(Ljava/io/InputStream;)V") { return JavaLangSystem.setIn0(context, ref_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "setOut0", "(Ljava/io/PrintStream;)V") { return JavaLangSystem.setOut0(context, ref_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "setErr0", "(Ljava/io/PrintStream;)V") { return JavaLangSystem.setErr0(context, ref_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "currentTimeMillis", "()J") { return JavaLangSystem.currentTimeMillis(context); }
        if method_is(method_name, descriptor, "nanoTime", "()J") { return JavaLangSystem.nanoTime(context); }
        if method_is(method_name, descriptor, "arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V") { return JavaLangSystem.arraycopy(context, ref_arg(arguments, 0), int_arg(arguments, 1), ref_arg(arguments, 2), int_arg(arguments, 3), int_arg(arguments, 4)); }
        if method_is(method_name, descriptor, "identityHashCode", "(Ljava/lang/Object;)I") { return JavaLangSystem.identityHashCode(context, ref_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "mapLibraryName", "(Ljava/lang/String;)Ljava/lang/String;") { return JavaLangSystem.mapLibraryName(context, ref_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Object" {
        if method_is(method_name, descriptor, "registerNatives", "()V") { return JavaLangObject.registerNatives(context); }
        if method_is(method_name, descriptor, "hashCode", "()I") { return JavaLangObject.hashCode(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getClass", "()Ljava/lang/Class;") { return JavaLangObject.getClass(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "notify", "()V") { return JavaLangObject.notify(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "notifyAll", "()V") { return JavaLangObject.notifyAll(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "wait", "(J)V") { return JavaLangObject.wait(context, try receiver_ref(receiver), long_arg(arguments, 0)); }
    }

    if class_name == "java/lang/String" {
        if method_is(method_name, descriptor, "intern", "()Ljava/lang/String;") { return JavaLangString.intern(context, try receiver_ref(receiver)); }
    }

    if class_name == "java/lang/Class" {
        if method_is(method_name, descriptor, "registerNatives", "()V") { return JavaLangClass.registerNatives(context); }
    }

    if class_name == "java/lang/ClassLoader" {
        if method_is(method_name, descriptor, "registerNatives", "()V") { return JavaLangClassLoader.registerNatives(context); }
    }

    if class_name == "java/lang/Float" {
        if method_is(method_name, descriptor, "floatToRawIntBits", "(F)I") { return JavaLangFloat.floatToRawIntBits(context, float_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "intBitsToFloat", "(I)F") { return JavaLangFloat.intBitsToFloat(context, int_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Double" {
        if method_is(method_name, descriptor, "doubleToRawLongBits", "(D)J") { return JavaLangDouble.doubleToRawLongBits(context, double_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "longBitsToDouble", "(J)D") { return JavaLangDouble.longBitsToDouble(context, long_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Thread" {
        if method_is(method_name, descriptor, "registerNatives", "()V") { return JavaLangThread.registerNatives(context); }
        if method_is(method_name, descriptor, "isAlive", "()Z") { return JavaLangThread.isAlive(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "setPriority0", "(I)V") { return JavaLangThread.setPriority0(context, try receiver_ref(receiver), int_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "start0", "()V") { return JavaLangThread.start0(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "sleep", "(J)V") { return JavaLangThread.sleep(context, long_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "interrupt0", "()V") { return JavaLangThread.interrupt0(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "isInterrupted", "(Z)Z") { return JavaLangThread.isInterrupted(context, try receiver_ref(receiver), int_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Throwable" {
        if method_is(method_name, descriptor, "getStackTraceDepth", "()I") { return JavaLangThrowable.getStackTraceDepth(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "fillInStackTrace", "(I)Ljava/lang/Throwable;") { return JavaLangThrowable.fillInStackTrace(context, try receiver_ref(receiver), int_arg(arguments, 0)); }
    }

    if class_name == "java/lang/Runtime" {
        if method_is(method_name, descriptor, "availableProcessors", "()I") { return JavaLangRuntime.availableProcessors(context, try receiver_ref(receiver)); }
    }

    if class_name == "sun/misc/VM" {
        if method_is(method_name, descriptor, "initialize", "()V") { return SunMiscVM.initialize(context); }
    }

    if class_name == "sun/misc/Unsafe" {
        if method_is(method_name, descriptor, "registerNatives", "()V") { return SunMiscUnsafe.registerNatives(context); }
        if method_is(method_name, descriptor, "arrayBaseOffset", "(Ljava/lang/Class;)I") { return SunMiscUnsafe.arrayBaseOffset(context, ref_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "arrayIndexScale", "(Ljava/lang/Class;)I") { return SunMiscUnsafe.arrayIndexScale(context, ref_arg(arguments, 0)); }
        if method_is(method_name, descriptor, "addressSize", "()I") { return SunMiscUnsafe.addressSize(context); }
    }

    if class_name == "java/io/FileDescriptor" {
        if method_is(method_name, descriptor, "initIDs", "()V") { return JavaIoFileDescriptor.initIDs(context); }
    }

    if class_name == "java/io/FileInputStream" {
        if method_is(method_name, descriptor, "initIDs", "()V") { return JavaIoFileInputStream.initIDs(context); }
    }

    if class_name == "java/io/FileOutputStream" {
        if method_is(method_name, descriptor, "initIDs", "()V") { return JavaIoFileOutputStream.initIDs(context); }
    }

    if class_name == "java/io/UnixFileSystem" {
        if method_is(method_name, descriptor, "initIDs", "()V") { return JavaIoUnixFileSystem.initIDs(context); }
    }

    if class_name == "java/util/concurrent/atomic/AtomicLong" {
        if method_is(method_name, descriptor, "VMSupportsCS8", "()Z") { return JavaUtilConcurrentAtomicAtomicLong.VMSupportsCS8(context); }
    }

    if class_name == "java/util/zip/ZipFile" {
        if method_is(method_name, descriptor, "initIDs", "()V") { return JavaUtilZipZipFile.initIDs(context); }
    }

    return .err(InstructionError.unsupported_native);
}

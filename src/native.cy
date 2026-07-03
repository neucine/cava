import { Constant } from .classfile;
import { Context } from .engine;
import { new_frame } from .engine;
import { new_heap } from .heap;
import { Class, Field, InstructionError, Reference, ReferenceKind, Value, class_access_flags, field_access_flags, null_ref, raw_class_access } from .types;
import { monotonic_ns, now_ns, ns_to_ms } from std.time;

fn ref_arg(arguments: &List<Value>, index: usize): Reference {
    switch arguments[index] {
    case .ref_value(actual) { return actual; }
    else { return Reference.init_null(); }
    }
}

fn value_ref_or_null(value: Value): Reference {
    switch value {
    case .ref_value(actual) { return actual; }
    case .byte_value(ignored) { const unused = ignored; return null_ref; }
    case .short_value(ignored) { const unused = ignored; return null_ref; }
    case .char_value(ignored) { const unused = ignored; return null_ref; }
    case .int_value(ignored) { const unused = ignored; return null_ref; }
    case .long_value(ignored) { const unused = ignored; return null_ref; }
    case .float_value(ignored) { const unused = ignored; return null_ref; }
    case .double_value(ignored) { const unused = ignored; return null_ref; }
    case .boolean_value(ignored) { const unused = ignored; return null_ref; }
    case .return_address_value(ignored) { const unused = ignored; return null_ref; }
    }
}

fn int_arg(arguments: &List<Value>, index: usize): i32 {
    switch arguments[index] {
    case .int_value(actual) { return actual; }
    case .boolean_value(actual) { return actual as i32; }
    case .byte_value(actual) { return actual as i32; }
    case .short_value(actual) { return actual as i32; }
    case .char_value(actual) { return actual as i32; }
    else { return 0; }
    }
}

fn long_arg(arguments: &List<Value>, index: usize): i64 {
    switch arguments[index] {
    case .long_value(actual) { return actual; }
    else { return 0; }
    }
}

fn float_arg(arguments: &List<Value>, index: usize): f32 {
    switch arguments[index] {
    case .float_value(actual) { return actual; }
    else { return 0.0; }
    }
}

fn double_arg(arguments: &List<Value>, index: usize): f64 {
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

fn set_system_static_ref(context: &Context, name: []const u8, descriptor: []const u8, reference: Reference): result<void, InstructionError> {
    var index: usize = 0;
    while index < context.classes.len() {
        if context.classes[index].name == "java/lang/System" {
            if context.classes[index].field_index(name, descriptor, true) is field_index_value {
                const field = context.classes[index].fields[field_index_value as usize];
                context.classes[index].static_vars[field.slot as usize] = .ref_value(reference);
                return .ok();
            }
            return .err(InstructionError.invalid_constant);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_native_class_index(context: &Context, name: string): result<usize, InstructionError> {
    var index: usize = 0;
    while index < context.classes.len() {
        if context.classes[index].name == name {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_loaded_class_index(classes: []Class, name: string): ?usize {
    var index: usize = 0;
    while index < classes.len() {
        if classes[index].name == name {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn find_class_object_index(context: &Context, class_object: Reference): ?usize {
    var index: usize = 0;
    while index < context.classes.len() {
        if context.classes[index].class_object.equals(class_object) {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn set_instance_field(context: &Context, reference: Reference, class_index: usize, name: []const u8, descriptor: []const u8, value: Value): result<void, InstructionError> {
    if context.classes[class_index].field_index(name, descriptor, false) is field_index {
        const slot = context.classes[class_index].fields[field_index as usize].slot;
        if !context.heap.set_field(reference, slot, value) {
            return .err(InstructionError.invalid_constant);
        }
    }
    return .ok();
}

fn java_string(context: &Context, value: []const u8): ?Reference {
    if find_loaded_class_index(context.classes, "java/lang/String") is string_class_index {
        var classes = context.classes;
        if context.heap.interned_string_reference(value) is existing {
            return existing;
        }
        const reference = context.heap.allocate_object_with_hierarchy(string_class_index, classes);
        if classes[string_class_index].field_index("value".bytes(), "[C".bytes(), false) is value_field_index {
            const chars_reference = context.heap.allocate_array(0, "C".bytes(), value.len());
            var byte_index: usize = 0;
            while byte_index < value.len() {
                const ignored_element = context.heap.set_element(chars_reference, byte_index, .char_value(value[byte_index] as u16));
                byte_index = byte_index + 1;
            }
            const slot = classes[string_class_index].fields[value_field_index as usize].slot;
            const ignored_field = context.heap.set_field(reference, slot, .ref_value(chars_reference));
        }
        if classes[string_class_index].field_index("coder".bytes(), "B".bytes(), false) is coder_field_index {
            const slot = classes[string_class_index].fields[coder_field_index as usize].slot;
            const ignored_coder = context.heap.set_field(reference, slot, .byte_value(0));
        }
        context.heap.register_string_bytes(reference, value);
        return reference;
    }
    return none;
}

fn java_string_buffer(context: &Context, data: [:]u8): result<Reference, InstructionError> {
    var bytes = data;
    if find_loaded_class_index(context.classes, "java/lang/String") is string_class_index {
        var classes = context.classes;
        return .ok(context.heap.intern_string_buffer(string_class_index, &classes[string_class_index], bytes));
    }
    drop bytes;
    return .err(InstructionError.invalid_constant);
}

fn concat_java_string(context: &Context, left_reference: Reference, right_reference: Reference): result<Reference, InstructionError> {
    if find_loaded_class_index(context.classes, "java/lang/String") is string_class_index {
        var classes = context.classes;
        return .ok(context.heap.concat_strings(string_class_index, &classes[string_class_index], left_reference, right_reference));
    }
    return .err(InstructionError.invalid_constant);
}

fn print_java_string(context: &Context, reference: Reference): void {
    var value_option = context.heap.string_bytes(reference);
    if take value_option is value {
        const bytes = copy value.value;
        const text = string.from(bytes[..]);
        println(text);
        drop text;
        drop bytes;
        drop value;
        return;
    }
    println("");
}

fn new_thread_group(context: &Context): result<Reference, InstructionError> {
    if find_loaded_class_index(context.classes, "java/lang/ThreadGroup") is group_class_index {
        var classes = context.classes;
        const group = context.heap.allocate_object(group_class_index, &classes[group_class_index]);
        if java_string(context, "main".bytes()) is group_name {
            try set_instance_field(context, group, group_class_index, "name".bytes(), "Ljava/lang/String;".bytes(), .ref_value(group_name));
        }
        return .ok(group);
    }
    return .ok(null_ref);
}

fn new_java_lang_thread(context: &Context): result<Reference, InstructionError> {
    if context.heap.current_thread_ref() is cached {
        if context.heap.has_object(cached) {
            return .ok(cached);
        }
    }
    if find_loaded_class_index(context.classes, "java/lang/Thread") is thread_class_index {
        var classes = context.classes;
        const thread = context.heap.allocate_object(thread_class_index, &classes[thread_class_index]);
        if java_string(context, "main".bytes()) is name {
            try set_instance_field(context, thread, thread_class_index, "name".bytes(), "Ljava/lang/String;".bytes(), .ref_value(name));
        }
        try set_instance_field(context, thread, thread_class_index, "tid".bytes(), "J".bytes(), .long_value(1));
        try set_instance_field(context, thread, thread_class_index, "priority".bytes(), "I".bytes(), .int_value(1));
        const group = try new_thread_group(context);
        if group.non_null() {
            try set_instance_field(context, thread, thread_class_index, "group".bytes(), "Ljava/lang/ThreadGroup;".bytes(), .ref_value(group));
        }
        context.heap.set_current_thread(thread);
        return .ok(thread);
    }
    return .err(InstructionError.invalid_constant);
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

fn clone_array(context: &Context, receiver: Reference, class_index: usize): result<Reference, InstructionError> {
    var length: usize = 0;
    if context.heap.array_length(receiver) is actual_length {
        length = actual_length;
    } else {
        return .err(InstructionError.invalid_constant);
    }

    const component_type = context.classes[class_index].component_type;
    const clone = context.heap.allocate_array(class_index, component_type.bytes(), length);
    var index: usize = 0;
    while index < length {
        var value: Value = .int_value(0);
        if context.heap.get_element(receiver, index) is actual_value {
            value = actual_value;
        } else {
            return .err(InstructionError.invalid_constant);
        }
        if !context.heap.set_element(clone, index, value) {
            return .err(InstructionError.invalid_constant);
        }
        index = index + 1;
    }
    return .ok(clone);
}

fn clone_object(context: &Context, receiver: Reference, class_index: usize): result<Reference, InstructionError> {
    var classes = context.classes;
    const class = &classes[class_index];
    const clone = context.heap.allocate_object(class_index, class);
    var slot: u16 = 0;
    while slot < class.instance_vars {
        var value: Value = .int_value(0);
        if context.heap.get_field(receiver, slot) is actual_value {
            value = actual_value;
        } else {
            return .err(InstructionError.invalid_constant);
        }
        if !context.heap.set_field(clone, slot, value) {
            return .err(InstructionError.invalid_constant);
        }
        slot = slot + 1;
    }
    return .ok(clone);
}

struct JavaLangSystem {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn setIn0(context: &Context, input: Reference): result<?Value, InstructionError> {
        try set_system_static_ref(context, "in".bytes(), "Ljava/io/InputStream;".bytes(), input);
        return .ok(none);
    }

    pub fn setOut0(context: &Context, output: Reference): result<?Value, InstructionError> {
        try set_system_static_ref(context, "out".bytes(), "Ljava/io/PrintStream;".bytes(), output);
        return .ok(none);
    }

    pub fn setErr0(context: &Context, error_stream: Reference): result<?Value, InstructionError> {
        try set_system_static_ref(context, "err".bytes(), "Ljava/io/PrintStream;".bytes(), error_stream);
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

    pub fn initProperties(context: &Context, properties: Reference): result<?Value, InstructionError> {
        return return_value(.ref_value(properties));
    }

    pub fn getProperty(context: &Context, key: Reference): result<?Value, InstructionError> {
        const ignored_key = key;
        if java_string(context, "Cava".bytes()) is value {
            return return_value(.ref_value(value));
        }
        return .err(InstructionError.invalid_constant);
    }
}

struct JavaLangObject {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn init(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
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

    pub fn clone(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if context.heap.object_class_index(receiver) is actual_class_index {
            return return_value(.ref_value(try clone_object(context, receiver, actual_class_index)));
        }
        if context.heap.array_class_index(receiver) is actual_class_index {
            return return_value(.ref_value(try clone_array(context, receiver, actual_class_index)));
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

    pub fn getPrimitiveClass(context: &Context, name: Reference): result<?Value, InstructionError> {
        const ignored_name = name;
        const class_class_index = try find_native_class_index(context, "java/lang/Class");
        var classes = context.classes;
        const reference = context.heap.allocate_object(class_class_index, &classes[class_class_index]);
        return return_value(.ref_value(reference));
    }

    pub fn desiredAssertionStatus0(context: &Context, class_object: Reference): result<?Value, InstructionError> {
        const ignored_class_object = class_object;
        return return_value(.boolean_value(0));
    }

    pub fn isPrimitive(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.boolean_value(0));
    }

    pub fn getName0(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, receiver) is class_index {
            if java_string(context, context.classes[class_index].name.bytes()) is value {
                return return_value(.ref_value(value));
            }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn initClassName(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        return JavaLangClass.getName0(context, receiver);
    }

    pub fn descriptorString(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, receiver) is class_index {
            if java_string(context, context.classes[class_index].descriptor.bytes()) is value {
                return return_value(.ref_value(value));
            }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn isArray(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, receiver) is class_index {
            if context.classes[class_index].is_array {
                return return_value(.boolean_value(1));
            }
            return return_value(.boolean_value(0));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getComponentType(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, receiver) is class_index {
            if !context.classes[class_index].is_array {
                return return_value(.ref_value(null_ref));
            }
            const component = context.classes[class_index].component_type.bytes();
            if component.len() > 2 and component[0] == 76 {
                const name = string.from(component[1..component.len() - 1]);
                switch find_native_class_index(context, name) {
                case .ok(component_index) {
                    drop name;
                    return return_value(.ref_value(context.classes[component_index].class_object));
                }
                case .err(error_value) {
                    const ignored = error_value;
                    drop name;
                }
                }
            }
            if component.len() > 0 and component[0] == 91 {
                const name = string.from(component);
                switch find_native_class_index(context, name) {
                case .ok(component_index) {
                    drop name;
                    return return_value(.ref_value(context.classes[component_index].class_object));
                }
                case .err(error_value) {
                    const ignored = error_value;
                    drop name;
                }
                }
            }
            const class_class_index = try find_native_class_index(context, "java/lang/Class");
            var classes = context.classes;
            const class_class = &classes[class_class_index];
            if class_class.class_object.is_null() {
                class_class.class_object = context.heap.allocate_object(class_class_index, class_class);
            }
            return return_value(.ref_value(class_class.class_object));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn isInterface(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, receiver) is class_index {
            if context.classes[class_index].is_interface() {
                return return_value(.boolean_value(1));
            }
            return return_value(.boolean_value(0));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getModifiers(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, receiver) is class_index {
            return return_value(.int_value(raw_class_access(context.classes[class_index].access_flags) as i32));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getSuperclass(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, receiver) is class_index {
            const super_class = context.classes[class_index].super_class;
            if super_class == "" {
                return return_value(.ref_value(null_ref));
            }
            if find_loaded_class_index(context.classes, super_class) is super_index {
                return return_value(.ref_value(context.classes[super_index].class_object));
            }
            return return_value(.ref_value(null_ref));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getClassAccessFlagsRaw0(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        return JavaLangClass.getModifiers(context, receiver);
    }

    pub fn getClassFileVersion0(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.int_value(52));
    }

    pub fn isHidden(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.boolean_value(0));
    }

    pub fn isRecord0(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.boolean_value(0));
    }
}

struct JavaLangClassLoader {
    pub fn registerNatives(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn findBuiltinLib(context: &Context, name: Reference): result<?Value, InstructionError> {
        const ignored_name = name;
        return return_value(.ref_value(null_ref));
    }
}

struct JavaLangClassLoaderNativeLibrary {
    pub fn load(context: &Context, receiver: Reference, name: Reference, is_builtin: i32): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_name = name;
        const ignored_is_builtin = is_builtin;
        return .ok(none);
    }
}

struct JavaLangPackage {
    pub fn getSystemPackage0(context: &Context, name: Reference): result<?Value, InstructionError> {
        const ignored_name = name;
        return return_value(.ref_value(null_ref));
    }
}

struct JavaLangString {
    pub fn intern(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const out: Value = .ref_value(Reference {
            kind: receiver.kind,
            slot: receiver.slot,
            generation: receiver.generation,
        });
        return .ok(out);
    }
}

fn java_lang_string_builder_append(context: &Context, receiver: Reference, value: Reference): result<?Value, InstructionError> {
    var heap = context.heap;
    const slot: u16 = 0;
    var current_ref = null_ref;
    if heap.get_field(receiver, slot) is current_value {
        current_ref = value_ref_or_null(current_value);
    } else {
        return .err(InstructionError.invalid_constant);
    }
    const combined_ref = try concat_java_string(context, current_ref, value);
    if !heap.set_field(receiver, slot, .ref_value(combined_ref)) {
        return .err(InstructionError.invalid_constant);
    }
    const out: Value = .ref_value(Reference {
        kind: receiver.kind,
        slot: receiver.slot,
        generation: receiver.generation,
    });
    return .ok(out);
}

fn java_lang_string_builder_init(context: &Context, receiver: Reference): result<?Value, InstructionError> {
    return .ok(none);
}

fn java_lang_string_builder_to_string(context: &Context, receiver: Reference): result<?Value, InstructionError> {
    var heap = context.heap;
    const slot: u16 = 0;
    if heap.get_field(receiver, slot) is current_value {
        const actual = value_ref_or_null(current_value);
        if actual.non_null() {
            const out: Value = .ref_value(Reference {
                kind: actual.kind,
                slot: actual.slot,
                generation: actual.generation,
            });
            return .ok(out);
        }
    }
    return return_value(.ref_value(null_ref));
}

fn java_io_print_stream_println(context: &Context, receiver: Reference, value: Reference): result<?Value, InstructionError> {
    print_java_string(context, value);
    return .ok(none);
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

    pub fn currentThread(context: &Context): result<?Value, InstructionError> {
        return return_value(.ref_value(try new_java_lang_thread(context)));
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

    pub fn holdsLock(context: &Context, object: Reference): result<?Value, InstructionError> {
        const ignored_object = object;
        return return_value(.boolean_value(0));
    }

    pub fn yield0(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn clearInterruptEvent(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn setNativeName(context: &Context, receiver: Reference, name: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_name = name;
        return .ok(none);
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

    pub fn freeMemory(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.long_value(16 * 1024 * 1024));
    }

    pub fn totalMemory(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.long_value(16 * 1024 * 1024));
    }

    pub fn maxMemory(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.long_value(256 * 1024 * 1024));
    }

    pub fn gc(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return .ok(none);
    }
}

struct JavaLangShutdown {
    pub fn beforeHalt(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn halt0(context: &Context, status: i32): result<?Value, InstructionError> {
        const ignored_status = status;
        return .ok(none);
    }
}

struct JavaLangRefFinalizer {
    pub fn isFinalizationEnabled(context: &Context): result<?Value, InstructionError> {
        return return_value(.boolean_value(0));
    }

    pub fn reportComplete(context: &Context, finalizer: Reference): result<?Value, InstructionError> {
        const ignored_finalizer = finalizer;
        return .ok(none);
    }
}

struct JavaLangRefReference {
    pub fn getAndClearReferencePendingList(context: &Context): result<?Value, InstructionError> {
        return return_value(.ref_value(null_ref));
    }

    pub fn hasReferencePendingList(context: &Context): result<?Value, InstructionError> {
        return return_value(.boolean_value(0));
    }

    pub fn waitForReferencePendingList(context: &Context): result<?Value, InstructionError> {
        return .ok(none);
    }

    pub fn refersTo0(context: &Context, receiver: Reference, object: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_object = object;
        return return_value(.boolean_value(0));
    }

    pub fn clear0(context: &Context, receiver: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return .ok(none);
    }
}

struct SunReflectReflection {
    pub fn getCallerClass(context: &Context): result<?Value, InstructionError> {
        const class_object = context.classes[context.class_index].class_object;
        return return_value(.ref_value(class_object));
    }

    pub fn getClassAccessFlags(context: &Context, class_object: Reference): result<?Value, InstructionError> {
        if find_class_object_index(context, class_object) is class_index {
            return return_value(.int_value(raw_class_access(context.classes[class_index].access_flags) as i32));
        }
        return .err(InstructionError.invalid_constant);
    }
}

struct JdkInternalReflectReflection {
    pub fn getCallerClass(context: &Context): result<?Value, InstructionError> {
        return SunReflectReflection.getCallerClass(context);
    }

    pub fn getClassAccessFlags(context: &Context, class_object: Reference): result<?Value, InstructionError> {
        return SunReflectReflection.getClassAccessFlags(context, class_object);
    }
}

struct JavaSecurityAccessController {
    pub fn getStackAccessControlContext(context: &Context): result<?Value, InstructionError> {
        return return_value(.ref_value(null_ref));
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

    pub fn canonicalize0(context: &Context, receiver: Reference, path: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        return return_value(.ref_value(path));
    }

    pub fn getBooleanAttributes0(context: &Context, receiver: Reference, file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        return return_value(.int_value(0));
    }

    pub fn checkAccess0(context: &Context, receiver: Reference, file: Reference, access: i32): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_access = access;
        return return_value(.boolean_value(0));
    }

    pub fn getLastModifiedTime0(context: &Context, receiver: Reference, file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        return return_value(.long_value(0));
    }

    pub fn getLength0(context: &Context, receiver: Reference, file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        return return_value(.long_value(0));
    }

    pub fn setPermission0(context: &Context, receiver: Reference, file: Reference, access: i32, enable: i32, owneronly: i32): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_access = access;
        const ignored_enable = enable;
        const ignored_owneronly = owneronly;
        return return_value(.boolean_value(0));
    }

    pub fn createFileExclusively0(context: &Context, receiver: Reference, path: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_path = path;
        return return_value(.boolean_value(0));
    }

    pub fn delete0(context: &Context, receiver: Reference, file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        return return_value(.boolean_value(0));
    }

    pub fn list0(context: &Context, receiver: Reference, file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        return return_value(.ref_value(null_ref));
    }

    pub fn createDirectory0(context: &Context, receiver: Reference, file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        return return_value(.boolean_value(0));
    }

    pub fn rename0(context: &Context, receiver: Reference, from_file: Reference, to_file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_from_file = from_file;
        const ignored_to_file = to_file;
        return return_value(.boolean_value(0));
    }

    pub fn setLastModifiedTime0(context: &Context, receiver: Reference, file: Reference, time: i64): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_time = time;
        return return_value(.boolean_value(0));
    }

    pub fn setReadOnly0(context: &Context, receiver: Reference, file: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        return return_value(.boolean_value(0));
    }

    pub fn getSpace0(context: &Context, receiver: Reference, file: Reference, t: i32): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_t = t;
        return return_value(.long_value(0));
    }

    pub fn getNameMax0(context: &Context, receiver: Reference, path: Reference): result<?Value, InstructionError> {
        const ignored_receiver = receiver;
        const ignored_path = path;
        return return_value(.long_value(255));
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

fn method_is(method_name: []const u8, method_descriptor: []const u8, name: []const u8, descriptor: []const u8): bool {
    return method_name == name and method_descriptor == descriptor;
}

pub fn execute_native_method(context: &Context, class_index: usize, method_index: usize, receiver: ?Reference, arguments: List<Value>): result<?Value, InstructionError> {
    var args = arguments;
    const class_name = context.classes[class_index].name.bytes();
    const method_name = context.classes[class_index].methods[method_index].name.bytes();
    const descriptor = context.classes[class_index].methods[method_index].descriptor.bytes();

    if class_name == "java/lang/System".bytes() {
        if method_is(method_name, descriptor, "registerNatives".bytes(), "()V".bytes()) { return JavaLangSystem.registerNatives(context); }
        if method_is(method_name, descriptor, "setIn0".bytes(), "(Ljava/io/InputStream;)V".bytes()) { return JavaLangSystem.setIn0(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "setOut0".bytes(), "(Ljava/io/PrintStream;)V".bytes()) { return JavaLangSystem.setOut0(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "setErr0".bytes(), "(Ljava/io/PrintStream;)V".bytes()) { return JavaLangSystem.setErr0(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "currentTimeMillis".bytes(), "()J".bytes()) { return JavaLangSystem.currentTimeMillis(context); }
        if method_is(method_name, descriptor, "nanoTime".bytes(), "()J".bytes()) { return JavaLangSystem.nanoTime(context); }
        if method_is(method_name, descriptor, "arraycopy".bytes(), "(Ljava/lang/Object;ILjava/lang/Object;II)V".bytes()) { return JavaLangSystem.arraycopy(context, ref_arg(&args, 0), int_arg(&args, 1), ref_arg(&args, 2), int_arg(&args, 3), int_arg(&args, 4)); }
        if method_is(method_name, descriptor, "identityHashCode".bytes(), "(Ljava/lang/Object;)I".bytes()) { return JavaLangSystem.identityHashCode(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "mapLibraryName".bytes(), "(Ljava/lang/String;)Ljava/lang/String;".bytes()) { return JavaLangSystem.mapLibraryName(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "initProperties".bytes(), "(Ljava/util/Properties;)Ljava/util/Properties;".bytes()) { return JavaLangSystem.initProperties(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "getProperty".bytes(), "(Ljava/lang/String;)Ljava/lang/String;".bytes()) { return JavaLangSystem.getProperty(context, ref_arg(&args, 0)); }
    }

    if class_name == "java/lang/Object".bytes() {
        if method_is(method_name, descriptor, "<init>".bytes(), "()V".bytes()) { return JavaLangObject.init(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "registerNatives".bytes(), "()V".bytes()) { return JavaLangObject.registerNatives(context); }
        if method_is(method_name, descriptor, "hashCode".bytes(), "()I".bytes()) { return JavaLangObject.hashCode(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getClass".bytes(), "()Ljava/lang/Class;".bytes()) { return JavaLangObject.getClass(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "clone".bytes(), "()Ljava/lang/Object;".bytes()) { return JavaLangObject.clone(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "notify".bytes(), "()V".bytes()) { return JavaLangObject.notify(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "notifyAll".bytes(), "()V".bytes()) { return JavaLangObject.notifyAll(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "wait".bytes(), "(J)V".bytes()) { return JavaLangObject.wait(context, try receiver_ref(receiver), long_arg(&args, 0)); }
    }

    if class_name == "java/lang/String".bytes() {
        if method_is(method_name, descriptor, "intern".bytes(), "()Ljava/lang/String;".bytes()) { return JavaLangString.intern(context, try receiver_ref(receiver)); }
    }

    if class_name == "java/lang/StringBuilder".bytes() {
        if method_is(method_name, descriptor, "<init>".bytes(), "()V".bytes()) { return java_lang_string_builder_init(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "append".bytes(), "(Ljava/lang/String;)Ljava/lang/StringBuilder;".bytes()) { return java_lang_string_builder_append(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "toString".bytes(), "()Ljava/lang/String;".bytes()) { return java_lang_string_builder_to_string(context, try receiver_ref(receiver)); }
    }

    if class_name == "java/lang/Class".bytes() {
        if method_is(method_name, descriptor, "registerNatives".bytes(), "()V".bytes()) { return JavaLangClass.registerNatives(context); }
        if method_is(method_name, descriptor, "getPrimitiveClass".bytes(), "(Ljava/lang/String;)Ljava/lang/Class;".bytes()) { return JavaLangClass.getPrimitiveClass(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "desiredAssertionStatus0".bytes(), "(Ljava/lang/Class;)Z".bytes()) { return JavaLangClass.desiredAssertionStatus0(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "isPrimitive".bytes(), "()Z".bytes()) { return JavaLangClass.isPrimitive(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getName0".bytes(), "()Ljava/lang/String;".bytes()) { return JavaLangClass.getName0(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "initClassName".bytes(), "()Ljava/lang/String;".bytes()) { return JavaLangClass.initClassName(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "descriptorString".bytes(), "()Ljava/lang/String;".bytes()) { return JavaLangClass.descriptorString(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "isArray".bytes(), "()Z".bytes()) { return JavaLangClass.isArray(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getComponentType".bytes(), "()Ljava/lang/Class;".bytes()) { return JavaLangClass.getComponentType(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "isInterface".bytes(), "()Z".bytes()) { return JavaLangClass.isInterface(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getModifiers".bytes(), "()I".bytes()) { return JavaLangClass.getModifiers(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getSuperclass".bytes(), "()Ljava/lang/Class;".bytes()) { return JavaLangClass.getSuperclass(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getClassAccessFlagsRaw0".bytes(), "()I".bytes()) { return JavaLangClass.getClassAccessFlagsRaw0(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "getClassFileVersion0".bytes(), "()I".bytes()) { return JavaLangClass.getClassFileVersion0(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "isHidden".bytes(), "()Z".bytes()) { return JavaLangClass.isHidden(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "isRecord0".bytes(), "()Z".bytes()) { return JavaLangClass.isRecord0(context, try receiver_ref(receiver)); }
    }

    if class_name == "java/lang/ClassLoader".bytes() {
        if method_is(method_name, descriptor, "registerNatives".bytes(), "()V".bytes()) { return JavaLangClassLoader.registerNatives(context); }
        if method_is(method_name, descriptor, "findBuiltinLib".bytes(), "(Ljava/lang/String;)Ljava/lang/String;".bytes()) { return JavaLangClassLoader.findBuiltinLib(context, ref_arg(&args, 0)); }
    }

    if class_name == "java/lang/ClassLoader$NativeLibrary".bytes() {
        if method_is(method_name, descriptor, "load".bytes(), "(Ljava/lang/String;Z)V".bytes()) { return JavaLangClassLoaderNativeLibrary.load(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1)); }
    }

    if class_name == "java/lang/Package".bytes() {
        if method_is(method_name, descriptor, "getSystemPackage0".bytes(), "(Ljava/lang/String;)Ljava/lang/String;".bytes()) { return JavaLangPackage.getSystemPackage0(context, ref_arg(&args, 0)); }
    }

    if class_name == "java/lang/Float".bytes() {
        if method_is(method_name, descriptor, "floatToRawIntBits".bytes(), "(F)I".bytes()) { return JavaLangFloat.floatToRawIntBits(context, float_arg(&args, 0)); }
        if method_is(method_name, descriptor, "intBitsToFloat".bytes(), "(I)F".bytes()) { return JavaLangFloat.intBitsToFloat(context, int_arg(&args, 0)); }
    }

    if class_name == "java/lang/Double".bytes() {
        if method_is(method_name, descriptor, "doubleToRawLongBits".bytes(), "(D)J".bytes()) { return JavaLangDouble.doubleToRawLongBits(context, double_arg(&args, 0)); }
        if method_is(method_name, descriptor, "longBitsToDouble".bytes(), "(J)D".bytes()) { return JavaLangDouble.longBitsToDouble(context, long_arg(&args, 0)); }
    }

    if class_name == "java/lang/Thread".bytes() {
        if method_is(method_name, descriptor, "registerNatives".bytes(), "()V".bytes()) { return JavaLangThread.registerNatives(context); }
        if method_is(method_name, descriptor, "currentThread".bytes(), "()Ljava/lang/Thread;".bytes()) { return JavaLangThread.currentThread(context); }
        if method_is(method_name, descriptor, "isAlive".bytes(), "()Z".bytes()) { return JavaLangThread.isAlive(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "setPriority0".bytes(), "(I)V".bytes()) { return JavaLangThread.setPriority0(context, try receiver_ref(receiver), int_arg(&args, 0)); }
        if method_is(method_name, descriptor, "start0".bytes(), "()V".bytes()) { return JavaLangThread.start0(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "sleep".bytes(), "(J)V".bytes()) { return JavaLangThread.sleep(context, long_arg(&args, 0)); }
        if method_is(method_name, descriptor, "interrupt0".bytes(), "()V".bytes()) { return JavaLangThread.interrupt0(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "isInterrupted".bytes(), "(Z)Z".bytes()) { return JavaLangThread.isInterrupted(context, try receiver_ref(receiver), int_arg(&args, 0)); }
        if method_is(method_name, descriptor, "holdsLock".bytes(), "(Ljava/lang/Object;)Z".bytes()) { return JavaLangThread.holdsLock(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "yield0".bytes(), "()V".bytes()) { return JavaLangThread.yield0(context); }
        if method_is(method_name, descriptor, "clearInterruptEvent".bytes(), "()V".bytes()) { return JavaLangThread.clearInterruptEvent(context); }
        if method_is(method_name, descriptor, "setNativeName".bytes(), "(Ljava/lang/String;)V".bytes()) { return JavaLangThread.setNativeName(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
    }

    if class_name == "java/lang/Throwable".bytes() {
        if method_is(method_name, descriptor, "getStackTraceDepth".bytes(), "()I".bytes()) { return JavaLangThrowable.getStackTraceDepth(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "fillInStackTrace".bytes(), "(I)Ljava/lang/Throwable;".bytes()) { return JavaLangThrowable.fillInStackTrace(context, try receiver_ref(receiver), int_arg(&args, 0)); }
    }

    if class_name == "java/lang/Runtime".bytes() {
        if method_is(method_name, descriptor, "availableProcessors".bytes(), "()I".bytes()) { return JavaLangRuntime.availableProcessors(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "freeMemory".bytes(), "()J".bytes()) { return JavaLangRuntime.freeMemory(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "totalMemory".bytes(), "()J".bytes()) { return JavaLangRuntime.totalMemory(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "maxMemory".bytes(), "()J".bytes()) { return JavaLangRuntime.maxMemory(context, try receiver_ref(receiver)); }
        if method_is(method_name, descriptor, "gc".bytes(), "()V".bytes()) { return JavaLangRuntime.gc(context, try receiver_ref(receiver)); }
    }

    if class_name == "java/lang/Shutdown".bytes() {
        if method_is(method_name, descriptor, "beforeHalt".bytes(), "()V".bytes()) { return JavaLangShutdown.beforeHalt(context); }
        if method_is(method_name, descriptor, "halt0".bytes(), "(I)V".bytes()) { return JavaLangShutdown.halt0(context, int_arg(&args, 0)); }
    }

    if class_name == "java/lang/ref/Finalizer".bytes() {
        if method_is(method_name, descriptor, "isFinalizationEnabled".bytes(), "()Z".bytes()) { return JavaLangRefFinalizer.isFinalizationEnabled(context); }
        if method_is(method_name, descriptor, "reportComplete".bytes(), "(Ljava/lang/Object;)V".bytes()) { return JavaLangRefFinalizer.reportComplete(context, ref_arg(&args, 0)); }
    }

    if class_name == "java/lang/ref/Reference".bytes() {
        if method_is(method_name, descriptor, "getAndClearReferencePendingList".bytes(), "()Ljava/lang/ref/Reference;".bytes()) { return JavaLangRefReference.getAndClearReferencePendingList(context); }
        if method_is(method_name, descriptor, "hasReferencePendingList".bytes(), "()Z".bytes()) { return JavaLangRefReference.hasReferencePendingList(context); }
        if method_is(method_name, descriptor, "waitForReferencePendingList".bytes(), "()V".bytes()) { return JavaLangRefReference.waitForReferencePendingList(context); }
        if method_is(method_name, descriptor, "refersTo0".bytes(), "(Ljava/lang/Object;)Z".bytes()) { return JavaLangRefReference.refersTo0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "clear0".bytes(), "()V".bytes()) { return JavaLangRefReference.clear0(context, try receiver_ref(receiver)); }
    }

    if class_name == "sun/reflect/Reflection".bytes() {
        if method_is(method_name, descriptor, "getCallerClass".bytes(), "()Ljava/lang/Class;".bytes()) { return SunReflectReflection.getCallerClass(context); }
        if method_is(method_name, descriptor, "getClassAccessFlags".bytes(), "(Ljava/lang/Class;)I".bytes()) { return SunReflectReflection.getClassAccessFlags(context, ref_arg(&args, 0)); }
    }

    if class_name == "jdk/internal/reflect/Reflection".bytes() {
        if method_is(method_name, descriptor, "getCallerClass".bytes(), "()Ljava/lang/Class;".bytes()) { return JdkInternalReflectReflection.getCallerClass(context); }
        if method_is(method_name, descriptor, "getClassAccessFlags".bytes(), "(Ljava/lang/Class;)I".bytes()) { return JdkInternalReflectReflection.getClassAccessFlags(context, ref_arg(&args, 0)); }
    }

    if class_name == "java/security/AccessController".bytes() {
        if method_is(method_name, descriptor, "getStackAccessControlContext".bytes(), "()Ljava/security/AccessControlContext;".bytes()) { return JavaSecurityAccessController.getStackAccessControlContext(context); }
    }

    if class_name == "sun/misc/VM".bytes() {
        if method_is(method_name, descriptor, "initialize".bytes(), "()V".bytes()) { return SunMiscVM.initialize(context); }
    }

    if class_name == "sun/misc/Unsafe".bytes() {
        if method_is(method_name, descriptor, "registerNatives".bytes(), "()V".bytes()) { return SunMiscUnsafe.registerNatives(context); }
        if method_is(method_name, descriptor, "arrayBaseOffset".bytes(), "(Ljava/lang/Class;)I".bytes()) { return SunMiscUnsafe.arrayBaseOffset(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "arrayIndexScale".bytes(), "(Ljava/lang/Class;)I".bytes()) { return SunMiscUnsafe.arrayIndexScale(context, ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "addressSize".bytes(), "()I".bytes()) { return SunMiscUnsafe.addressSize(context); }
    }

    if class_name == "java/io/FileDescriptor".bytes() {
        if method_is(method_name, descriptor, "initIDs".bytes(), "()V".bytes()) { return JavaIoFileDescriptor.initIDs(context); }
    }

    if class_name == "java/io/PrintStream".bytes() {
        if method_is(method_name, descriptor, "println".bytes(), "(Ljava/lang/String;)V".bytes()) { return java_io_print_stream_println(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
    }

    if class_name == "java/io/FileInputStream".bytes() {
        if method_is(method_name, descriptor, "initIDs".bytes(), "()V".bytes()) { return JavaIoFileInputStream.initIDs(context); }
    }

    if class_name == "java/io/FileOutputStream".bytes() {
        if method_is(method_name, descriptor, "initIDs".bytes(), "()V".bytes()) { return JavaIoFileOutputStream.initIDs(context); }
    }

    if class_name == "java/io/UnixFileSystem".bytes() {
        if method_is(method_name, descriptor, "initIDs".bytes(), "()V".bytes()) { return JavaIoUnixFileSystem.initIDs(context); }
        if method_is(method_name, descriptor, "canonicalize0".bytes(), "(Ljava/lang/String;)Ljava/lang/String;".bytes()) { return JavaIoUnixFileSystem.canonicalize0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "getBooleanAttributes0".bytes(), "(Ljava/io/File;)I".bytes()) { return JavaIoUnixFileSystem.getBooleanAttributes0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "checkAccess0".bytes(), "(Ljava/io/File;I)Z".bytes()) { return JavaIoUnixFileSystem.checkAccess0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1)); }
        if method_is(method_name, descriptor, "getLastModifiedTime0".bytes(), "(Ljava/io/File;)J".bytes()) { return JavaIoUnixFileSystem.getLastModifiedTime0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "getLength0".bytes(), "(Ljava/io/File;)J".bytes()) { return JavaIoUnixFileSystem.getLength0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "setPermission0".bytes(), "(Ljava/io/File;IZZ)Z".bytes()) { return JavaIoUnixFileSystem.setPermission0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1), int_arg(&args, 2), int_arg(&args, 3)); }
        if method_is(method_name, descriptor, "createFileExclusively0".bytes(), "(Ljava/lang/String;)Z".bytes()) { return JavaIoUnixFileSystem.createFileExclusively0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "delete0".bytes(), "(Ljava/io/File;)Z".bytes()) { return JavaIoUnixFileSystem.delete0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "list0".bytes(), "(Ljava/io/File;)[Ljava/lang/String;".bytes()) { return JavaIoUnixFileSystem.list0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "createDirectory0".bytes(), "(Ljava/io/File;)Z".bytes()) { return JavaIoUnixFileSystem.createDirectory0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "rename0".bytes(), "(Ljava/io/File;Ljava/io/File;)Z".bytes()) { return JavaIoUnixFileSystem.rename0(context, try receiver_ref(receiver), ref_arg(&args, 0), ref_arg(&args, 1)); }
        if method_is(method_name, descriptor, "setLastModifiedTime0".bytes(), "(Ljava/io/File;J)Z".bytes()) { return JavaIoUnixFileSystem.setLastModifiedTime0(context, try receiver_ref(receiver), ref_arg(&args, 0), long_arg(&args, 1)); }
        if method_is(method_name, descriptor, "setReadOnly0".bytes(), "(Ljava/io/File;)Z".bytes()) { return JavaIoUnixFileSystem.setReadOnly0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method_name, descriptor, "getSpace0".bytes(), "(Ljava/io/File;I)J".bytes()) { return JavaIoUnixFileSystem.getSpace0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1)); }
        if method_is(method_name, descriptor, "getNameMax0".bytes(), "(Ljava/lang/String;)J".bytes()) { return JavaIoUnixFileSystem.getNameMax0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
    }

    if class_name == "java/util/concurrent/atomic/AtomicLong".bytes() {
        if method_is(method_name, descriptor, "VMSupportsCS8".bytes(), "()Z".bytes()) { return JavaUtilConcurrentAtomicAtomicLong.VMSupportsCS8(context); }
    }

    if class_name == "java/util/zip/ZipFile".bytes() {
        if method_is(method_name, descriptor, "initIDs".bytes(), "()V".bytes()) { return JavaUtilZipZipFile.initIDs(context); }
    }

    println("unsupported native");
    return .err(InstructionError.unsupported_native);
}

test "native Object.clone copies instance fields" {
    const native_code: [0]u8 = [];
    const field = Field {
        class_name: "Example",
        access_flags: field_access_flags(0x0001),
        name: "value",
        descriptor: "I",
        index: 0,
        slot: 0,
    };
    var classes: [1]Class = [
        Class {
            name: "Example",
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [field],
            methods: [],
            constant_pool: [],
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
    const original = heap.allocate_object(0, &classes[0]);
    assert(heap.set_field(original, 0, .int_value(42)));
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    const result = try JavaLangObject.clone(&context, original);
    if result is value {
        switch value {
        case .ref_value(clone) {
            assert(!clone.equals(original));
            if heap.get_field(clone, 0) is cloned_value {
                switch cloned_value {
                case .int_value(actual) { assert(actual == 42); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            assert(heap.set_field(original, 0, .int_value(7)));
            if heap.get_field(clone, 0) is cloned_after_original_update {
                switch cloned_after_original_update {
                case .int_value(actual) { assert(actual == 42); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
        }
        else { assert(false); }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

test "native Class metadata reads represented class" {
    const native_code: [0]u8 = [];
    const example_class_object = Reference {
        kind: ReferenceKind.object,
        slot: 0,
        generation: 1,
    };
    const object_class_object = Reference {
        kind: ReferenceKind.object,
        slot: 1,
        generation: 1,
    };
    var classes: [3]Class = [
        Class {
            name: "Example",
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Example.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: example_class_object,
        },
        Class {
            name: "java/lang/Object",
            descriptor: "Ljava/lang/Object;",
            access_flags: class_access_flags(0x0021),
            super_class: "",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Object.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: object_class_object,
        },
        Class {
            name: "java/lang/Class",
            descriptor: "Ljava/lang/Class;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
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
        },
    ];
    var heap = new_heap();
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    const modifiers = try JavaLangClass.getModifiers(&context, classes[0].class_object);
    if modifiers is modifiers_value {
        switch modifiers_value {
        case .int_value(actual) { assert(actual == 0x0021); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }

    const super_class = try JavaLangClass.getSuperclass(&context, classes[0].class_object);
    if super_class is super_value {
        switch super_value {
        case .ref_value(actual) { assert(actual.equals(classes[1].class_object)); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }

    const object_super_class = try JavaLangClass.getSuperclass(&context, classes[1].class_object);
    if object_super_class is object_super_value {
        switch object_super_value {
        case .ref_value(actual) { assert(actual.is_null()); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

test "native bootstrap helpers return conservative values" {
    const native_code: [0]u8 = [];
    const class_object = Reference {
        kind: ReferenceKind.object,
        slot: 7,
        generation: 1,
    };
    var classes: [1]Class = [
        Class {
            name: "Example",
            descriptor: "LExample;",
            access_flags: class_access_flags(0x0421),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
            instance_vars: 0,
            static_vars: [],
            source_file: "Example.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: class_object,
        },
    ];
    var heap = new_heap();
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    const runtime = Reference {
        kind: ReferenceKind.object,
        slot: 8,
        generation: 1,
    };
    const free_memory = try JavaLangRuntime.freeMemory(&context, runtime);
    if free_memory is free_value {
        switch free_value {
        case .long_value(actual) { assert(actual > 0); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }

    const access_flags_value = try SunReflectReflection.getClassAccessFlags(&context, class_object);
    if access_flags_value is flags_value {
        switch flags_value {
        case .int_value(actual) { assert(actual == 0x0421); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }

    const path = Reference {
        kind: ReferenceKind.object,
        slot: 9,
        generation: 1,
    };
    const canonicalized = try JavaIoUnixFileSystem.canonicalize0(&context, runtime, path);
    if canonicalized is canonicalized_value {
        switch canonicalized_value {
        case .ref_value(actual) { assert(actual.equals(path)); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }

    const pending = try JavaLangRefReference.hasReferencePendingList(&context);
    if pending is pending_value {
        switch pending_value {
        case .boolean_value(actual) { assert(actual == 0); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

test "native Thread.currentThread creates stable java thread object" {
    const native_code: [0]u8 = [];
    const thread_name_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "name",
        descriptor: "Ljava/lang/String;",
        index: 0,
        slot: 0,
    };
    const thread_tid_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "tid",
        descriptor: "J",
        index: 1,
        slot: 1,
    };
    const thread_group_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "group",
        descriptor: "Ljava/lang/ThreadGroup;",
        index: 2,
        slot: 2,
    };
    const thread_priority_field = Field {
        class_name: "java/lang/Thread",
        access_flags: field_access_flags(0x0001),
        name: "priority",
        descriptor: "I",
        index: 3,
        slot: 3,
    };
    const group_name_field = Field {
        class_name: "java/lang/ThreadGroup",
        access_flags: field_access_flags(0x0001),
        name: "name",
        descriptor: "Ljava/lang/String;",
        index: 0,
        slot: 0,
    };
    var classes: [3]Class = [
        Class {
            name: "java/lang/Thread",
            descriptor: "Ljava/lang/Thread;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [thread_name_field, thread_tid_field, thread_group_field, thread_priority_field],
            methods: [],
            constant_pool: [],
            instance_vars: 4,
            static_vars: [],
            source_file: "Thread.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: "java/lang/ThreadGroup",
            descriptor: "Ljava/lang/ThreadGroup;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [group_name_field],
            methods: [],
            constant_pool: [],
            instance_vars: 1,
            static_vars: [],
            source_file: "ThreadGroup.java",
            is_array: false,
            component_type: "",
            element_type: "",
            dimensions: 0,
            defined: true,
            linked: false,
            class_object: null_ref,
        },
        Class {
            name: "java/lang/String",
            descriptor: "Ljava/lang/String;",
            access_flags: class_access_flags(0x0021),
            super_class: "java/lang/Object",
            interfaces: [],
            fields: [],
            methods: [],
            constant_pool: [],
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
        },
    ];
    var heap = new_heap();
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..],
        classes: classes[..],
        heap: &heap,
    };

    const first = try JavaLangThread.currentThread(&context);
    const second = try JavaLangThread.currentThread(&context);
    if first is first_value {
        switch first_value {
        case .ref_value(first_ref) {
            if second is second_value {
                switch second_value {
                case .ref_value(second_ref) { assert(first_ref.equals(second_ref)); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            if heap.get_field(first_ref, 1) is tid {
                switch tid {
                case .long_value(actual) { assert(actual == 1); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            if heap.get_field(first_ref, 3) is priority {
                switch priority {
                case .int_value(actual) { assert(actual == 1); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            if heap.get_field(first_ref, 0) is name {
                switch name {
                case .ref_value(name_ref) { assert(name_ref.equals(heap.strings[0].reference)); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            if heap.get_field(first_ref, 2) is group {
                switch group {
                case .ref_value(group_ref) {
                    assert(group_ref.non_null());
                    if heap.get_field(group_ref, 0) is group_name {
                        switch group_name {
                        case .ref_value(group_name_ref) { assert(group_name_ref.equals(heap.strings[0].reference)); }
                        else { assert(false); }
                        }
                    } else {
                        assert(false);
                    }
                }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
        }
        else { assert(false); }
        }
    } else {
        assert(false);
    }
    drop context;
    drop classes;
    drop constant_pool;
}

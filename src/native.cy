import { Constant } from .classfile;
import { Context } from .engine;
import { execute_method_frame_with_runtime } from .engine;
import { new_frame } from .engine;
import { VM } from .vm;
import { new_vm } from .vm;
import { Class, Field, InstructionError, Method, MethodAccessFlags, Reference, ReferenceKind, Value, byte_buffer, class_access_flags, field_access_flags, java_utf16_units_from_utf8, null_ref, raw_class_access, raw_field_access, raw_method_access } from .types;
import { monotonic_ns, now_ns, ns_to_ms, sleep_ms } from std.time;
import std.thread;
import { Runtime } from .runtime;
import { enter_method_monitor, exit_method_monitor } from .method_monitor;
import { is_access_controller_do_privileged, invoke_privileged_action, initialize_java_system_properties, invoke_reflect_constructor } from .instruction;

fn ref_arg(arguments: &List<Value>, index: usize): Reference {
    return switch arguments[index] {
        .ref_value(actual) => actual;
        _ => Reference.init_null();
    };
}

fn value_ref_or_null(value: Value): Reference {
    return switch value {
        .ref_value(actual) => actual;
        .byte_value => null_ref;
        .short_value => null_ref;
        .char_value => null_ref;
        .int_value => null_ref;
        .long_value => null_ref;
        .float_value => null_ref;
        .double_value => null_ref;
        .boolean_value => null_ref;
        .return_address_value => null_ref;
    };
}

fn int_arg(arguments: &List<Value>, index: usize): i32 {
    return switch arguments[index] {
        .int_value(actual) => actual;
        .boolean_value(actual) => actual as i32;
        .byte_value(actual) => actual as i32;
        .short_value(actual) => actual as i32;
        .char_value(actual) => actual as i32;
        _ => 0;
    };
}

fn long_arg(arguments: &List<Value>, index: usize): i64 {
    return switch arguments[index] {
        .long_value(actual) => actual;
        _ => 0;
    };
}

fn float_arg(arguments: &List<Value>, index: usize): f32 {
    return switch arguments[index] {
        .float_value(actual) => actual;
        _ => 0.0;
    };
}

fn double_arg(arguments: &List<Value>, index: usize): f64 {
    return switch arguments[index] {
        .double_value(actual) => actual;
        _ => 0.0;
    };
}

fn receiver_ref(receiver: ?Reference): Reference ! InstructionError {
    if receiver is actual {
        return actual;
    }
    throw InstructionError.invalid_constant;
}

fn return_value(value: Value): ?Value {
    const result: ?Value = value;
    const _cava_optional_242: ?Value = result;
    return _cava_optional_242;
}

fn identity_hash_code(reference: Reference): i32 {
    if reference.slot is slot {
        const mixed = (slot as u64) +% ((reference.generation as u64) *% 1103515245);
        return (mixed & 2147483647) as i32;
    }
    return 0;
}

fn set_system_static_ref(context: &Context, vm: &VM, name: string, descriptor: string, reference: Reference): void ! InstructionError {
    var classes = vm.method_area.classes[..];
    var index: usize = 0;
    while index < classes.len() {
        var class = &classes[index];
        if class.name == "java/lang/System" {
            if class.field_index(name, descriptor, true) is field_index_value {
                var fields = class.fields[..];
                const field = &fields[field_index_value as usize];
                class.static_vars[field.slot] = .ref_value(reference);
                return;
            }
            throw InstructionError.invalid_constant;
        }
        index = index + 1;
    }
    throw InstructionError.invalid_constant;
}

fn find_native_class_index(context: &Context, vm: &VM, name: string): usize ! InstructionError {
    var classes = vm.method_area.classes[..];
    var index: usize = 0;
    while index < classes.len() {
        const class = &classes[index];
        if class.name == name {
            return index;
        }
        index = index + 1;
    }
    throw InstructionError.invalid_constant;
}

fn load_native_class_index(context: &Context, vm: &VM, name: string): usize ! InstructionError {
    return vm.method_area.resolve_class(name) catch (status) {
        throw InstructionError.invalid_constant;
    };
}

fn find_or_load_native_class_index(context: &Context, vm: &VM, name: string): usize ! InstructionError {
    return find_native_class_index(context, vm, name) catch (problem) {
        return try load_native_class_index(context, vm, name);
    };
}

fn find_or_load_native_class_index_optional(context: &Context, vm: &VM, name: string): ?usize {
    return find_or_load_native_class_index(context, vm, name) catch (problem) => none;
}

fn find_loaded_class_index(classes: []Class, name: string): ?usize {
    var class_view = classes;
    var index: usize = 0;
    while index < class_view.len() {
        const class = &class_view[index];
        if class.name == name {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn find_class_object_index_in(classes: []Class, class_object: Reference): ?usize {
    var class_view = classes;
    var index: usize = 0;
    while index < class_view.len() {
        const class = &class_view[index];
        if class.class_object.equals(class_object) {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn native_class_index_by_name(classes: []Class, name: string): ?usize {
    var class_view = classes;
    var index: usize = 0;
    while index < class_view.len() {
        const class = &class_view[index];
        if class.name == name {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn native_hierarchy_instance_var_count(classes: []Class, class_index: usize): u16 {
    if class_index >= classes.len() {
        return 0;
    }
    var class_view = classes;
    const class = &class_view[class_index];
    var count: u16 = 0;
    const super_name = class.super_class;
    if super_name != "" {
        if native_class_index_by_name(classes, super_name) is super_index {
            count = native_hierarchy_instance_var_count(classes, super_index);
        }
    }
    var fields = class.fields[..];
    var index: usize = 0;
    while index < fields.len() {
        const field = &fields[index];
        if !field.is_static() {
            count = count + 1;
        }
        index = index + 1;
    }
    return count;
}

fn native_field_runtime_slot(classes: []Class, object_class_index: usize, declaring_class_name: string, slot: u16): ?u16 {
    if object_class_index >= classes.len() {
        return none;
    }
    var class_view = classes;
    const class = &class_view[object_class_index];
    var super_count: u16 = 0;
    const super_name = class.super_class;
    if super_name != "" {
        if native_class_index_by_name(classes, super_name) is super_index {
            super_count = native_hierarchy_instance_var_count(classes, super_index);
            if native_field_runtime_slot(classes, super_index, declaring_class_name, slot) is inherited_slot {
                return inherited_slot;
            }
        }
    }
    if class.name == declaring_class_name {
        return super_count + slot;
    }
    return none;
}

fn native_class_named(classes: []Class, index: usize, name: string): bool {
    if index >= classes.len() {
        return false;
    }
    var class_view = classes;
    const class = &class_view[index];
    return class.name == name;
}

fn native_reference_assignable_to(classes: []Class, actual_index: usize, expected_index: usize): bool {
    if actual_index >= classes.len() or expected_index >= classes.len() {
        return false;
    }
    if actual_index == expected_index {
        return true;
    }

    var class_view = classes;
    const actual_class = &class_view[actual_index];
    const expected_class = &class_view[expected_index];

    if expected_class.is_interface() {
        var interfaces = actual_class.interfaces[..];
        var interface_index: usize = 0;
        while interface_index < interfaces.len() {
            const interface_name = interfaces[interface_index];
            if find_loaded_class_index(class_view, interface_name) is actual_interface_index {
                if native_reference_assignable_to(classes, actual_interface_index, expected_index) {
                    return true;
                }
            } else if interface_name == expected_class.name {
                return true;
            }
            interface_index = interface_index + 1;
        }
        if find_loaded_class_index(class_view, actual_class.super_class) is super_index {
            return native_reference_assignable_to(classes, super_index, expected_index);
        }
        return false;
    }

    if actual_class.is_array {
        if native_class_named(classes, expected_index, "java/lang/Object") {
            return true;
        }
        if expected_class.is_array {
            return actual_class.component_type == expected_class.component_type;
        }
        return false;
    }

    if find_loaded_class_index(class_view, actual_class.super_class) is super_index {
        return native_reference_assignable_to(classes, super_index, expected_index);
    }
    return false;
}

fn set_instance_field(context: &Context, vm: &VM, reference: Reference, class_index: usize, name: string, descriptor: string, value: Value): void ! InstructionError {
    var classes = vm.method_area.classes[..];
    return set_instance_field_in(context, vm, classes, reference, class_index, name, descriptor, value);
}

fn set_instance_field_in(context: &Context, vm: &VM, classes: []Class, reference: Reference, class_index: usize, name: string, descriptor: string, value: Value): void ! InstructionError {
    var class_view = classes;
    const class = &class_view[class_index];
    if class.field_index(name, descriptor, false) is field_index {
        var fields = class.fields[..];
        const field = &fields[field_index as usize];
        var slot = field.slot;
        if vm.heap.object_class_index(reference) is object_class_index {
            if native_field_runtime_slot(class_view, object_class_index, field.class_name, field.slot) is runtime_slot {
                slot = runtime_slot;
            }
        }
        if !vm.heap.set_field(reference, slot, value) {
            throw InstructionError.invalid_constant;
        }
    }
    return;
}

fn get_instance_field(context: &Context, vm: &VM, reference: Reference, class_index: usize, name: string, descriptor: string): Value ! InstructionError {
    var classes = vm.method_area.classes[..];
    return get_instance_field_in(context, vm, classes, reference, class_index, name, descriptor);
}

fn get_instance_field_in(context: &Context, vm: &VM, classes: []Class, reference: Reference, class_index: usize, name: string, descriptor: string): Value ! InstructionError {
    var class_view = classes;
    const class = &class_view[class_index];
    if class.field_index(name, descriptor, false) is field_index {
        var fields = class.fields[..];
        const field = &fields[field_index as usize];
        var slot = field.slot;
        if vm.heap.object_class_index(reference) is object_class_index {
            if native_field_runtime_slot(class_view, object_class_index, field.class_name, field.slot) is runtime_slot {
                slot = runtime_slot;
            }
        }
        if vm.heap.get_field(reference, slot) is value {
            return value;
        }
    }
    throw InstructionError.invalid_constant;
}

struct NativeResolvedMethod {
    pub class_index: usize;
    pub method_index: usize;
}

struct JavaThreadStartPayload {
    vm: Runtime;
    receiver: Reference;
}

fn find_native_instance_method(vm: &VM, class_index: usize, name: string, descriptor: string): NativeResolvedMethod ! InstructionError {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        if class.method_index(name, descriptor, false) is method_index {
            return NativeResolvedMethod {
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

fn java_thread_start_worker_with_vm(vm: &VM, payload: JavaThreadStartPayload): void {
    const receiver = payload.receiver;
    const ignored_register = vm.heap.register_current_java_thread(receiver, thread.current_id(), true, true);

    var receiver_class_index: usize = 0;
    if vm.heap.object_class_index(receiver) is actual {
        receiver_class_index = actual;
    } else {
        const ignored_finish_missing_class = vm.heap.mark_java_thread_finished(receiver);
        return;
    }
    var classes = vm.method_area.classes[..];
    if classes[receiver_class_index].name == "java/lang/ref/Reference$ReferenceHandler" {
        const ignored_finish_reference_handler = vm.heap.mark_java_thread_finished(receiver);
        return;
    }

    const target = find_native_instance_method(vm, receiver_class_index, "run", "()V") catch (problem) {
        const ignored_problem = problem;
        const ignored_finish_missing_run = vm.heap.mark_java_thread_finished(receiver);
        return;
    };

    const target_class = &classes[target.class_index];
    var target_methods = target_class.methods[..];
    const target_method = &target_methods[target.method_index];
    var frame = new_frame(target.class_index, target.method_index, target_method.max_locals, target_method.max_stack);
    frame.store(0, .ref_value(receiver));
    const frame_result = execute_method_frame_with_runtime(payload.vm.alias_handles(), vm, target.class_index, target.method_index, frame, target_class.constant_pool[..]) catch (problem) {
        const ignored_problem = problem;
        const ignored_finish = vm.heap.mark_java_thread_finished(receiver);
        return;
    };
    switch frame_result {
        .return_value => {}
        .exception => {}
    }
    const ignored_finish = vm.heap.mark_java_thread_finished(receiver);
}

fn java_thread_start_worker(payload: JavaThreadStartPayload): void {
    const ignored_status = payload.vm.state.with<JavaThreadStartPayload>(payload, java_thread_start_worker_with_vm);
}

fn java_string(context: &Context, vm: &VM, value: []const u8): ?Reference {
    var classes = vm.method_area.classes[..];
    if find_loaded_class_index(classes, "java/lang/String") is string_class_index {
        const string_class = &classes[string_class_index];
        if vm.heap.interned_string_reference(value) is existing {
            return existing;
        }
        const reference = vm.heap.allocate_object_with_hierarchy(string_class_index, classes);
        if string_class.field_index("value", "[C", false) is value_field_index {
            const chars = java_utf16_units_from_utf8(value);
            const chars_reference = vm.heap.allocate_array(0, "C".bytes(), chars.len());
            var char_index: usize = 0;
            while char_index < chars.len() {
                const ignored_element = vm.heap.set_element(chars_reference, char_index, .char_value(chars[char_index]));
                char_index = char_index + 1;
            }
            drop chars;
            var fields = string_class.fields[..];
            const field = &fields[value_field_index as usize];
            const slot = field.slot;
            const ignored_field = vm.heap.set_field(reference, slot, .ref_value(chars_reference));
        }
        if string_class.field_index("coder", "B", false) is coder_field_index {
            var fields = string_class.fields[..];
            const field = &fields[coder_field_index as usize];
            const slot = field.slot;
            const ignored_coder = vm.heap.set_field(reference, slot, .byte_value(0));
        }
        vm.heap.register_string_bytes(reference, value);
        return reference;
    }
    return none;
}

fn java_string_bytes(context: &Context, vm: &VM, reference: Reference): [:]u8 ! InstructionError {
    var value_option = vm.heap.string_bytes(reference);
    if take value_option is value {
        const bytes = value.value.clone();
        drop value;
        return bytes;
    }
    const string_class_index = try find_native_class_index(context, vm, "java/lang/String");
    const value_field = try get_instance_field(context, vm, reference, string_class_index, "value", "[C");
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
                            _ => {
                                drop bytes;
                                throw InstructionError.invalid_constant;
                            }
                        }
                    } else {
                        drop bytes;
                        throw InstructionError.invalid_constant;
                    }
                    index = index + 1;
                }
                const out = byte_buffer(bytes[..]);
                drop bytes;
                return out;
            }
        }
        _ => throw InstructionError.invalid_constant;
    }
    throw InstructionError.invalid_constant;
}

fn is_primitive_class_object(context: &Context, vm: &VM, reference: Reference): bool {
    var classes = vm.method_area.classes[..];
    var class_index: usize = 0;
    while class_index < classes.len() {
        const class = &classes[class_index];
        if class.field_index("TYPE", "Ljava/lang/Class;", true) is field_index {
            var fields = class.fields[..];
            const field = &fields[field_index as usize];
            const slot = field.slot as usize;
            if slot < class.static_vars.len() {
                switch class.static_vars[slot] {
                    .ref_value(type_reference) => {
                        if type_reference.equals(reference) {
                            return true;
                        }
                    }
                    .byte_value => {}
                    .short_value => {}
                    .char_value => {}
                    .int_value => {}
                    .long_value => {}
                    .float_value => {}
                    .double_value => {}
                    .boolean_value => {}
                    .return_address_value => {}
                }
            }
        }
        class_index = class_index + 1;
    }
    return false;
}

fn ensure_class_object(context: &Context, vm: &VM, class_index: usize): Reference ! InstructionError {
    const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
    var classes = vm.method_area.classes[..];
    const class_class = &classes[class_class_index];
    var class = &classes[class_index];
    if class.class_object.is_null() {
        class.class_object = vm.heap.allocate_object(class_class_index, class_class);
    }
    return class.class_object;
}

fn descriptor_class_object(context: &Context, vm: &VM, descriptor: []const u8): Reference ! InstructionError {
    if descriptor.len() == 1 {
        const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
        var classes = vm.method_area.classes[..];
        return vm.heap.allocate_object(class_class_index, &classes[class_class_index]);
    }
    const descriptor_text = string.from(descriptor);
    var classes = vm.method_area.classes[..];
    var index: usize = 0;
    while index < classes.len() {
        const class = &classes[index];
        if class.descriptor == descriptor_text or class.name == descriptor_text {
            drop descriptor_text;
            return ensure_class_object(context, vm, index);
        }
        index = index + 1;
    }
    drop descriptor_text;
    if descriptor.len() > 2 and descriptor[0] == 'L' {
        const name = string.from(descriptor[1..descriptor.len() - 1]);
        const found = find_or_load_native_class_index(context, vm, name) catch (problem) {
            drop name;
            throw InstructionError.invalid_constant;
        };
        drop name;
        return try ensure_class_object(context, vm, found);
    }
    throw InstructionError.invalid_constant;
}

fn new_java_reflect_field(context: &Context, vm: &VM, declaring_class: Reference, field: &Field): Reference ! InstructionError {
    const field_class_index = try find_or_load_native_class_index(context, vm, "java/lang/reflect/Field");
    var classes = vm.method_area.classes[..];
    const reference = vm.heap.allocate_object_with_hierarchy(field_class_index, classes);
    const type_reference = try descriptor_class_object(context, vm, field.descriptor.bytes());
    var name_reference = null_ref;
    if java_string(context, vm, field.name.bytes()) is actual_name {
        name_reference = actual_name;
    } else {
        throw InstructionError.invalid_constant;
    }
    var signature_reference = null_ref;
    if java_string(context, vm, field.descriptor.bytes()) is actual_signature {
        signature_reference = actual_signature;
    } else {
        throw InstructionError.invalid_constant;
    }
    var annotations_class_index: usize = 0;
    if find_loaded_class_index(classes, "[B") is actual_annotations_class_index {
        annotations_class_index = actual_annotations_class_index;
    }
    const annotations = vm.heap.allocate_array(annotations_class_index, "B".bytes(), 0);
    classes = vm.method_area.classes[..];
    try set_instance_field_in(context, vm, classes, reference, field_class_index, "clazz", "Ljava/lang/Class;", .ref_value(declaring_class));
    try set_instance_field_in(context, vm, classes, reference, field_class_index, "name", "Ljava/lang/String;", .ref_value(name_reference));
    try set_instance_field_in(context, vm, classes, reference, field_class_index, "type", "Ljava/lang/Class;", .ref_value(type_reference));
    try set_instance_field_in(context, vm, classes, reference, field_class_index, "modifiers", "I", .int_value(raw_field_access(field.access_flags) as i32));
    try set_instance_field_in(context, vm, classes, reference, field_class_index, "slot", "I", .int_value(field.slot as i32));
    try set_instance_field_in(context, vm, classes, reference, field_class_index, "signature", "Ljava/lang/String;", .ref_value(signature_reference));
    try set_instance_field_in(context, vm, classes, reference, field_class_index, "annotations", "[B", .ref_value(annotations));
    return reference;
}

fn descriptor_end(descriptor: []const u8, start: usize): usize {
    var index = start;
    while index < descriptor.len() and descriptor[index] == '[' {
        index = index + 1;
    }
    if index >= descriptor.len() {
        return descriptor.len();
    }
    if descriptor[index] == 'L' {
        while index < descriptor.len() and descriptor[index] != ';' {
            index = index + 1;
        }
        if index < descriptor.len() {
            return index + 1;
        }
        return descriptor.len();
    }
    return index + 1;
}

fn new_class_array_for_method_parameters(context: &Context, vm: &VM, method: &Method): Reference ! InstructionError {
    const class_array_index = try find_or_load_native_class_index(context, vm, "[Ljava/lang/Class;");
    const array = vm.heap.allocate_array(class_array_index, "Ljava/lang/Class;".bytes(), method.parameter_count as usize);
    const descriptor = method.descriptor.bytes();
    var descriptor_index: usize = 1;
    var parameter_index: usize = 0;
    while descriptor_index < descriptor.len() and descriptor[descriptor_index] != ')' and parameter_index < method.parameter_count as usize {
        const end = descriptor_end(descriptor, descriptor_index);
        const class_reference = try descriptor_class_object(context, vm, descriptor[descriptor_index..end]);
        const ignored_set = vm.heap.set_element(array, parameter_index, .ref_value(class_reference));
        descriptor_index = end;
        parameter_index = parameter_index + 1;
    }
    return array;
}

fn new_java_reflect_constructor(context: &Context, vm: &VM, declaring_class: Reference, method: &Method, slot: usize): Reference ! InstructionError {
    const constructor_class_index = try find_or_load_native_class_index(context, vm, "java/lang/reflect/Constructor");
    var classes = vm.method_area.classes[..];
    const reference = vm.heap.allocate_object_with_hierarchy(constructor_class_index, classes);
    const parameter_types = try new_class_array_for_method_parameters(context, vm, method);
    const exception_types_index = try find_or_load_native_class_index(context, vm, "[Ljava/lang/Class;");
    const exception_types = vm.heap.allocate_array(exception_types_index, "Ljava/lang/Class;".bytes(), 0);
    const annotations_class_index = try find_or_load_native_class_index(context, vm, "[B");
    const annotations = vm.heap.allocate_array(annotations_class_index, "B".bytes(), 0);
    const parameter_annotations = vm.heap.allocate_array(annotations_class_index, "B".bytes(), 0);
    if java_string(context, vm, method.descriptor.bytes()) is signature {
        classes = vm.method_area.classes[..];
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "clazz", "Ljava/lang/Class;", .ref_value(declaring_class));
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "parameterTypes", "[Ljava/lang/Class;", .ref_value(parameter_types));
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "exceptionTypes", "[Ljava/lang/Class;", .ref_value(exception_types));
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "modifiers", "I", .int_value(raw_method_access(method.access_flags) as i32));
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "slot", "I", .int_value(slot as i32));
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "signature", "Ljava/lang/String;", .ref_value(signature));
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "annotations", "[B", .ref_value(annotations));
        try set_instance_field_in(context, vm, classes, reference, constructor_class_index, "parameterAnnotations", "[B", .ref_value(parameter_annotations));
        return reference;
    }
    throw InstructionError.invalid_constant;
}

fn array_descriptor_for_component(class: &Class): string {
    if class.is_array {
        return $"[{class.name}";
    }
    return $"[L{class.name};";
}

fn class_name_from_java_name(name: []const u8): string {
    var bytes: List<u8> = [];
    var index: usize = 0;
    while index < name.len() {
        if name[index] == 46 {
            bytes.push(47);
        } else {
            bytes.push(name[index]);
        }
        index = index + 1;
    }
    const out = string.from(bytes[..]);
    drop bytes;
    return out;
}

fn java_string_buffer(context: &Context, vm: &VM, data: [:]u8): Reference ! InstructionError {
    var bytes = data;
    var classes = vm.method_area.classes[..];
    if find_loaded_class_index(classes, "java/lang/String") is string_class_index {
        return vm.heap.intern_string_buffer(string_class_index, &classes[string_class_index], bytes);
    }
    drop bytes;
    throw InstructionError.invalid_constant;
}

fn concat_java_string(context: &Context, vm: &VM, left_reference: Reference, right_reference: Reference): Reference ! InstructionError {
    var classes = vm.method_area.classes[..];
    if find_loaded_class_index(classes, "java/lang/String") is string_class_index {
        return vm.heap.concat_strings(string_class_index, &classes[string_class_index], left_reference, right_reference);
    }
    throw InstructionError.invalid_constant;
}

fn print_java_string(context: &Context, vm: &VM, reference: Reference): void {
    var value_option = vm.heap.string_bytes(reference);
    if take value_option is value {
        const bytes = value.value.clone();
        const text = string.from(bytes[..]);
        println(text);
        drop text;
        drop bytes;
        drop value;
        return;
    }
    println("");
}

fn new_thread_group(context: &Context, vm: &VM): Reference ! InstructionError {
    const group_class_index = find_or_load_native_class_index(context, vm, "java/lang/ThreadGroup") catch (problem) {
        return null_ref;
    };
    var classes = vm.method_area.classes[..];
    const group = vm.heap.allocate_object(group_class_index, &classes[group_class_index]);
    if java_string(context, vm, "main".bytes()) is group_name {
        try set_instance_field_in(context, vm, classes, group, group_class_index, "name", "Ljava/lang/String;", .ref_value(group_name));
    }
    return group;
}

fn new_java_lang_thread(context: &Context, vm: &VM): Reference ! InstructionError {
    if vm.heap.current_thread_ref() is cached {
        if vm.heap.has_object(cached) {
            return cached;
        }
    }
    const thread_class_index = find_or_load_native_class_index(context, vm, "java/lang/Thread") catch (problem) {
        throw InstructionError.invalid_constant;
    };
    var classes = vm.method_area.classes[..];
    const thread = vm.heap.allocate_object(thread_class_index, &classes[thread_class_index]);
    if java_string(context, vm, "main".bytes()) is name {
        try set_instance_field_in(context, vm, classes, thread, thread_class_index, "name", "Ljava/lang/String;", .ref_value(name));
    }
    try set_instance_field_in(context, vm, classes, thread, thread_class_index, "tid", "J", .long_value(1));
    try set_instance_field_in(context, vm, classes, thread, thread_class_index, "priority", "I", .int_value(1));
    const group = try new_thread_group(context, vm);
    if group.non_null() {
        classes = vm.method_area.classes[..];
        try set_instance_field_in(context, vm, classes, thread, thread_class_index, "group", "Ljava/lang/ThreadGroup;", .ref_value(group));
    }
    vm.heap.set_current_thread(thread);
    return thread;
}

fn arraycopy(context: &Context, vm: &VM, src: Reference, src_pos: i32, dest: Reference, dest_pos: i32, length: i32): void ! InstructionError {
    if src_pos < 0 or dest_pos < 0 or length < 0 {
        throw InstructionError.invalid_constant;
    }
    const src_start = src_pos as usize;
    const dest_start = dest_pos as usize;
    const count = length as usize;
    var src_len: usize = 0;
    if vm.heap.array_length(src) is actual_src_len {
        src_len = actual_src_len;
    } else {
        throw InstructionError.invalid_constant;
    }
    var dest_len: usize = 0;
    if vm.heap.array_length(dest) is actual_dest_len {
        dest_len = actual_dest_len;
    } else {
        throw InstructionError.invalid_constant;
    }
    if src_start + count > src_len or dest_start + count > dest_len {
        throw InstructionError.invalid_constant;
    }

    if src.equals(dest) and dest_start > src_start {
        var index = count;
        while index > 0 {
            index = index - 1;
            var value: Value = .int_value(0);
            if vm.heap.get_element(src, src_start + index) is actual_value {
                value = actual_value;
            } else {
                throw InstructionError.invalid_constant;
            }
            if !vm.heap.set_element(dest, dest_start + index, value) {
                throw InstructionError.invalid_constant;
            }
        }
        return;
    }

    var index: usize = 0;
    while index < count {
        var value: Value = .int_value(0);
        if vm.heap.get_element(src, src_start + index) is actual_value {
            value = actual_value;
        } else {
            throw InstructionError.invalid_constant;
        }
        if !vm.heap.set_element(dest, dest_start + index, value) {
            throw InstructionError.invalid_constant;
        }
        index = index + 1;
    }
    return;
}

fn clone_array(context: &Context, vm: &VM, receiver: Reference, class_index: usize): Reference ! InstructionError {
    var length: usize = 0;
    if vm.heap.array_length(receiver) is actual_length {
        length = actual_length;
    } else {
        throw InstructionError.invalid_constant;
    }

    var classes = vm.method_area.classes[..];
    const class = &classes[class_index];
    const component_type = class.component_type;
    const clone = vm.heap.allocate_array(class_index, component_type.bytes(), length);
    var index: usize = 0;
    while index < length {
        var value: Value = .int_value(0);
        if vm.heap.get_element(receiver, index) is actual_value {
            value = actual_value;
        } else {
            throw InstructionError.invalid_constant;
        }
        if !vm.heap.set_element(clone, index, value) {
            throw InstructionError.invalid_constant;
        }
        index = index + 1;
    }
    return clone;
}

fn clone_object(context: &Context, vm: &VM, receiver: Reference, class_index: usize): Reference ! InstructionError {
    var classes = vm.method_area.classes[..];
    const class = &classes[class_index];
    const clone = vm.heap.allocate_object(class_index, class);
    var slot: u16 = 0;
    while slot < class.instance_vars {
        var value: Value = .int_value(0);
        if vm.heap.get_field(receiver, slot) is actual_value {
            value = actual_value;
        } else {
            throw InstructionError.invalid_constant;
        }
        if !vm.heap.set_field(clone, slot, value) {
            throw InstructionError.invalid_constant;
        }
        slot = slot + 1;
    }
    return clone;
}

struct JavaLangSystem {
    pub fn registerNatives(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn setIn0(context: &Context, vm: &VM, input: Reference): ?Value ! InstructionError {
        try set_system_static_ref(context, vm, "in", "Ljava/io/InputStream;", input);
        return none;
    }

    pub fn setOut0(context: &Context, vm: &VM, output: Reference): ?Value ! InstructionError {
        try set_system_static_ref(context, vm, "out", "Ljava/io/PrintStream;", output);
        return none;
    }

    pub fn setErr0(context: &Context, vm: &VM, error_stream: Reference): ?Value ! InstructionError {
        try set_system_static_ref(context, vm, "err", "Ljava/io/PrintStream;", error_stream);
        return none;
    }

    pub fn arraycopy(context: &Context, vm: &VM, src: Reference, src_pos: i32, dest: Reference, dest_pos: i32, length: i32): ?Value ! InstructionError {
        try arraycopy(context, vm, src, src_pos, dest, dest_pos, length);
        return none;
    }

    pub fn identityHashCode(context: &Context, reference: Reference): ?Value ! InstructionError {
        const _cava_optional_241: ?Value = return_value(.int_value(identity_hash_code(reference)));
        return _cava_optional_241;
    }

    pub fn currentTimeMillis(context: &Context): ?Value ! InstructionError {
        const ns = now_ns() catch (problem) {
            throw InstructionError.invalid_constant;
        };
        const _cava_optional_240: ?Value = return_value(.long_value(ns_to_ms(ns)));
        return _cava_optional_240;
    }

    pub fn nanoTime(context: &Context): ?Value ! InstructionError {
        const ns = monotonic_ns() catch (problem) {
            throw InstructionError.invalid_constant;
        };
        const _cava_optional_239: ?Value = return_value(.long_value(ns));
        return _cava_optional_239;
    }

    pub fn mapLibraryName(context: &Context, name: Reference): ?Value ! InstructionError {
        const _cava_optional_238: ?Value = return_value(.ref_value(name));
        return _cava_optional_238;
    }

    pub fn initProperties(context: &Context, properties: Reference): ?Value ! InstructionError {
        const _cava_optional_237: ?Value = return_value(.ref_value(properties));
        return _cava_optional_237;
    }

    pub fn getProperty(context: &Context, vm: &VM, key: Reference): ?Value ! InstructionError {
        const ignored_key = key;
        if java_string(context, vm, "Cava".bytes()) is value {
            const _cava_optional_236: ?Value = return_value(.ref_value(value));
            return _cava_optional_236;
        }
        throw InstructionError.invalid_constant;
    }
}

struct JavaLangObject {
    pub fn registerNatives(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn init(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        return none;
    }

    pub fn hashCode(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const _cava_optional_235: ?Value = return_value(.int_value(identity_hash_code(receiver)));
        return _cava_optional_235;
    }

    pub fn getClass(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if vm.heap.object_class_index(receiver) is actual_class_index {
            const ignored_class = &classes[actual_class_index];
            const _cava_optional_234: ?Value = return_value(.ref_value(try ensure_class_object(context, vm, actual_class_index)));
            return _cava_optional_234;
        }
        if vm.heap.array_class_index(receiver) is actual_class_index {
            const ignored_class = &classes[actual_class_index];
            const _cava_optional_233: ?Value = return_value(.ref_value(try ensure_class_object(context, vm, actual_class_index)));
            return _cava_optional_233;
        }
        throw InstructionError.invalid_constant;
    }

    pub fn clone(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        if vm.heap.object_class_index(receiver) is actual_class_index {
            const _cava_optional_232: ?Value = return_value(.ref_value(try clone_object(context, vm, receiver, actual_class_index)));
            return _cava_optional_232;
        }
        if vm.heap.array_class_index(receiver) is actual_class_index {
            const _cava_optional_231: ?Value = return_value(.ref_value(try clone_array(context, vm, receiver, actual_class_index)));
            return _cava_optional_231;
        }
        throw InstructionError.invalid_constant;
    }

    pub fn notify(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        return none;
    }

    pub fn notifyAll(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        return none;
    }

    pub fn wait(context: &Context, receiver: Reference, millis: i64): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_millis = millis;
        return none;
    }
}

struct JavaLangClass {
    pub fn registerNatives(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn getPrimitiveClass(context: &Context, vm: &VM, name: Reference): ?Value ! InstructionError {
        const ignored_name = name;
        const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
        var classes = vm.method_area.classes[..];
        const reference = vm.heap.allocate_object(class_class_index, &classes[class_class_index]);
        const _cava_optional_230: ?Value = return_value(.ref_value(reference));
        return _cava_optional_230;
    }

    pub fn desiredAssertionStatus0(context: &Context, class_object: Reference): ?Value ! InstructionError {
        const ignored_class_object = class_object;
        const _cava_optional_229: ?Value = return_value(.boolean_value(0));
        return _cava_optional_229;
    }

    pub fn getDeclaredFields0(context: &Context, vm: &VM, receiver: Reference, public_only: i32): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is declaring_class_index {
            const declaring_class = &classes[declaring_class_index];
            var fields = declaring_class.fields[..];
            const field_array_class_index = find_or_load_native_class_index(context, vm, "[Ljava/lang/reflect/Field;") catch (problem) {
                println("cava native error: missing [Ljava/lang/reflect/Field; array class");
                throw InstructionError.invalid_constant;
            };
            var count: usize = 0;
            var field_index: usize = 0;
            while field_index < fields.len() {
                const field = &fields[field_index];
                if public_only == 0 or field.is_public() {
                    count = count + 1;
                }
                field_index = field_index + 1;
            }
            const array = vm.heap.allocate_array(field_array_class_index, "Ljava/lang/reflect/Field;".bytes(), count);
            var out_index: usize = 0;
            field_index = 0;
            while field_index < fields.len() {
                const field = &fields[field_index];
                if public_only == 0 or field.is_public() {
                    const actual_field_object = new_java_reflect_field(context, vm, receiver, field) catch (problem) {
                        print("cava native error: cannot create java/lang/reflect/Field for ");
                        print(declaring_class.name);
                        print(".");
                        println(field.name);
                        throw InstructionError.invalid_constant;
                    };
                    const ignored_set = vm.heap.set_element(array, out_index, .ref_value(actual_field_object));
                    out_index = out_index + 1;
                }
                field_index = field_index + 1;
            }
            const _cava_optional_228: ?Value = return_value(.ref_value(array));
            return _cava_optional_228;
        }
        println("cava native error: Class.getDeclaredFields0 receiver has no class mapping");
        throw InstructionError.invalid_constant;
    }

    pub fn getDeclaredConstructors0(context: &Context, vm: &VM, receiver: Reference, public_only: i32): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is declaring_class_index {
            const declaring_class = &classes[declaring_class_index];
            var methods = declaring_class.methods[..];
            const constructor_array_class_index = find_or_load_native_class_index(context, vm, "[Ljava/lang/reflect/Constructor;") catch (problem) {
                println("cava native error: missing [Ljava/lang/reflect/Constructor; array class");
                throw InstructionError.invalid_constant;
            };
            var count: usize = 0;
            var method_index: usize = 0;
            while method_index < methods.len() {
                const method = &methods[method_index];
                if method.name == "<init>" and (public_only == 0 or MethodAccessFlags.public in method.access_flags) {
                    count = count + 1;
                }
                method_index = method_index + 1;
            }
            const array = vm.heap.allocate_array(constructor_array_class_index, "Ljava/lang/reflect/Constructor;".bytes(), count);
            var out_index: usize = 0;
            method_index = 0;
            while method_index < methods.len() {
                const method = &methods[method_index];
                if method.name == "<init>" and (public_only == 0 or MethodAccessFlags.public in method.access_flags) {
                    const actual_constructor = new_java_reflect_constructor(context, vm, receiver, method, method_index) catch (problem) {
                        print("cava native error: cannot create java/lang/reflect/Constructor for ");
                        println(declaring_class.name);
                        throw InstructionError.invalid_constant;
                    };
                    const ignored_set = vm.heap.set_element(array, out_index, .ref_value(actual_constructor));
                    out_index = out_index + 1;
                }
                method_index = method_index + 1;
            }
            const _cava_optional_227: ?Value = return_value(.ref_value(array));
            return _cava_optional_227;
        }
        println("cava native error: Class.getDeclaredConstructors0 receiver has no class mapping");
        throw InstructionError.invalid_constant;
    }

    pub fn isPrimitive(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        if is_primitive_class_object(context, vm, receiver) {
            const _cava_optional_226: ?Value = return_value(.boolean_value(1));
            return _cava_optional_226;
        }
        const _cava_optional_225: ?Value = return_value(.boolean_value(0));
        return _cava_optional_225;
    }

    pub fn isAssignableFrom(context: &Context, vm: &VM, receiver: Reference, other: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is expected_index {
            if find_class_object_index_in(classes, other) is actual_index {
                if native_reference_assignable_to(classes, actual_index, expected_index) {
                    const _cava_optional_224: ?Value = return_value(.boolean_value(1));
                    return _cava_optional_224;
                }
                const _cava_optional_223: ?Value = return_value(.boolean_value(0));
                return _cava_optional_223;
            }
        }
        throw InstructionError.invalid_constant;
    }

    pub fn getName0(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if java_string(context, vm, class.name.bytes()) is value {
                const _cava_optional_222: ?Value = return_value(.ref_value(value));
                return _cava_optional_222;
            }
        }
        throw InstructionError.invalid_constant;
    }

    pub fn forName0(context: &Context, vm: &VM, name: Reference, initialize: i32, loader: Reference, caller: Reference): ?Value ! InstructionError {
        const ignored_initialize = initialize;
        const ignored_loader = loader;
        const ignored_caller = caller;
        const name_bytes = try java_string_bytes(context, vm, name);
        const class_name = class_name_from_java_name(name_bytes[..]);
        drop name_bytes;
        const class_index = find_or_load_native_class_index(context, vm, class_name) catch (problem) {
            print("cava native error: Class.forName0 missing class ");
            println(class_name);
            drop class_name;
            throw InstructionError.invalid_constant;
        };
        const reference = try ensure_class_object(context, vm, class_index);
        drop class_name;
        const _cava_optional_221: ?Value = return_value(.ref_value(reference));
        return _cava_optional_221;
    }

    pub fn initClassName(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        const _cava_optional_220: ?Value = try JavaLangClass.getName0(context, vm, receiver);
        return _cava_optional_220;
    }

    pub fn descriptorString(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if java_string(context, vm, class.descriptor.bytes()) is value {
                const _cava_optional_219: ?Value = return_value(.ref_value(value));
                return _cava_optional_219;
            }
        }
        throw InstructionError.invalid_constant;
    }

    pub fn isArray(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if class.is_array {
                const _cava_optional_218: ?Value = return_value(.boolean_value(1));
                return _cava_optional_218;
            }
            const _cava_optional_217: ?Value = return_value(.boolean_value(0));
            return _cava_optional_217;
        }
        const _cava_optional_216: ?Value = return_value(.boolean_value(0));
        return _cava_optional_216;
    }

    pub fn getComponentType(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if !class.is_array {
                const _cava_optional_215: ?Value = return_value(.ref_value(null_ref));
                return _cava_optional_215;
            }
            const component = class.component_type.bytes();
            if component.len() > 2 and component[0] == 'L' {
                const name = string.from(component[1..component.len() - 1]);
                if find_or_load_native_class_index_optional(context, vm, name) is component_index {
                    const reference = try ensure_class_object(context, vm, component_index);
                    drop name;
                    const _cava_optional_214: ?Value = return_value(.ref_value(reference));
                    return _cava_optional_214;
                }
                drop name;
            }
            if component.len() > 0 and component[0] == '[' {
                const name = string.from(component);
                if find_or_load_native_class_index_optional(context, vm, name) is component_index {
                    const reference = try ensure_class_object(context, vm, component_index);
                    drop name;
                    const _cava_optional_213: ?Value = return_value(.ref_value(reference));
                    return _cava_optional_213;
                }
                drop name;
            }
            const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
            var class_class = &classes[class_class_index];
            if class_class.class_object.is_null() {
                class_class.class_object = vm.heap.allocate_object(class_class_index, class_class);
            }
            const _cava_optional_212: ?Value = return_value(.ref_value(class_class.class_object));
            return _cava_optional_212;
        }
        throw InstructionError.invalid_constant;
    }

    pub fn isInterface(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if class.is_interface() {
                const _cava_optional_211: ?Value = return_value(.boolean_value(1));
                return _cava_optional_211;
            }
            const _cava_optional_210: ?Value = return_value(.boolean_value(0));
            return _cava_optional_210;
        }
        throw InstructionError.invalid_constant;
    }

    pub fn getModifiers(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            const _cava_optional_209: ?Value = return_value(.int_value(raw_class_access(class.access_flags) as i32));
            return _cava_optional_209;
        }
        throw InstructionError.invalid_constant;
    }

    pub fn getSuperclass(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            const super_class = class.super_class;
            if super_class == "" {
                const _cava_optional_208: ?Value = return_value(.ref_value(null_ref));
                return _cava_optional_208;
            }
            if find_loaded_class_index(classes, super_class) is super_index {
                const _cava_optional_207: ?Value = return_value(.ref_value(try ensure_class_object(context, vm, super_index)));
                return _cava_optional_207;
            }
            const _cava_optional_206: ?Value = return_value(.ref_value(null_ref));
            return _cava_optional_206;
        }
        throw InstructionError.invalid_constant;
    }

    pub fn getClassAccessFlagsRaw0(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        const _cava_optional_205: ?Value = try JavaLangClass.getModifiers(context, vm, receiver);
        return _cava_optional_205;
    }

    pub fn getClassFileVersion0(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_204: ?Value = return_value(.int_value(52));
        return _cava_optional_204;
    }

    pub fn isHidden(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_203: ?Value = return_value(.boolean_value(0));
        return _cava_optional_203;
    }

    pub fn isRecord0(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_202: ?Value = return_value(.boolean_value(0));
        return _cava_optional_202;
    }
}

struct JavaLangClassLoader {
    pub fn registerNatives(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn findBuiltinLib(context: &Context, name: Reference): ?Value ! InstructionError {
        const ignored_name = name;
        const _cava_optional_201: ?Value = return_value(.ref_value(null_ref));
        return _cava_optional_201;
    }
}

struct JavaLangClassLoaderNativeLibrary {
    pub fn load(context: &Context, receiver: Reference, name: Reference, is_builtin: i32): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_name = name;
        const ignored_is_builtin = is_builtin;
        return none;
    }
}

struct JavaLangReflectArray {
    pub fn newArray(context: &Context, vm: &VM, component_class: Reference, length: i32): ?Value ! InstructionError {
        if length < 0 {
            throw InstructionError.invalid_constant;
        }
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, component_class) is component_index {
            const component = &classes[component_index];
            const descriptor = array_descriptor_for_component(component);
            const array_class_index = find_or_load_native_class_index(context, vm, descriptor) catch (problem) {
                drop descriptor;
                throw InstructionError.invalid_constant;
            };
            const reference = vm.heap.allocate_array(array_class_index, component.descriptor.bytes(), length as usize);
            drop descriptor;
            const _cava_optional_200: ?Value = return_value(.ref_value(reference));
            return _cava_optional_200;
        }
        throw InstructionError.invalid_constant;
    }
}

struct JavaLangPackage {
    pub fn getSystemPackage0(context: &Context, name: Reference): ?Value ! InstructionError {
        const ignored_name = name;
        const _cava_optional_199: ?Value = return_value(.ref_value(null_ref));
        return _cava_optional_199;
    }
}

struct JavaLangString {
    pub fn intern(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const out: Value = .ref_value(Reference {
            kind: receiver.kind,
            slot: receiver.slot,
            generation: receiver.generation,
        });
        const _cava_optional_198: ?Value = out;
        return _cava_optional_198;
    }
}

fn java_lang_string_builder_append(context: &Context, vm: &VM, receiver: Reference, value: Reference): ?Value ! InstructionError {
    const slot: u16 = 0;
    var current_ref = null_ref;
    if vm.heap.get_field(receiver, slot) is current_value {
        current_ref = value_ref_or_null(current_value);
    } else {
        throw InstructionError.invalid_constant;
    }
    const combined_ref = try concat_java_string(context, vm, current_ref, value);
    if !vm.heap.set_field(receiver, slot, .ref_value(combined_ref)) {
        throw InstructionError.invalid_constant;
    }
    const out: Value = .ref_value(Reference {
        kind: receiver.kind,
        slot: receiver.slot,
        generation: receiver.generation,
    });
    const _cava_optional_197: ?Value = out;
    return _cava_optional_197;
}

fn java_lang_string_builder_init(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
    return none;
}

fn java_lang_string_builder_to_string(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
    const slot: u16 = 0;
    if vm.heap.get_field(receiver, slot) is current_value {
        const actual = value_ref_or_null(current_value);
        if actual.non_null() {
            const out: Value = .ref_value(Reference {
                kind: actual.kind,
                slot: actual.slot,
                generation: actual.generation,
            });
            const _cava_optional_196: ?Value = out;
            return _cava_optional_196;
        }
    }
    const _cava_optional_195: ?Value = return_value(.ref_value(null_ref));
    return _cava_optional_195;
}

fn java_io_print_stream_println(context: &Context, vm: &VM, receiver: Reference, value: Reference): ?Value ! InstructionError {
    print_java_string(context, vm, value);
    return none;
}

struct JavaLangFloat {
    pub fn floatToRawIntBits(context: &Context, value: f32): ?Value ! InstructionError {
        const _cava_optional_194: ?Value = return_value(.int_value(value as! i32));
        return _cava_optional_194;
    }

    pub fn intBitsToFloat(context: &Context, value: i32): ?Value ! InstructionError {
        const _cava_optional_193: ?Value = return_value(.float_value(value as! f32));
        return _cava_optional_193;
    }
}

struct JavaLangDouble {
    pub fn doubleToRawLongBits(context: &Context, value: f64): ?Value ! InstructionError {
        const _cava_optional_192: ?Value = return_value(.long_value(value as! i64));
        return _cava_optional_192;
    }

    pub fn longBitsToDouble(context: &Context, value: i64): ?Value ! InstructionError {
        const _cava_optional_191: ?Value = return_value(.double_value(value as! f64));
        return _cava_optional_191;
    }
}

struct JavaLangThread {
    pub fn registerNatives(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn currentThread(context: &Context, vm: &VM): ?Value ! InstructionError {
        const _cava_optional_190: ?Value = return_value(.ref_value(try new_java_lang_thread(context, vm)));
        return _cava_optional_190;
    }

    pub fn isAlive(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        if vm.heap.java_thread_alive(receiver) {
            const _cava_optional_189: ?Value = return_value(.boolean_value(1));
            return _cava_optional_189;
        }
        const _cava_optional_188: ?Value = return_value(.boolean_value(0));
        return _cava_optional_188;
    }

    pub fn setPriority0(context: &Context, receiver: Reference, priority: i32): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_priority = priority;
        return none;
    }

    pub fn start0(context: &Context, vm: &VM, receiver: Reference): ?Value ! InstructionError {
        var receiver_class_index: usize = 0;
        if vm.heap.object_class_index(receiver) is actual {
            receiver_class_index = actual;
        } else {
            throw InstructionError.invalid_constant;
        }
        var classes = vm.method_area.classes[..];
        if classes[receiver_class_index].name == "java/lang/ref/Reference$ReferenceHandler" {
            return none;
        }
        const ignored_target = try find_native_instance_method(vm, receiver_class_index, "run", "()V");
        try set_instance_field(context, vm, receiver, try vm.resolve_class_index("java/lang/Thread"), "threadStatus", "I", .int_value(2));
        const ignored_started = vm.heap.mark_java_thread_started(receiver);

        if context.runtime is actual_runtime {
            const handle = thread.spawn(java_thread_start_worker, JavaThreadStartPayload {
                vm: actual_runtime.alias_handles(),
                receiver: receiver
            }) catch (problem) {
                const ignored_finish_spawn = vm.heap.mark_java_thread_finished(receiver);
                throw InstructionError.invalid_constant;
            };
            actual_runtime.track(handle);
            return none;
        } else {
            const ignored_finish_missing_runtime = vm.heap.mark_java_thread_finished(receiver);
            throw InstructionError.invalid_constant;
        }
    }

    pub fn sleep(context: &Context, millis: i64): ?Value ! InstructionError {
        if context.runtime is runtime {
            if !runtime.pause(millis) {
                throw InstructionError.invalid_constant;
            }
            return none;
        }
        if millis > 0 {
            sleep_ms(millis) catch (problem) {
                throw InstructionError.invalid_constant;
            };
        }
        return none;
    }

    pub fn interrupt0(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        return none;
    }

    pub fn isInterrupted(context: &Context, receiver: Reference, clear_interrupted: i32): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_clear_interrupted = clear_interrupted;
        const _cava_optional_187: ?Value = return_value(.boolean_value(0));
        return _cava_optional_187;
    }

    pub fn holdsLock(context: &Context, vm: &VM, object: Reference): ?Value ! InstructionError {
        if vm.heap.monitor_held_by_current_thread(object) {
            const _cava_optional_186: ?Value = return_value(.boolean_value(1));
            return _cava_optional_186;
        }
        const _cava_optional_185: ?Value = return_value(.boolean_value(0));
        return _cava_optional_185;
    }

    pub fn yield0(context: &Context): ?Value ! InstructionError {
        if context.runtime is runtime {
            if !runtime.pause(0) {
                throw InstructionError.invalid_constant;
            }
        }
        return none;
    }

    pub fn clearInterruptEvent(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn setNativeName(context: &Context, receiver: Reference, name: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_name = name;
        return none;
    }
}

struct JavaLangThrowable {
    pub fn getStackTraceDepth(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_184: ?Value = return_value(.int_value(0));
        return _cava_optional_184;
    }

    pub fn fillInStackTrace(context: &Context, receiver: Reference, dummy: i32): ?Value ! InstructionError {
        const ignored_dummy = dummy;
        const _cava_optional_183: ?Value = return_value(.ref_value(receiver));
        return _cava_optional_183;
    }
}

struct JavaLangRuntime {
    pub fn availableProcessors(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_182: ?Value = return_value(.int_value(1));
        return _cava_optional_182;
    }

    pub fn freeMemory(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_181: ?Value = return_value(.long_value(16 * 1024 * 1024));
        return _cava_optional_181;
    }

    pub fn totalMemory(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_180: ?Value = return_value(.long_value(16 * 1024 * 1024));
        return _cava_optional_180;
    }

    pub fn maxMemory(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_179: ?Value = return_value(.long_value(256 * 1024 * 1024));
        return _cava_optional_179;
    }

    pub fn gc(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        return none;
    }
}

struct JavaLangShutdown {
    pub fn beforeHalt(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn halt0(context: &Context, status: i32): ?Value ! InstructionError {
        const ignored_status = status;
        return none;
    }
}

struct JavaLangRefFinalizer {
    pub fn isFinalizationEnabled(context: &Context): ?Value ! InstructionError {
        const _cava_optional_178: ?Value = return_value(.boolean_value(0));
        return _cava_optional_178;
    }

    pub fn reportComplete(context: &Context, finalizer: Reference): ?Value ! InstructionError {
        const ignored_finalizer = finalizer;
        return none;
    }
}

struct JavaLangRefReference {
    pub fn getAndClearReferencePendingList(context: &Context): ?Value ! InstructionError {
        const _cava_optional_177: ?Value = return_value(.ref_value(null_ref));
        return _cava_optional_177;
    }

    pub fn hasReferencePendingList(context: &Context): ?Value ! InstructionError {
        const _cava_optional_176: ?Value = return_value(.boolean_value(0));
        return _cava_optional_176;
    }

    pub fn waitForReferencePendingList(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn refersTo0(context: &Context, receiver: Reference, object: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_object = object;
        const _cava_optional_175: ?Value = return_value(.boolean_value(0));
        return _cava_optional_175;
    }

    pub fn clear0(context: &Context, receiver: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        return none;
    }
}

struct SunReflectReflection {
    pub fn getCallerClass(context: &Context, vm: &VM): ?Value ! InstructionError {
        const _cava_optional_174: ?Value = return_value(.ref_value(try ensure_class_object(context, vm, context.class_index)));
        return _cava_optional_174;
    }

    pub fn getClassAccessFlags(context: &Context, vm: &VM, class_object: Reference): ?Value ! InstructionError {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, class_object) is class_index {
            const class = &classes[class_index];
            const _cava_optional_173: ?Value = return_value(.int_value(raw_class_access(class.access_flags) as i32));
            return _cava_optional_173;
        }
        throw InstructionError.invalid_constant;
    }
}

struct JdkInternalReflectReflection {
    pub fn getCallerClass(context: &Context, vm: &VM): ?Value ! InstructionError {
        const _cava_optional_172: ?Value = try SunReflectReflection.getCallerClass(context, vm);
        return _cava_optional_172;
    }

    pub fn getClassAccessFlags(context: &Context, vm: &VM, class_object: Reference): ?Value ! InstructionError {
        const _cava_optional_171: ?Value = try SunReflectReflection.getClassAccessFlags(context, vm, class_object);
        return _cava_optional_171;
    }
}

struct JavaSecurityAccessController {
    pub fn getStackAccessControlContext(context: &Context): ?Value ! InstructionError {
        const _cava_optional_170: ?Value = return_value(.ref_value(null_ref));
        return _cava_optional_170;
    }
}

struct SunMiscVM {
    pub fn initialize(context: &Context): ?Value ! InstructionError {
        return none;
    }
}

struct SunMiscUnsafe {
    pub fn registerNatives(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn arrayBaseOffset(context: &Context, class: Reference): ?Value ! InstructionError {
        const ignored_class = class;
        const _cava_optional_169: ?Value = return_value(.int_value(0));
        return _cava_optional_169;
    }

    pub fn arrayIndexScale(context: &Context, class: Reference): ?Value ! InstructionError {
        const ignored_class = class;
        const _cava_optional_168: ?Value = return_value(.int_value(1));
        return _cava_optional_168;
    }

    pub fn objectFieldOffset(context: &Context, vm: &VM, field: Reference): ?Value ! InstructionError {
        const field_class_index = try find_or_load_native_class_index(context, vm, "java/lang/reflect/Field");
        var classes = vm.method_area.classes[..];
        const clazz_value = try get_instance_field_in(context, vm, classes, field, field_class_index, "clazz", "Ljava/lang/Class;");
        const slot_value = try get_instance_field_in(context, vm, classes, field, field_class_index, "slot", "I");
        switch clazz_value {
            .ref_value(clazz) => {
                classes = vm.method_area.classes[..];
                if find_class_object_index_in(classes, clazz) is declaring_class_index {
                    const declaring_class = &classes[declaring_class_index];
                    switch slot_value {
                        .int_value(slot) => {
                            if native_field_runtime_slot(classes, declaring_class_index, declaring_class.name, slot as u16) is runtime_slot {
                                const _cava_optional_167: ?Value = return_value(.long_value(runtime_slot as i64));
                                return _cava_optional_167;
                            }
                            throw InstructionError.invalid_constant;
                        }
                        _ => throw InstructionError.invalid_constant;
                    }
                }
                throw InstructionError.invalid_constant;
            }
            _ => throw InstructionError.invalid_constant;
        }
    }

    pub fn compareAndSwapInt(context: &Context, vm: &VM, object: Reference, offset: i64, expected: i32, value: i32): ?Value ! InstructionError {
        if offset < 0 {
            throw InstructionError.invalid_constant;
        }
        if object.kind == ReferenceKind.array {
            if vm.heap.get_element(object, offset as usize) is current {
                switch current {
                    .int_value(actual) => {
                        if actual == expected {
                            const ignored_set = vm.heap.set_element(object, offset as usize, .int_value(value));
                            const _cava_optional_166: ?Value = return_value(.boolean_value(1));
                            return _cava_optional_166;
                        }
                        const _cava_optional_165: ?Value = return_value(.boolean_value(0));
                        return _cava_optional_165;
                    }
                    _ => {
                        const _cava_optional_164: ?Value = return_value(.boolean_value(0));
                        return _cava_optional_164;
                    }
                }
            }
            throw InstructionError.invalid_constant;
        }
        if vm.heap.get_field(object, offset as u16) is current_field {
            switch current_field {
                .int_value(actual) => {
                    if actual == expected {
                        const ignored_set = vm.heap.set_field(object, offset as u16, .int_value(value));
                        const _cava_optional_163: ?Value = return_value(.boolean_value(1));
                        return _cava_optional_163;
                    }
                    const _cava_optional_162: ?Value = return_value(.boolean_value(0));
                    return _cava_optional_162;
                }
                .boolean_value(actual) => {
                    if actual as i32 == expected {
                        const ignored_set = vm.heap.set_field(object, offset as u16, .boolean_value(value as u8));
                        const _cava_optional_161: ?Value = return_value(.boolean_value(1));
                        return _cava_optional_161;
                    }
                    const _cava_optional_160: ?Value = return_value(.boolean_value(0));
                    return _cava_optional_160;
                }
                _ => {
                    const _cava_optional_159: ?Value = return_value(.boolean_value(0));
                    return _cava_optional_159;
                }
            }
        }
        throw InstructionError.invalid_constant;
    }

    pub fn compareAndSwapLong(context: &Context, object: Reference, offset: i64, expected: i64, value: i64): ?Value ! InstructionError {
        const ignored_object = object;
        const ignored_offset = offset;
        const ignored_expected = expected;
        const ignored_value = value;
        const _cava_optional_158: ?Value = return_value(.boolean_value(1));
        return _cava_optional_158;
    }

    pub fn compareAndSwapObject(context: &Context, vm: &VM, object: Reference, offset: i64, expected: Reference, value: Reference): ?Value ! InstructionError {
        const ignored_expected = expected;
        if object.kind == ReferenceKind.array and offset >= 0 {
            const ignored_set = vm.heap.set_element(object, offset as usize, .ref_value(value));
        } else if offset >= 0 {
            const ignored_set = vm.heap.set_field(object, offset as u16, .ref_value(value));
        }
        const _cava_optional_157: ?Value = return_value(.boolean_value(1));
        return _cava_optional_157;
    }

    pub fn getIntVolatile(context: &Context, vm: &VM, object: Reference, offset: i64): ?Value ! InstructionError {
        if offset < 0 {
            throw InstructionError.invalid_constant;
        }
        if object.kind == ReferenceKind.array {
            if vm.heap.get_element(object, offset as usize) is value {
                const _cava_optional_156: ?Value = return_value(value);
                return _cava_optional_156;
            }
        } else if vm.heap.get_field(object, offset as u16) is value {
            const _cava_optional_155: ?Value = return_value(value);
            return _cava_optional_155;
        }
        throw InstructionError.invalid_constant;
    }

    pub fn getObjectVolatile(context: &Context, vm: &VM, object: Reference, offset: i64): ?Value ! InstructionError {
        if object.kind == ReferenceKind.array and offset >= 0 {
            if vm.heap.get_element(object, offset as usize) is value {
                const _cava_optional_154: ?Value = return_value(value);
                return _cava_optional_154;
            }
        } else if offset >= 0 {
            if vm.heap.get_field(object, offset as u16) is value {
                const _cava_optional_153: ?Value = return_value(value);
                return _cava_optional_153;
            }
        }
        const _cava_optional_152: ?Value = return_value(.ref_value(null_ref));
        return _cava_optional_152;
    }

    pub fn putObjectVolatile(context: &Context, vm: &VM, object: Reference, offset: i64, value: Reference): ?Value ! InstructionError {
        if object.kind == ReferenceKind.array and offset >= 0 {
            const ignored_set = vm.heap.set_element(object, offset as usize, .ref_value(value));
        } else if offset >= 0 {
            const ignored_set = vm.heap.set_field(object, offset as u16, .ref_value(value));
        }
        return none;
    }

    pub fn allocateMemory(context: &Context, size: i64): ?Value ! InstructionError {
        const ignored_size = size;
        const _cava_optional_151: ?Value = return_value(.long_value(1));
        return _cava_optional_151;
    }

    pub fn putLong(context: &Context, address: i64, value: i64): ?Value ! InstructionError {
        const ignored_address = address;
        const ignored_value = value;
        return none;
    }

    pub fn getByte(context: &Context, address: i64): ?Value ! InstructionError {
        const ignored_address = address;
        const _cava_optional_150: ?Value = return_value(.byte_value(8));
        return _cava_optional_150;
    }

    pub fn freeMemory(context: &Context, address: i64): ?Value ! InstructionError {
        const ignored_address = address;
        return none;
    }

    pub fn ensureClassInitialized(context: &Context, class: Reference): ?Value ! InstructionError {
        const ignored_class = class;
        return none;
    }

    pub fn addressSize(context: &Context): ?Value ! InstructionError {
        const _cava_optional_149: ?Value = return_value(.int_value(8));
        return _cava_optional_149;
    }
}

struct JavaIoFileDescriptor {
    pub fn initIDs(context: &Context): ?Value ! InstructionError {
        return none;
    }
}

struct JavaIoFileInputStream {
    pub fn initIDs(context: &Context): ?Value ! InstructionError {
        return none;
    }
}

struct JavaIoFileOutputStream {
    pub fn initIDs(context: &Context): ?Value ! InstructionError {
        return none;
    }
}

struct JavaIoUnixFileSystem {
    pub fn initIDs(context: &Context): ?Value ! InstructionError {
        return none;
    }

    pub fn canonicalize0(context: &Context, receiver: Reference, path: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const _cava_optional_148: ?Value = return_value(.ref_value(path));
        return _cava_optional_148;
    }

    pub fn getBooleanAttributes0(context: &Context, receiver: Reference, file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const _cava_optional_147: ?Value = return_value(.int_value(0));
        return _cava_optional_147;
    }

    pub fn checkAccess0(context: &Context, receiver: Reference, file: Reference, access: i32): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_access = access;
        const _cava_optional_146: ?Value = return_value(.boolean_value(0));
        return _cava_optional_146;
    }

    pub fn getLastModifiedTime0(context: &Context, receiver: Reference, file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const _cava_optional_145: ?Value = return_value(.long_value(0));
        return _cava_optional_145;
    }

    pub fn getLength0(context: &Context, receiver: Reference, file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const _cava_optional_144: ?Value = return_value(.long_value(0));
        return _cava_optional_144;
    }

    pub fn setPermission0(context: &Context, receiver: Reference, file: Reference, access: i32, enable: i32, owneronly: i32): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_access = access;
        const ignored_enable = enable;
        const ignored_owneronly = owneronly;
        const _cava_optional_143: ?Value = return_value(.boolean_value(0));
        return _cava_optional_143;
    }

    pub fn createFileExclusively0(context: &Context, receiver: Reference, path: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_path = path;
        const _cava_optional_142: ?Value = return_value(.boolean_value(0));
        return _cava_optional_142;
    }

    pub fn delete0(context: &Context, receiver: Reference, file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const _cava_optional_141: ?Value = return_value(.boolean_value(0));
        return _cava_optional_141;
    }

    pub fn list0(context: &Context, receiver: Reference, file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const _cava_optional_140: ?Value = return_value(.ref_value(null_ref));
        return _cava_optional_140;
    }

    pub fn createDirectory0(context: &Context, receiver: Reference, file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const _cava_optional_139: ?Value = return_value(.boolean_value(0));
        return _cava_optional_139;
    }

    pub fn rename0(context: &Context, receiver: Reference, from_file: Reference, to_file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_from_file = from_file;
        const ignored_to_file = to_file;
        const _cava_optional_138: ?Value = return_value(.boolean_value(0));
        return _cava_optional_138;
    }

    pub fn setLastModifiedTime0(context: &Context, receiver: Reference, file: Reference, time: i64): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_time = time;
        const _cava_optional_137: ?Value = return_value(.boolean_value(0));
        return _cava_optional_137;
    }

    pub fn setReadOnly0(context: &Context, receiver: Reference, file: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const _cava_optional_136: ?Value = return_value(.boolean_value(0));
        return _cava_optional_136;
    }

    pub fn getSpace0(context: &Context, receiver: Reference, file: Reference, t: i32): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_file = file;
        const ignored_t = t;
        const _cava_optional_135: ?Value = return_value(.long_value(0));
        return _cava_optional_135;
    }

    pub fn getNameMax0(context: &Context, receiver: Reference, path: Reference): ?Value ! InstructionError {
        const ignored_receiver = receiver;
        const ignored_path = path;
        const _cava_optional_134: ?Value = return_value(.long_value(255));
        return _cava_optional_134;
    }
}

struct JavaUtilConcurrentAtomicAtomicLong {
    pub fn VMSupportsCS8(context: &Context): ?Value ! InstructionError {
        const _cava_optional_133: ?Value = return_value(.boolean_value(1));
        return _cava_optional_133;
    }
}

struct JavaUtilZipZipFile {
    pub fn initIDs(context: &Context): ?Value ! InstructionError {
        return none;
    }
}

fn method_is(method: &Method, name: string, descriptor: string): bool {
    return method.name == name and method.descriptor == descriptor;
}

pub fn execute_native_method(context: &Context, vm: &VM, class_index: usize, method_index: usize, receiver: ?Reference, arguments: List<Value>): ?Value ! InstructionError {
    const monitor = try enter_method_monitor(context.runtime, vm, class_index, method_index, receiver);
    const result = execute_native_method_body(context, vm, class_index, method_index, receiver, arguments) catch (problem) {
        try exit_method_monitor(vm, monitor);
        throw problem;
    };
    try exit_method_monitor(vm, monitor);
    const _cava_optional_132: ?Value = result;
    return _cava_optional_132;
}

fn execute_native_method_body(context: &Context, vm: &VM, class_index: usize, method_index: usize, receiver: ?Reference, arguments: List<Value>): ?Value ! InstructionError {
    var args = arguments;
    var classes = vm.method_area.classes[..];
    const class = &classes[class_index];
    var methods = class.methods[..];
    const method = &methods[method_index];
    if is_access_controller_do_privileged(classes, class_index, method_index) {
        if args.len() == 0 {
            throw InstructionError.invalid_constant;
        }
        const _cava_optional_131: ?Value = try invoke_privileged_action(context, vm, ref_arg(&args, 0));
        return _cava_optional_131;
    }
    if class.name == "java/lang/System" and method_is(method, "initProperties", "(Ljava/util/Properties;)Ljava/util/Properties;") {
        if args.len() == 0 {
            throw InstructionError.invalid_constant;
        }
        const properties = ref_arg(&args, 0);
        if properties.non_null() {
            const _cava_optional_130: ?Value = try initialize_java_system_properties(context, vm, properties);
            return _cava_optional_130;
        }
    }
    if class.name == "sun/reflect/NativeConstructorAccessorImpl" and method_is(method, "newInstance0", "(Ljava/lang/reflect/Constructor;[Ljava/lang/Object;)Ljava/lang/Object;") {
        if args.len() < 2 {
            throw InstructionError.invalid_constant;
        }
        const _cava_optional_129: ?Value = try invoke_reflect_constructor(context, vm, ref_arg(&args, 0), ref_arg(&args, 1));
        return _cava_optional_129;
    }
    if class.name == "java/lang/System" {
        if method_is(method, "registerNatives", "()V") {
            const _cava_optional_128: ?Value = try JavaLangSystem.registerNatives(context);
            return _cava_optional_128;
        }
        if method_is(method, "setIn0", "(Ljava/io/InputStream;)V") {
            const _cava_optional_127: ?Value = try JavaLangSystem.setIn0(context, vm, ref_arg(&args, 0));
            return _cava_optional_127;
        }
        if method_is(method, "setOut0", "(Ljava/io/PrintStream;)V") {
            const _cava_optional_126: ?Value = try JavaLangSystem.setOut0(context, vm, ref_arg(&args, 0));
            return _cava_optional_126;
        }
        if method_is(method, "setErr0", "(Ljava/io/PrintStream;)V") {
            const _cava_optional_125: ?Value = try JavaLangSystem.setErr0(context, vm, ref_arg(&args, 0));
            return _cava_optional_125;
        }
        if method_is(method, "currentTimeMillis", "()J") {
            const _cava_optional_124: ?Value = try JavaLangSystem.currentTimeMillis(context);
            return _cava_optional_124;
        }
        if method_is(method, "nanoTime", "()J") {
            const _cava_optional_123: ?Value = try JavaLangSystem.nanoTime(context);
            return _cava_optional_123;
        }
        if method_is(method, "arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V") {
            const _cava_optional_122: ?Value = try JavaLangSystem.arraycopy(context, vm, ref_arg(&args, 0), int_arg(&args, 1), ref_arg(&args, 2), int_arg(&args, 3), int_arg(&args, 4));
            return _cava_optional_122;
        }
        if method_is(method, "identityHashCode", "(Ljava/lang/Object;)I") {
            const _cava_optional_121: ?Value = try JavaLangSystem.identityHashCode(context, ref_arg(&args, 0));
            return _cava_optional_121;
        }
        if method_is(method, "mapLibraryName", "(Ljava/lang/String;)Ljava/lang/String;") {
            const _cava_optional_120: ?Value = try JavaLangSystem.mapLibraryName(context, ref_arg(&args, 0));
            return _cava_optional_120;
        }
        if method_is(method, "initProperties", "(Ljava/util/Properties;)Ljava/util/Properties;") {
            const _cava_optional_119: ?Value = try JavaLangSystem.initProperties(context, ref_arg(&args, 0));
            return _cava_optional_119;
        }
        if method_is(method, "getProperty", "(Ljava/lang/String;)Ljava/lang/String;") {
            const _cava_optional_118: ?Value = try JavaLangSystem.getProperty(context, vm, ref_arg(&args, 0));
            return _cava_optional_118;
        }
    }

    if class.name == "java/lang/Object" {
        if method_is(method, "<init>", "()V") {
            const _cava_optional_117: ?Value = try JavaLangObject.init(context, try receiver_ref(receiver));
            return _cava_optional_117;
        }
        if method_is(method, "registerNatives", "()V") {
            const _cava_optional_116: ?Value = try JavaLangObject.registerNatives(context);
            return _cava_optional_116;
        }
        if method_is(method, "hashCode", "()I") {
            const _cava_optional_115: ?Value = try JavaLangObject.hashCode(context, try receiver_ref(receiver));
            return _cava_optional_115;
        }
        if method_is(method, "getClass", "()Ljava/lang/Class;") {
            const _cava_optional_114: ?Value = try JavaLangObject.getClass(context, vm, try receiver_ref(receiver));
            return _cava_optional_114;
        }
        if method_is(method, "clone", "()Ljava/lang/Object;") {
            const _cava_optional_113: ?Value = try JavaLangObject.clone(context, vm, try receiver_ref(receiver));
            return _cava_optional_113;
        }
        if method_is(method, "notify", "()V") {
            const _cava_optional_112: ?Value = try JavaLangObject.notify(context, try receiver_ref(receiver));
            return _cava_optional_112;
        }
        if method_is(method, "notifyAll", "()V") {
            const _cava_optional_111: ?Value = try JavaLangObject.notifyAll(context, try receiver_ref(receiver));
            return _cava_optional_111;
        }
        if method_is(method, "wait", "(J)V") {
            const _cava_optional_110: ?Value = try JavaLangObject.wait(context, try receiver_ref(receiver), long_arg(&args, 0));
            return _cava_optional_110;
        }
    }

    if class.name == "java/lang/String" {
        if method_is(method, "intern", "()Ljava/lang/String;") {
            const _cava_optional_109: ?Value = try JavaLangString.intern(context, try receiver_ref(receiver));
            return _cava_optional_109;
        }
    }

    if class.name == "java/lang/StringBuilder" {
        if method_is(method, "<init>", "()V") {
            const _cava_optional_108: ?Value = try java_lang_string_builder_init(context, vm, try receiver_ref(receiver));
            return _cava_optional_108;
        }
        if method_is(method, "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;") {
            const _cava_optional_107: ?Value = try java_lang_string_builder_append(context, vm, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_107;
        }
        if method_is(method, "toString", "()Ljava/lang/String;") {
            const _cava_optional_106: ?Value = try java_lang_string_builder_to_string(context, vm, try receiver_ref(receiver));
            return _cava_optional_106;
        }
    }

    if class.name == "java/lang/Class" {
        if method_is(method, "registerNatives", "()V") {
            const _cava_optional_105: ?Value = try JavaLangClass.registerNatives(context);
            return _cava_optional_105;
        }
        if method_is(method, "getPrimitiveClass", "(Ljava/lang/String;)Ljava/lang/Class;") {
            const _cava_optional_104: ?Value = try JavaLangClass.getPrimitiveClass(context, vm, ref_arg(&args, 0));
            return _cava_optional_104;
        }
        if method_is(method, "desiredAssertionStatus0", "(Ljava/lang/Class;)Z") {
            const _cava_optional_103: ?Value = try JavaLangClass.desiredAssertionStatus0(context, ref_arg(&args, 0));
            return _cava_optional_103;
        }
        if method_is(method, "getDeclaredFields0", "(Z)[Ljava/lang/reflect/Field;") {
            const _cava_optional_102: ?Value = try JavaLangClass.getDeclaredFields0(context, vm, try receiver_ref(receiver), int_arg(&args, 0));
            return _cava_optional_102;
        }
        if method_is(method, "getDeclaredConstructors0", "(Z)[Ljava/lang/reflect/Constructor;") {
            const _cava_optional_101: ?Value = try JavaLangClass.getDeclaredConstructors0(context, vm, try receiver_ref(receiver), int_arg(&args, 0));
            return _cava_optional_101;
        }
        if method_is(method, "isPrimitive", "()Z") {
            const _cava_optional_100: ?Value = try JavaLangClass.isPrimitive(context, vm, try receiver_ref(receiver));
            return _cava_optional_100;
        }
        if method_is(method, "forName0", "(Ljava/lang/String;ZLjava/lang/ClassLoader;Ljava/lang/Class;)Ljava/lang/Class;") {
            const _cava_optional_99: ?Value = try JavaLangClass.forName0(context, vm, ref_arg(&args, 0), int_arg(&args, 1), ref_arg(&args, 2), ref_arg(&args, 3));
            return _cava_optional_99;
        }
        if method_is(method, "isAssignableFrom", "(Ljava/lang/Class;)Z") {
            const _cava_optional_98: ?Value = try JavaLangClass.isAssignableFrom(context, vm, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_98;
        }
        if method_is(method, "getName0", "()Ljava/lang/String;") {
            const _cava_optional_97: ?Value = try JavaLangClass.getName0(context, vm, try receiver_ref(receiver));
            return _cava_optional_97;
        }
        if method_is(method, "initClassName", "()Ljava/lang/String;") {
            const _cava_optional_96: ?Value = try JavaLangClass.initClassName(context, vm, try receiver_ref(receiver));
            return _cava_optional_96;
        }
        if method_is(method, "descriptorString", "()Ljava/lang/String;") {
            const _cava_optional_95: ?Value = try JavaLangClass.descriptorString(context, vm, try receiver_ref(receiver));
            return _cava_optional_95;
        }
        if method_is(method, "isArray", "()Z") {
            const _cava_optional_94: ?Value = try JavaLangClass.isArray(context, vm, try receiver_ref(receiver));
            return _cava_optional_94;
        }
        if method_is(method, "getComponentType", "()Ljava/lang/Class;") {
            const _cava_optional_93: ?Value = try JavaLangClass.getComponentType(context, vm, try receiver_ref(receiver));
            return _cava_optional_93;
        }
        if method_is(method, "isInterface", "()Z") {
            const _cava_optional_92: ?Value = try JavaLangClass.isInterface(context, vm, try receiver_ref(receiver));
            return _cava_optional_92;
        }
        if method_is(method, "getModifiers", "()I") {
            const _cava_optional_91: ?Value = try JavaLangClass.getModifiers(context, vm, try receiver_ref(receiver));
            return _cava_optional_91;
        }
        if method_is(method, "getSuperclass", "()Ljava/lang/Class;") {
            const _cava_optional_90: ?Value = try JavaLangClass.getSuperclass(context, vm, try receiver_ref(receiver));
            return _cava_optional_90;
        }
        if method_is(method, "getClassAccessFlagsRaw0", "()I") {
            const _cava_optional_89: ?Value = try JavaLangClass.getClassAccessFlagsRaw0(context, vm, try receiver_ref(receiver));
            return _cava_optional_89;
        }
        if method_is(method, "getClassFileVersion0", "()I") {
            const _cava_optional_88: ?Value = try JavaLangClass.getClassFileVersion0(context, try receiver_ref(receiver));
            return _cava_optional_88;
        }
        if method_is(method, "isHidden", "()Z") {
            const _cava_optional_87: ?Value = try JavaLangClass.isHidden(context, try receiver_ref(receiver));
            return _cava_optional_87;
        }
        if method_is(method, "isRecord0", "()Z") {
            const _cava_optional_86: ?Value = try JavaLangClass.isRecord0(context, try receiver_ref(receiver));
            return _cava_optional_86;
        }
    }

    if class.name == "java/lang/ClassLoader" {
        if method_is(method, "registerNatives", "()V") {
            const _cava_optional_85: ?Value = try JavaLangClassLoader.registerNatives(context);
            return _cava_optional_85;
        }
        if method_is(method, "findBuiltinLib", "(Ljava/lang/String;)Ljava/lang/String;") {
            const _cava_optional_84: ?Value = try JavaLangClassLoader.findBuiltinLib(context, ref_arg(&args, 0));
            return _cava_optional_84;
        }
    }

    if class.name == "java/lang/ClassLoader$NativeLibrary" {
        if method_is(method, "load", "(Ljava/lang/String;Z)V") {
            const _cava_optional_83: ?Value = try JavaLangClassLoaderNativeLibrary.load(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1));
            return _cava_optional_83;
        }
    }

    if class.name == "java/lang/reflect/Array" {
        if method_is(method, "newArray", "(Ljava/lang/Class;I)Ljava/lang/Object;") {
            const _cava_optional_82: ?Value = try JavaLangReflectArray.newArray(context, vm, ref_arg(&args, 0), int_arg(&args, 1));
            return _cava_optional_82;
        }
    }

    if class.name == "java/lang/Package" {
        if method_is(method, "getSystemPackage0", "(Ljava/lang/String;)Ljava/lang/String;") {
            const _cava_optional_81: ?Value = try JavaLangPackage.getSystemPackage0(context, ref_arg(&args, 0));
            return _cava_optional_81;
        }
    }

    if class.name == "java/lang/Float" {
        if method_is(method, "floatToRawIntBits", "(F)I") {
            const _cava_optional_80: ?Value = try JavaLangFloat.floatToRawIntBits(context, float_arg(&args, 0));
            return _cava_optional_80;
        }
        if method_is(method, "intBitsToFloat", "(I)F") {
            const _cava_optional_79: ?Value = try JavaLangFloat.intBitsToFloat(context, int_arg(&args, 0));
            return _cava_optional_79;
        }
    }

    if class.name == "java/lang/Double" {
        if method_is(method, "doubleToRawLongBits", "(D)J") {
            const _cava_optional_78: ?Value = try JavaLangDouble.doubleToRawLongBits(context, double_arg(&args, 0));
            return _cava_optional_78;
        }
        if method_is(method, "longBitsToDouble", "(J)D") {
            const _cava_optional_77: ?Value = try JavaLangDouble.longBitsToDouble(context, long_arg(&args, 0));
            return _cava_optional_77;
        }
    }

    if class.name == "java/lang/Thread" {
        if method_is(method, "registerNatives", "()V") {
            const _cava_optional_76: ?Value = try JavaLangThread.registerNatives(context);
            return _cava_optional_76;
        }
        if method_is(method, "currentThread", "()Ljava/lang/Thread;") {
            const _cava_optional_75: ?Value = try JavaLangThread.currentThread(context, vm);
            return _cava_optional_75;
        }
        if method_is(method, "isAlive", "()Z") {
            const _cava_optional_74: ?Value = try JavaLangThread.isAlive(context, vm, try receiver_ref(receiver));
            return _cava_optional_74;
        }
        if method_is(method, "setPriority0", "(I)V") {
            const _cava_optional_73: ?Value = try JavaLangThread.setPriority0(context, try receiver_ref(receiver), int_arg(&args, 0));
            return _cava_optional_73;
        }
        if method_is(method, "start0", "()V") {
            const _cava_optional_72: ?Value = try JavaLangThread.start0(context, vm, try receiver_ref(receiver));
            return _cava_optional_72;
        }
        if method_is(method, "sleep", "(J)V") {
            const _cava_optional_71: ?Value = try JavaLangThread.sleep(context, long_arg(&args, 0));
            return _cava_optional_71;
        }
        if method_is(method, "interrupt0", "()V") {
            const _cava_optional_70: ?Value = try JavaLangThread.interrupt0(context, try receiver_ref(receiver));
            return _cava_optional_70;
        }
        if method_is(method, "isInterrupted", "(Z)Z") {
            const _cava_optional_69: ?Value = try JavaLangThread.isInterrupted(context, try receiver_ref(receiver), int_arg(&args, 0));
            return _cava_optional_69;
        }
        if method_is(method, "holdsLock", "(Ljava/lang/Object;)Z") {
            const _cava_optional_68: ?Value = try JavaLangThread.holdsLock(context, vm, ref_arg(&args, 0));
            return _cava_optional_68;
        }
        if method_is(method, "yield0", "()V") or method_is(method, "yield", "()V") {
            const _cava_optional_67: ?Value = try JavaLangThread.yield0(context);
            return _cava_optional_67;
        }
        if method_is(method, "clearInterruptEvent", "()V") {
            const _cava_optional_66: ?Value = try JavaLangThread.clearInterruptEvent(context);
            return _cava_optional_66;
        }
        if method_is(method, "setNativeName", "(Ljava/lang/String;)V") {
            const _cava_optional_65: ?Value = try JavaLangThread.setNativeName(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_65;
        }
    }

    if class.name == "java/lang/Throwable" {
        if method_is(method, "getStackTraceDepth", "()I") {
            const _cava_optional_64: ?Value = try JavaLangThrowable.getStackTraceDepth(context, try receiver_ref(receiver));
            return _cava_optional_64;
        }
        if method_is(method, "fillInStackTrace", "(I)Ljava/lang/Throwable;") {
            const _cava_optional_63: ?Value = try JavaLangThrowable.fillInStackTrace(context, try receiver_ref(receiver), int_arg(&args, 0));
            return _cava_optional_63;
        }
    }

    if class.name == "java/lang/Runtime" {
        if method_is(method, "availableProcessors", "()I") {
            const _cava_optional_62: ?Value = try JavaLangRuntime.availableProcessors(context, try receiver_ref(receiver));
            return _cava_optional_62;
        }
        if method_is(method, "freeMemory", "()J") {
            const _cava_optional_61: ?Value = try JavaLangRuntime.freeMemory(context, try receiver_ref(receiver));
            return _cava_optional_61;
        }
        if method_is(method, "totalMemory", "()J") {
            const _cava_optional_60: ?Value = try JavaLangRuntime.totalMemory(context, try receiver_ref(receiver));
            return _cava_optional_60;
        }
        if method_is(method, "maxMemory", "()J") {
            const _cava_optional_59: ?Value = try JavaLangRuntime.maxMemory(context, try receiver_ref(receiver));
            return _cava_optional_59;
        }
        if method_is(method, "gc", "()V") {
            const _cava_optional_58: ?Value = try JavaLangRuntime.gc(context, try receiver_ref(receiver));
            return _cava_optional_58;
        }
    }

    if class.name == "java/lang/Shutdown" {
        if method_is(method, "beforeHalt", "()V") {
            const _cava_optional_57: ?Value = try JavaLangShutdown.beforeHalt(context);
            return _cava_optional_57;
        }
        if method_is(method, "halt0", "(I)V") {
            const _cava_optional_56: ?Value = try JavaLangShutdown.halt0(context, int_arg(&args, 0));
            return _cava_optional_56;
        }
    }

    if class.name == "java/lang/ref/Finalizer" {
        if method_is(method, "isFinalizationEnabled", "()Z") {
            const _cava_optional_55: ?Value = try JavaLangRefFinalizer.isFinalizationEnabled(context);
            return _cava_optional_55;
        }
        if method_is(method, "reportComplete", "(Ljava/lang/Object;)V") {
            const _cava_optional_54: ?Value = try JavaLangRefFinalizer.reportComplete(context, ref_arg(&args, 0));
            return _cava_optional_54;
        }
    }

    if class.name == "java/lang/ref/Reference" {
        if method_is(method, "getAndClearReferencePendingList", "()Ljava/lang/ref/Reference;") {
            const _cava_optional_53: ?Value = try JavaLangRefReference.getAndClearReferencePendingList(context);
            return _cava_optional_53;
        }
        if method_is(method, "hasReferencePendingList", "()Z") {
            const _cava_optional_52: ?Value = try JavaLangRefReference.hasReferencePendingList(context);
            return _cava_optional_52;
        }
        if method_is(method, "waitForReferencePendingList", "()V") {
            const _cava_optional_51: ?Value = try JavaLangRefReference.waitForReferencePendingList(context);
            return _cava_optional_51;
        }
        if method_is(method, "refersTo0", "(Ljava/lang/Object;)Z") {
            const _cava_optional_50: ?Value = try JavaLangRefReference.refersTo0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_50;
        }
        if method_is(method, "clear0", "()V") {
            const _cava_optional_49: ?Value = try JavaLangRefReference.clear0(context, try receiver_ref(receiver));
            return _cava_optional_49;
        }
    }

    if class.name == "sun/reflect/Reflection" {
        if method_is(method, "getCallerClass", "()Ljava/lang/Class;") {
            const _cava_optional_48: ?Value = try SunReflectReflection.getCallerClass(context, vm);
            return _cava_optional_48;
        }
        if method_is(method, "getClassAccessFlags", "(Ljava/lang/Class;)I") {
            const _cava_optional_47: ?Value = try SunReflectReflection.getClassAccessFlags(context, vm, ref_arg(&args, 0));
            return _cava_optional_47;
        }
    }

    if class.name == "jdk/internal/reflect/Reflection" {
        if method_is(method, "getCallerClass", "()Ljava/lang/Class;") {
            const _cava_optional_46: ?Value = try JdkInternalReflectReflection.getCallerClass(context, vm);
            return _cava_optional_46;
        }
        if method_is(method, "getClassAccessFlags", "(Ljava/lang/Class;)I") {
            const _cava_optional_45: ?Value = try JdkInternalReflectReflection.getClassAccessFlags(context, vm, ref_arg(&args, 0));
            return _cava_optional_45;
        }
    }

    if class.name == "java/security/AccessController" {
        if method_is(method, "getStackAccessControlContext", "()Ljava/security/AccessControlContext;") {
            const _cava_optional_44: ?Value = try JavaSecurityAccessController.getStackAccessControlContext(context);
            return _cava_optional_44;
        }
    }

    if class.name == "sun/misc/VM" {
        if method_is(method, "initialize", "()V") {
            const _cava_optional_43: ?Value = try SunMiscVM.initialize(context);
            return _cava_optional_43;
        }
    }

    if class.name == "sun/misc/Unsafe" {
        if method_is(method, "registerNatives", "()V") {
            const _cava_optional_42: ?Value = try SunMiscUnsafe.registerNatives(context);
            return _cava_optional_42;
        }
        if method_is(method, "arrayBaseOffset", "(Ljava/lang/Class;)I") {
            const _cava_optional_41: ?Value = try SunMiscUnsafe.arrayBaseOffset(context, ref_arg(&args, 0));
            return _cava_optional_41;
        }
        if method_is(method, "arrayIndexScale", "(Ljava/lang/Class;)I") {
            const _cava_optional_40: ?Value = try SunMiscUnsafe.arrayIndexScale(context, ref_arg(&args, 0));
            return _cava_optional_40;
        }
        if method_is(method, "objectFieldOffset", "(Ljava/lang/reflect/Field;)J") {
            const _cava_optional_39: ?Value = try SunMiscUnsafe.objectFieldOffset(context, vm, ref_arg(&args, 0));
            return _cava_optional_39;
        }
        if method_is(method, "compareAndSwapInt", "(Ljava/lang/Object;JII)Z") {
            const _cava_optional_38: ?Value = try SunMiscUnsafe.compareAndSwapInt(context, vm, ref_arg(&args, 0), long_arg(&args, 1), int_arg(&args, 2), int_arg(&args, 3));
            return _cava_optional_38;
        }
        if method_is(method, "compareAndSwapLong", "(Ljava/lang/Object;JJJ)Z") {
            const _cava_optional_37: ?Value = try SunMiscUnsafe.compareAndSwapLong(context, ref_arg(&args, 0), long_arg(&args, 1), long_arg(&args, 2), long_arg(&args, 3));
            return _cava_optional_37;
        }
        if method_is(method, "compareAndSwapObject", "(Ljava/lang/Object;JLjava/lang/Object;Ljava/lang/Object;)Z") {
            const _cava_optional_36: ?Value = try SunMiscUnsafe.compareAndSwapObject(context, vm, ref_arg(&args, 0), long_arg(&args, 1), ref_arg(&args, 2), ref_arg(&args, 3));
            return _cava_optional_36;
        }
        if method_is(method, "getIntVolatile", "(Ljava/lang/Object;J)I") {
            const _cava_optional_35: ?Value = try SunMiscUnsafe.getIntVolatile(context, vm, ref_arg(&args, 0), long_arg(&args, 1));
            return _cava_optional_35;
        }
        if method_is(method, "getObjectVolatile", "(Ljava/lang/Object;J)Ljava/lang/Object;") {
            const _cava_optional_34: ?Value = try SunMiscUnsafe.getObjectVolatile(context, vm, ref_arg(&args, 0), long_arg(&args, 1));
            return _cava_optional_34;
        }
        if method_is(method, "putObjectVolatile", "(Ljava/lang/Object;JLjava/lang/Object;)V") {
            const _cava_optional_33: ?Value = try SunMiscUnsafe.putObjectVolatile(context, vm, ref_arg(&args, 0), long_arg(&args, 1), ref_arg(&args, 2));
            return _cava_optional_33;
        }
        if method_is(method, "allocateMemory", "(J)J") {
            const _cava_optional_32: ?Value = try SunMiscUnsafe.allocateMemory(context, long_arg(&args, 0));
            return _cava_optional_32;
        }
        if method_is(method, "putLong", "(JJ)V") {
            const _cava_optional_31: ?Value = try SunMiscUnsafe.putLong(context, long_arg(&args, 0), long_arg(&args, 1));
            return _cava_optional_31;
        }
        if method_is(method, "getByte", "(J)B") {
            const _cava_optional_30: ?Value = try SunMiscUnsafe.getByte(context, long_arg(&args, 0));
            return _cava_optional_30;
        }
        if method_is(method, "freeMemory", "(J)V") {
            const _cava_optional_29: ?Value = try SunMiscUnsafe.freeMemory(context, long_arg(&args, 0));
            return _cava_optional_29;
        }
        if method_is(method, "ensureClassInitialized", "(Ljava/lang/Class;)V") {
            const _cava_optional_28: ?Value = try SunMiscUnsafe.ensureClassInitialized(context, ref_arg(&args, 0));
            return _cava_optional_28;
        }
        if method_is(method, "addressSize", "()I") {
            const _cava_optional_27: ?Value = try SunMiscUnsafe.addressSize(context);
            return _cava_optional_27;
        }
    }

    if class.name == "java/io/FileDescriptor" {
        if method_is(method, "initIDs", "()V") {
            const _cava_optional_26: ?Value = try JavaIoFileDescriptor.initIDs(context);
            return _cava_optional_26;
        }
    }

    if class.name == "java/io/PrintStream" {
        if method_is(method, "println", "(Ljava/lang/String;)V") {
            const _cava_optional_25: ?Value = try java_io_print_stream_println(context, vm, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_25;
        }
    }

    if class.name == "java/io/FileInputStream" {
        if method_is(method, "initIDs", "()V") {
            const _cava_optional_24: ?Value = try JavaIoFileInputStream.initIDs(context);
            return _cava_optional_24;
        }
    }

    if class.name == "java/io/FileOutputStream" {
        if method_is(method, "initIDs", "()V") {
            const _cava_optional_23: ?Value = try JavaIoFileOutputStream.initIDs(context);
            return _cava_optional_23;
        }
    }

    if class.name == "java/io/UnixFileSystem" {
        if method_is(method, "initIDs", "()V") {
            const _cava_optional_22: ?Value = try JavaIoUnixFileSystem.initIDs(context);
            return _cava_optional_22;
        }
        if method_is(method, "canonicalize0", "(Ljava/lang/String;)Ljava/lang/String;") {
            const _cava_optional_21: ?Value = try JavaIoUnixFileSystem.canonicalize0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_21;
        }
        if method_is(method, "getBooleanAttributes0", "(Ljava/io/File;)I") {
            const _cava_optional_20: ?Value = try JavaIoUnixFileSystem.getBooleanAttributes0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_20;
        }
        if method_is(method, "checkAccess0", "(Ljava/io/File;I)Z") {
            const _cava_optional_19: ?Value = try JavaIoUnixFileSystem.checkAccess0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1));
            return _cava_optional_19;
        }
        if method_is(method, "getLastModifiedTime0", "(Ljava/io/File;)J") {
            const _cava_optional_18: ?Value = try JavaIoUnixFileSystem.getLastModifiedTime0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_18;
        }
        if method_is(method, "getLength0", "(Ljava/io/File;)J") {
            const _cava_optional_17: ?Value = try JavaIoUnixFileSystem.getLength0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_17;
        }
        if method_is(method, "setPermission0", "(Ljava/io/File;IZZ)Z") {
            const _cava_optional_16: ?Value = try JavaIoUnixFileSystem.setPermission0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1), int_arg(&args, 2), int_arg(&args, 3));
            return _cava_optional_16;
        }
        if method_is(method, "createFileExclusively0", "(Ljava/lang/String;)Z") {
            const _cava_optional_15: ?Value = try JavaIoUnixFileSystem.createFileExclusively0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_15;
        }
        if method_is(method, "delete0", "(Ljava/io/File;)Z") {
            const _cava_optional_14: ?Value = try JavaIoUnixFileSystem.delete0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_14;
        }
        if method_is(method, "list0", "(Ljava/io/File;)[Ljava/lang/String;") {
            const _cava_optional_13: ?Value = try JavaIoUnixFileSystem.list0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_13;
        }
        if method_is(method, "createDirectory0", "(Ljava/io/File;)Z") {
            const _cava_optional_12: ?Value = try JavaIoUnixFileSystem.createDirectory0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_12;
        }
        if method_is(method, "rename0", "(Ljava/io/File;Ljava/io/File;)Z") {
            const _cava_optional_11: ?Value = try JavaIoUnixFileSystem.rename0(context, try receiver_ref(receiver), ref_arg(&args, 0), ref_arg(&args, 1));
            return _cava_optional_11;
        }
        if method_is(method, "setLastModifiedTime0", "(Ljava/io/File;J)Z") {
            const _cava_optional_10: ?Value = try JavaIoUnixFileSystem.setLastModifiedTime0(context, try receiver_ref(receiver), ref_arg(&args, 0), long_arg(&args, 1));
            return _cava_optional_10;
        }
        if method_is(method, "setReadOnly0", "(Ljava/io/File;)Z") {
            const _cava_optional_9: ?Value = try JavaIoUnixFileSystem.setReadOnly0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_9;
        }
        if method_is(method, "getSpace0", "(Ljava/io/File;I)J") {
            const _cava_optional_8: ?Value = try JavaIoUnixFileSystem.getSpace0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1));
            return _cava_optional_8;
        }
        if method_is(method, "getNameMax0", "(Ljava/lang/String;)J") {
            const _cava_optional_7: ?Value = try JavaIoUnixFileSystem.getNameMax0(context, try receiver_ref(receiver), ref_arg(&args, 0));
            return _cava_optional_7;
        }
    }

    if class.name == "java/util/concurrent/atomic/AtomicLong" {
        if method_is(method, "VMSupportsCS8", "()Z") {
            const _cava_optional_6: ?Value = try JavaUtilConcurrentAtomicAtomicLong.VMSupportsCS8(context);
            return _cava_optional_6;
        }
    }

    if class.name == "java/util/zip/ZipFile" {
        if method_is(method, "initIDs", "()V") {
            const _cava_optional_5: ?Value = try JavaUtilZipZipFile.initIDs(context);
            return _cava_optional_5;
        }
    }

    println("cava panic: unsupported native method");
    print("  class: ");
    println(class.name);
    print("  method: ");
    print(method.name);
    println(method.descriptor);
    panic("unsupported native method");
    throw InstructionError.unsupported_native;
}

fn seed_test_vm(vm: &VM, classes: []Class): void {
    var index: usize = 0;
    while index < classes.len() {
        vm.method_area.classes.push(classes[index].clone());
        index = index + 1;
    }
}

import { Constant } from .classfile;
import { Context } from .engine;
import { new_frame } from .engine;
import { VM } from .vm;
import { new_vm } from .vm;
import { Class, Field, InstructionError, Method, MethodAccessFlags, Reference, ReferenceKind, Value, byte_buffer, class_access_flags, field_access_flags, java_utf16_units_from_utf8, null_ref, raw_class_access, raw_field_access, raw_method_access } from .types;
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
    case .byte_value { return null_ref; }
    case .short_value { return null_ref; }
    case .char_value { return null_ref; }
    case .int_value { return null_ref; }
    case .long_value { return null_ref; }
    case .float_value { return null_ref; }
    case .double_value { return null_ref; }
    case .boolean_value { return null_ref; }
    case .return_address_value { return null_ref; }
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
        const mixed = (slot as u64) +% ((reference.generation as u64) *% 1103515245);
        return (mixed & 2147483647) as i32;
    }
    return 0;
}

fn set_system_static_ref(context: &Context, vm: &VM, name: string, descriptor: string, reference: Reference): result<void, InstructionError> {
    var classes = vm.method_area.classes[..];
    var index: usize = 0;
    while index < classes.len() {
        var class = &classes[index];
        if class.name == "java/lang/System" {
            if class.field_index(name, descriptor, true) is field_index_value {
                var fields = class.fields[..];
                const field = &fields[field_index_value as usize];
                class.static_vars[field.slot as usize] = .ref_value(reference);
                return .ok();
            }
            return .err(InstructionError.invalid_constant);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_native_class_index(context: &Context, vm: &VM, name: string): result<usize, InstructionError> {
    var classes = vm.method_area.classes[..];
    var index: usize = 0;
    while index < classes.len() {
        const class = &classes[index];
        if class.name == name {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn load_native_class_index(context: &Context, vm: &VM, name: string): result<usize, InstructionError> {
    switch vm.method_area.resolve_class(name) {
    case .ok(class_index) {
        return .ok(class_index);
    }
    case .err {}
    }
    return .err(InstructionError.invalid_constant);
}

fn find_or_load_native_class_index(context: &Context, vm: &VM, name: string): result<usize, InstructionError> {
    switch find_native_class_index(context, vm, name) {
    case .ok(class_index) { return .ok(class_index); }
    case .err {
        return load_native_class_index(context, vm, name);
    }
    }
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

fn set_instance_field(context: &Context, vm: &VM, reference: Reference, class_index: usize, name: string, descriptor: string, value: Value): result<void, InstructionError> {
    var classes = vm.method_area.classes[..];
    return set_instance_field_in(context, vm, classes, reference, class_index, name, descriptor, value);
}

fn set_instance_field_in(context: &Context, vm: &VM, classes: []Class, reference: Reference, class_index: usize, name: string, descriptor: string, value: Value): result<void, InstructionError> {
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
            return .err(InstructionError.invalid_constant);
        }
    }
    return .ok();
}

fn get_instance_field(context: &Context, vm: &VM, reference: Reference, class_index: usize, name: string, descriptor: string): result<Value, InstructionError> {
    var classes = vm.method_area.classes[..];
    return get_instance_field_in(context, vm, classes, reference, class_index, name, descriptor);
}

fn get_instance_field_in(context: &Context, vm: &VM, classes: []Class, reference: Reference, class_index: usize, name: string, descriptor: string): result<Value, InstructionError> {
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
            return .ok(value);
        }
    }
    return .err(InstructionError.invalid_constant);
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

fn java_string_bytes(context: &Context, vm: &VM, reference: Reference): result<[:]u8, InstructionError> {
    var value_option = vm.heap.string_bytes(reference);
    if take value_option is value {
        const bytes = copy value.value;
        drop value;
        return .ok(bytes);
    }
    const string_class_index = try find_native_class_index(context, vm, "java/lang/String");
    const value_field = try get_instance_field(context, vm, reference, string_class_index, "value", "[C");
    switch value_field {
    case .ref_value(chars_reference) {
        if vm.heap.array_length(chars_reference) is length {
            var bytes: List<u8> = [];
            var index: usize = 0;
            while index < length {
                if vm.heap.get_element(chars_reference, index) is element {
                    switch element {
                    case .char_value(ch) { bytes.push(ch as u8); }
                    case .byte_value(ch) { bytes.push(ch as u8); }
                    else {
                        drop bytes;
                        return .err(InstructionError.invalid_constant);
                    }
                    }
                } else {
                    drop bytes;
                    return .err(InstructionError.invalid_constant);
                }
                index = index + 1;
            }
            const out = byte_buffer(bytes[..]);
            drop bytes;
            return .ok(out);
        }
    }
    else { return .err(InstructionError.invalid_constant); }
    }
    return .err(InstructionError.invalid_constant);
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
                case .ref_value(type_reference) {
                    if type_reference.equals(reference) {
                        return true;
                    }
                }
                case .byte_value {}
                case .short_value {}
                case .char_value {}
                case .int_value {}
                case .long_value {}
                case .float_value {}
                case .double_value {}
                case .boolean_value {}
                case .return_address_value {}
                }
            }
        }
        class_index = class_index + 1;
    }
    return false;
}

fn ensure_class_object(context: &Context, vm: &VM, class_index: usize): result<Reference, InstructionError> {
    const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
    var classes = vm.method_area.classes[..];
    const class_class = &classes[class_class_index];
    var class = &classes[class_index];
    if class.class_object.is_null() {
        class.class_object = vm.heap.allocate_object(class_class_index, class_class);
    }
    return .ok(class.class_object);
}

fn descriptor_class_object(context: &Context, vm: &VM, descriptor: []const u8): result<Reference, InstructionError> {
    if descriptor.len() == 1 {
        const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
        var classes = vm.method_area.classes[..];
        return .ok(vm.heap.allocate_object(class_class_index, &classes[class_class_index]));
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
        const found = find_or_load_native_class_index(context, vm, name);
        drop name;
        switch found {
        case .ok(class_index) { return ensure_class_object(context, vm, class_index); }
        case .err {}
        }
    }
    return .err(InstructionError.invalid_constant);
}

fn new_java_reflect_field(context: &Context, vm: &VM, declaring_class: Reference, field: &Field): result<Reference, InstructionError> {
    const field_class_index = try find_or_load_native_class_index(context, vm, "java/lang/reflect/Field");
    var classes = vm.method_area.classes[..];
    const reference = vm.heap.allocate_object_with_hierarchy(field_class_index, classes);
    const type_reference = try descriptor_class_object(context, vm, field.descriptor.bytes());
    var name_reference = null_ref;
    if java_string(context, vm, field.name.bytes()) is actual_name {
        name_reference = actual_name;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var signature_reference = null_ref;
    if java_string(context, vm, field.descriptor.bytes()) is actual_signature {
        signature_reference = actual_signature;
    } else {
        return .err(InstructionError.invalid_constant);
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
    return .ok(reference);
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

fn new_class_array_for_method_parameters(context: &Context, vm: &VM, method: &Method): result<Reference, InstructionError> {
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
    return .ok(array);
}

fn new_java_reflect_constructor(context: &Context, vm: &VM, declaring_class: Reference, method: &Method, slot: usize): result<Reference, InstructionError> {
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
        return .ok(reference);
    }
    return .err(InstructionError.invalid_constant);
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

fn java_string_buffer(context: &Context, vm: &VM, data: [:]u8): result<Reference, InstructionError> {
    var bytes = data;
    var classes = vm.method_area.classes[..];
    if find_loaded_class_index(classes, "java/lang/String") is string_class_index {
        return .ok(vm.heap.intern_string_buffer(string_class_index, &classes[string_class_index], bytes));
    }
    drop bytes;
    return .err(InstructionError.invalid_constant);
}

fn concat_java_string(context: &Context, vm: &VM, left_reference: Reference, right_reference: Reference): result<Reference, InstructionError> {
    var classes = vm.method_area.classes[..];
    if find_loaded_class_index(classes, "java/lang/String") is string_class_index {
        return .ok(vm.heap.concat_strings(string_class_index, &classes[string_class_index], left_reference, right_reference));
    }
    return .err(InstructionError.invalid_constant);
}

fn print_java_string(context: &Context, vm: &VM, reference: Reference): void {
    var value_option = vm.heap.string_bytes(reference);
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

fn new_thread_group(context: &Context, vm: &VM): result<Reference, InstructionError> {
    switch find_or_load_native_class_index(context, vm, "java/lang/ThreadGroup") {
    case .ok(group_class_index) {
        var classes = vm.method_area.classes[..];
        const group = vm.heap.allocate_object(group_class_index, &classes[group_class_index]);
        if java_string(context, vm, "main".bytes()) is group_name {
            try set_instance_field_in(context, vm, classes, group, group_class_index, "name", "Ljava/lang/String;", .ref_value(group_name));
        }
        return .ok(group);
    }
    case .err {}
    }
    return .ok(null_ref);
}

fn new_java_lang_thread(context: &Context, vm: &VM): result<Reference, InstructionError> {
    if vm.heap.current_thread_ref() is cached {
        if vm.heap.has_object(cached) {
            return .ok(cached);
        }
    }
    switch find_or_load_native_class_index(context, vm, "java/lang/Thread") {
    case .ok(thread_class_index) {
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
        return .ok(thread);
    }
    case .err {}
    }
    return .err(InstructionError.invalid_constant);
}

fn arraycopy(context: &Context, vm: &VM, src: Reference, src_pos: i32, dest: Reference, dest_pos: i32, length: i32): result<void, InstructionError> {
    if src_pos < 0 or dest_pos < 0 or length < 0 {
        return .err(InstructionError.invalid_constant);
    }
    const src_start = src_pos as usize;
    const dest_start = dest_pos as usize;
    const count = length as usize;
    var src_len: usize = 0;
    if vm.heap.array_length(src) is actual_src_len {
        src_len = actual_src_len;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    var dest_len: usize = 0;
    if vm.heap.array_length(dest) is actual_dest_len {
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
            if vm.heap.get_element(src, src_start + index) is actual_value {
                value = actual_value;
            } else {
                return .err(InstructionError.invalid_constant);
            }
            if !vm.heap.set_element(dest, dest_start + index, value) {
                return .err(InstructionError.invalid_constant);
            }
        }
        return .ok();
    }

    var index: usize = 0;
    while index < count {
        var value: Value = .int_value(0);
        if vm.heap.get_element(src, src_start + index) is actual_value {
            value = actual_value;
        } else {
            return .err(InstructionError.invalid_constant);
        }
        if !vm.heap.set_element(dest, dest_start + index, value) {
            return .err(InstructionError.invalid_constant);
        }
        index = index + 1;
    }
    return .ok();
}

fn clone_array(context: &Context, vm: &VM, receiver: Reference, class_index: usize): result<Reference, InstructionError> {
    var length: usize = 0;
    if vm.heap.array_length(receiver) is actual_length {
        length = actual_length;
    } else {
        return .err(InstructionError.invalid_constant);
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
            return .err(InstructionError.invalid_constant);
        }
        if !vm.heap.set_element(clone, index, value) {
            return .err(InstructionError.invalid_constant);
        }
        index = index + 1;
    }
    return .ok(clone);
}

fn clone_object(context: &Context, vm: &VM, receiver: Reference, class_index: usize): result<Reference, InstructionError> {
    var classes = vm.method_area.classes[..];
    const class = &classes[class_index];
    const clone = vm.heap.allocate_object(class_index, class);
    var slot: u16 = 0;
    while slot < class.instance_vars {
        var value: Value = .int_value(0);
        if vm.heap.get_field(receiver, slot) is actual_value {
            value = actual_value;
        } else {
            return .err(InstructionError.invalid_constant);
        }
        if !vm.heap.set_field(clone, slot, value) {
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

    pub fn setIn0(context: &Context, vm: &VM, input: Reference): result<?Value, InstructionError> {
        try set_system_static_ref(context, vm, "in", "Ljava/io/InputStream;", input);
        return .ok(none);
    }

    pub fn setOut0(context: &Context, vm: &VM, output: Reference): result<?Value, InstructionError> {
        try set_system_static_ref(context, vm, "out", "Ljava/io/PrintStream;", output);
        return .ok(none);
    }

    pub fn setErr0(context: &Context, vm: &VM, error_stream: Reference): result<?Value, InstructionError> {
        try set_system_static_ref(context, vm, "err", "Ljava/io/PrintStream;", error_stream);
        return .ok(none);
    }

    pub fn arraycopy(context: &Context, vm: &VM, src: Reference, src_pos: i32, dest: Reference, dest_pos: i32, length: i32): result<?Value, InstructionError> {
        try arraycopy(context, vm, src, src_pos, dest, dest_pos, length);
        return .ok(none);
    }

    pub fn identityHashCode(context: &Context, reference: Reference): result<?Value, InstructionError> {
        return return_value(.int_value(identity_hash_code(reference)));
    }

    pub fn currentTimeMillis(context: &Context): result<?Value, InstructionError> {
        switch now_ns() {
        case .ok(ns) { return return_value(.long_value(ns_to_ms(ns))); }
        case .err {
            return .err(InstructionError.invalid_constant);
        }
        }
    }

    pub fn nanoTime(context: &Context): result<?Value, InstructionError> {
        switch monotonic_ns() {
        case .ok(ns) { return return_value(.long_value(ns)); }
        case .err {
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

    pub fn getProperty(context: &Context, vm: &VM, key: Reference): result<?Value, InstructionError> {
        const ignored_key = key;
        if java_string(context, vm, "Cava".bytes()) is value {
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

    pub fn getClass(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if vm.heap.object_class_index(receiver) is actual_class_index {
            const ignored_class = &classes[actual_class_index];
            return return_value(.ref_value(try ensure_class_object(context, vm, actual_class_index)));
        }
        if vm.heap.array_class_index(receiver) is actual_class_index {
            const ignored_class = &classes[actual_class_index];
            return return_value(.ref_value(try ensure_class_object(context, vm, actual_class_index)));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn clone(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        if vm.heap.object_class_index(receiver) is actual_class_index {
            return return_value(.ref_value(try clone_object(context, vm, receiver, actual_class_index)));
        }
        if vm.heap.array_class_index(receiver) is actual_class_index {
            return return_value(.ref_value(try clone_array(context, vm, receiver, actual_class_index)));
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

    pub fn getPrimitiveClass(context: &Context, vm: &VM, name: Reference): result<?Value, InstructionError> {
        const ignored_name = name;
        const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
        var classes = vm.method_area.classes[..];
        const reference = vm.heap.allocate_object(class_class_index, &classes[class_class_index]);
        return return_value(.ref_value(reference));
    }

    pub fn desiredAssertionStatus0(context: &Context, class_object: Reference): result<?Value, InstructionError> {
        const ignored_class_object = class_object;
        return return_value(.boolean_value(0));
    }

    pub fn getDeclaredFields0(context: &Context, vm: &VM, receiver: Reference, public_only: i32): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is declaring_class_index {
            const declaring_class = &classes[declaring_class_index];
            var fields = declaring_class.fields[..];
            var field_array_class_index: usize = 0;
            switch find_or_load_native_class_index(context, vm, "[Ljava/lang/reflect/Field;") {
            case .ok(index) { field_array_class_index = index; }
            case .err {
                println("cava native error: missing [Ljava/lang/reflect/Field; array class");
                return .err(InstructionError.invalid_constant);
            }
            }
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
                    const field_object = new_java_reflect_field(context, vm, receiver, field);
                    switch field_object {
                    case .ok(actual_field_object) {
                        const ignored_set = vm.heap.set_element(array, out_index, .ref_value(actual_field_object));
                    }
                    case .err {
                        print("cava native error: cannot create java/lang/reflect/Field for ");
                        print(declaring_class.name);
                        print(".");
                        println(field.name);
                        return .err(InstructionError.invalid_constant);
                    }
                    }
                    out_index = out_index + 1;
                }
                field_index = field_index + 1;
            }
            return return_value(.ref_value(array));
        }
        println("cava native error: Class.getDeclaredFields0 receiver has no class mapping");
        return .err(InstructionError.invalid_constant);
    }

    pub fn getDeclaredConstructors0(context: &Context, vm: &VM, receiver: Reference, public_only: i32): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is declaring_class_index {
            const declaring_class = &classes[declaring_class_index];
            var methods = declaring_class.methods[..];
            var constructor_array_class_index: usize = 0;
            switch find_or_load_native_class_index(context, vm, "[Ljava/lang/reflect/Constructor;") {
            case .ok(index) { constructor_array_class_index = index; }
            case .err {
                println("cava native error: missing [Ljava/lang/reflect/Constructor; array class");
                return .err(InstructionError.invalid_constant);
            }
            }
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
                    const constructor_object = new_java_reflect_constructor(context, vm, receiver, method, method_index);
                    switch constructor_object {
                    case .ok(actual_constructor) {
                        const ignored_set = vm.heap.set_element(array, out_index, .ref_value(actual_constructor));
                    }
                    case .err {
                        print("cava native error: cannot create java/lang/reflect/Constructor for ");
                        println(declaring_class.name);
                        return .err(InstructionError.invalid_constant);
                    }
                    }
                    out_index = out_index + 1;
                }
                method_index = method_index + 1;
            }
            return return_value(.ref_value(array));
        }
        println("cava native error: Class.getDeclaredConstructors0 receiver has no class mapping");
        return .err(InstructionError.invalid_constant);
    }

    pub fn isPrimitive(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        if is_primitive_class_object(context, vm, receiver) {
            return return_value(.boolean_value(1));
        }
        return return_value(.boolean_value(0));
    }

    pub fn isAssignableFrom(context: &Context, vm: &VM, receiver: Reference, other: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is expected_index {
            if find_class_object_index_in(classes, other) is actual_index {
                if native_reference_assignable_to(classes, actual_index, expected_index) {
                    return return_value(.boolean_value(1));
                }
                return return_value(.boolean_value(0));
            }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getName0(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if java_string(context, vm, class.name.bytes()) is value {
                return return_value(.ref_value(value));
            }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn forName0(context: &Context, vm: &VM, name: Reference, initialize: i32, loader: Reference, caller: Reference): result<?Value, InstructionError> {
        const ignored_initialize = initialize;
        const ignored_loader = loader;
        const ignored_caller = caller;
        const name_bytes = try java_string_bytes(context, vm, name);
        const class_name = class_name_from_java_name(name_bytes[..]);
        drop name_bytes;
        switch find_or_load_native_class_index(context, vm, class_name) {
        case .ok(class_index) {
            const reference = try ensure_class_object(context, vm, class_index);
            drop class_name;
            return return_value(.ref_value(reference));
        }
        case .err {
            print("cava native error: Class.forName0 missing class ");
            println(class_name);
            drop class_name;
            return .err(InstructionError.invalid_constant);
        }
        }
    }

    pub fn initClassName(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        return JavaLangClass.getName0(context, vm, receiver);
    }

    pub fn descriptorString(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if java_string(context, vm, class.descriptor.bytes()) is value {
                return return_value(.ref_value(value));
            }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn isArray(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if class.is_array {
                return return_value(.boolean_value(1));
            }
            return return_value(.boolean_value(0));
        }
        return return_value(.boolean_value(0));
    }

    pub fn getComponentType(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if !class.is_array {
                return return_value(.ref_value(null_ref));
            }
            const component = class.component_type.bytes();
            if component.len() > 2 and component[0] == 'L' {
                const name = string.from(component[1..component.len() - 1]);
                switch find_or_load_native_class_index(context, vm, name) {
                case .ok(component_index) {
                    const reference = try ensure_class_object(context, vm, component_index);
                    drop name;
                    return return_value(.ref_value(reference));
                }
                case .err {
                    drop name;
                }
                }
            }
            if component.len() > 0 and component[0] == '[' {
                const name = string.from(component);
                switch find_or_load_native_class_index(context, vm, name) {
                case .ok(component_index) {
                    const reference = try ensure_class_object(context, vm, component_index);
                    drop name;
                    return return_value(.ref_value(reference));
                }
                case .err {
                    drop name;
                }
                }
            }
            const class_class_index = try find_or_load_native_class_index(context, vm, "java/lang/Class");
            var class_class = &classes[class_class_index];
            if class_class.class_object.is_null() {
                class_class.class_object = vm.heap.allocate_object(class_class_index, class_class);
            }
            return return_value(.ref_value(class_class.class_object));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn isInterface(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            if class.is_interface() {
                return return_value(.boolean_value(1));
            }
            return return_value(.boolean_value(0));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getModifiers(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            return return_value(.int_value(raw_class_access(class.access_flags) as i32));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getSuperclass(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, receiver) is class_index {
            const class = &classes[class_index];
            const super_class = class.super_class;
            if super_class == "" {
                return return_value(.ref_value(null_ref));
            }
            if find_loaded_class_index(classes, super_class) is super_index {
                return return_value(.ref_value(try ensure_class_object(context, vm, super_index)));
            }
            return return_value(.ref_value(null_ref));
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getClassAccessFlagsRaw0(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
        return JavaLangClass.getModifiers(context, vm, receiver);
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

struct JavaLangReflectArray {
    pub fn newArray(context: &Context, vm: &VM, component_class: Reference, length: i32): result<?Value, InstructionError> {
        if length < 0 {
            return .err(InstructionError.invalid_constant);
        }
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, component_class) is component_index {
            const component = &classes[component_index];
            const descriptor = array_descriptor_for_component(component);
            var array_class_index: usize = 0;
            switch find_or_load_native_class_index(context, vm, descriptor) {
            case .ok(found_index) {
                array_class_index = found_index;
            }
            case .err {
                drop descriptor;
                return .err(InstructionError.invalid_constant);
            }
            }
            const reference = vm.heap.allocate_array(array_class_index, component.descriptor.bytes(), length as usize);
            drop descriptor;
            return return_value(.ref_value(reference));
        }
        return .err(InstructionError.invalid_constant);
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

fn java_lang_string_builder_append(context: &Context, vm: &VM, receiver: Reference, value: Reference): result<?Value, InstructionError> {
    const slot: u16 = 0;
    var current_ref = null_ref;
    if vm.heap.get_field(receiver, slot) is current_value {
        current_ref = value_ref_or_null(current_value);
    } else {
        return .err(InstructionError.invalid_constant);
    }
    const combined_ref = try concat_java_string(context, vm, current_ref, value);
    if !vm.heap.set_field(receiver, slot, .ref_value(combined_ref)) {
        return .err(InstructionError.invalid_constant);
    }
    const out: Value = .ref_value(Reference {
        kind: receiver.kind,
        slot: receiver.slot,
        generation: receiver.generation,
    });
    return .ok(out);
}

fn java_lang_string_builder_init(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
    return .ok(none);
}

fn java_lang_string_builder_to_string(context: &Context, vm: &VM, receiver: Reference): result<?Value, InstructionError> {
    const slot: u16 = 0;
    if vm.heap.get_field(receiver, slot) is current_value {
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

fn java_io_print_stream_println(context: &Context, vm: &VM, receiver: Reference, value: Reference): result<?Value, InstructionError> {
    print_java_string(context, vm, value);
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

    pub fn currentThread(context: &Context, vm: &VM): result<?Value, InstructionError> {
        return return_value(.ref_value(try new_java_lang_thread(context, vm)));
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
    pub fn getCallerClass(context: &Context, vm: &VM): result<?Value, InstructionError> {
        return return_value(.ref_value(try ensure_class_object(context, vm, context.class_index)));
    }

    pub fn getClassAccessFlags(context: &Context, vm: &VM, class_object: Reference): result<?Value, InstructionError> {
        var classes = vm.method_area.classes[..];
        if find_class_object_index_in(classes, class_object) is class_index {
            const class = &classes[class_index];
            return return_value(.int_value(raw_class_access(class.access_flags) as i32));
        }
        return .err(InstructionError.invalid_constant);
    }
}

struct JdkInternalReflectReflection {
    pub fn getCallerClass(context: &Context, vm: &VM): result<?Value, InstructionError> {
        return SunReflectReflection.getCallerClass(context, vm);
    }

    pub fn getClassAccessFlags(context: &Context, vm: &VM, class_object: Reference): result<?Value, InstructionError> {
        return SunReflectReflection.getClassAccessFlags(context, vm, class_object);
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

    pub fn objectFieldOffset(context: &Context, vm: &VM, field: Reference): result<?Value, InstructionError> {
        const field_class_index = try find_or_load_native_class_index(context, vm, "java/lang/reflect/Field");
        var classes = vm.method_area.classes[..];
        const clazz_value = try get_instance_field_in(context, vm, classes, field, field_class_index, "clazz", "Ljava/lang/Class;");
        const slot_value = try get_instance_field_in(context, vm, classes, field, field_class_index, "slot", "I");
        switch clazz_value {
        case .ref_value(clazz) {
            classes = vm.method_area.classes[..];
            if find_class_object_index_in(classes, clazz) is declaring_class_index {
                const declaring_class = &classes[declaring_class_index];
                switch slot_value {
                case .int_value(slot) {
                    if native_field_runtime_slot(classes, declaring_class_index, declaring_class.name, slot as u16) is runtime_slot {
                        return return_value(.long_value(runtime_slot as i64));
                    }
                    return .err(InstructionError.invalid_constant);
                }
                else { return .err(InstructionError.invalid_constant); }
                }
            }
            return .err(InstructionError.invalid_constant);
        }
        else { return .err(InstructionError.invalid_constant); }
        }
    }

    pub fn compareAndSwapInt(context: &Context, vm: &VM, object: Reference, offset: i64, expected: i32, value: i32): result<?Value, InstructionError> {
        if offset < 0 {
            return .err(InstructionError.invalid_constant);
        }
        if object.kind == ReferenceKind.array {
            if vm.heap.get_element(object, offset as usize) is current {
                switch current {
                case .int_value(actual) {
                    if actual == expected {
                        const ignored_set = vm.heap.set_element(object, offset as usize, .int_value(value));
                        return return_value(.boolean_value(1));
                    }
                    return return_value(.boolean_value(0));
                }
                else { return return_value(.boolean_value(0)); }
                }
            }
            return .err(InstructionError.invalid_constant);
        }
        if vm.heap.get_field(object, offset as u16) is current_field {
            switch current_field {
            case .int_value(actual) {
                if actual == expected {
                    const ignored_set = vm.heap.set_field(object, offset as u16, .int_value(value));
                    return return_value(.boolean_value(1));
                }
                return return_value(.boolean_value(0));
            }
            case .boolean_value(actual) {
                if actual as i32 == expected {
                    const ignored_set = vm.heap.set_field(object, offset as u16, .boolean_value(value as u8));
                    return return_value(.boolean_value(1));
                }
                return return_value(.boolean_value(0));
            }
            else { return return_value(.boolean_value(0)); }
            }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn compareAndSwapLong(context: &Context, object: Reference, offset: i64, expected: i64, value: i64): result<?Value, InstructionError> {
        const ignored_object = object;
        const ignored_offset = offset;
        const ignored_expected = expected;
        const ignored_value = value;
        return return_value(.boolean_value(1));
    }

    pub fn compareAndSwapObject(context: &Context, vm: &VM, object: Reference, offset: i64, expected: Reference, value: Reference): result<?Value, InstructionError> {
        const ignored_expected = expected;
        if object.kind == ReferenceKind.array and offset >= 0 {
            const ignored_set = vm.heap.set_element(object, offset as usize, .ref_value(value));
        } else if offset >= 0 {
            const ignored_set = vm.heap.set_field(object, offset as u16, .ref_value(value));
        }
        return return_value(.boolean_value(1));
    }

    pub fn getIntVolatile(context: &Context, vm: &VM, object: Reference, offset: i64): result<?Value, InstructionError> {
        if offset < 0 {
            return .err(InstructionError.invalid_constant);
        }
        if object.kind == ReferenceKind.array {
            if vm.heap.get_element(object, offset as usize) is value {
                return return_value(value);
            }
        } else if vm.heap.get_field(object, offset as u16) is value {
            return return_value(value);
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn getObjectVolatile(context: &Context, vm: &VM, object: Reference, offset: i64): result<?Value, InstructionError> {
        if object.kind == ReferenceKind.array and offset >= 0 {
            if vm.heap.get_element(object, offset as usize) is value {
                return return_value(value);
            }
        } else if offset >= 0 {
            if vm.heap.get_field(object, offset as u16) is value {
                return return_value(value);
            }
        }
        return return_value(.ref_value(null_ref));
    }

    pub fn putObjectVolatile(context: &Context, vm: &VM, object: Reference, offset: i64, value: Reference): result<?Value, InstructionError> {
        if object.kind == ReferenceKind.array and offset >= 0 {
            const ignored_set = vm.heap.set_element(object, offset as usize, .ref_value(value));
        } else if offset >= 0 {
            const ignored_set = vm.heap.set_field(object, offset as u16, .ref_value(value));
        }
        return .ok(none);
    }

    pub fn allocateMemory(context: &Context, size: i64): result<?Value, InstructionError> {
        const ignored_size = size;
        return return_value(.long_value(1));
    }

    pub fn putLong(context: &Context, address: i64, value: i64): result<?Value, InstructionError> {
        const ignored_address = address;
        const ignored_value = value;
        return .ok(none);
    }

    pub fn getByte(context: &Context, address: i64): result<?Value, InstructionError> {
        const ignored_address = address;
        return return_value(.byte_value(8));
    }

    pub fn freeMemory(context: &Context, address: i64): result<?Value, InstructionError> {
        const ignored_address = address;
        return .ok(none);
    }

    pub fn ensureClassInitialized(context: &Context, class: Reference): result<?Value, InstructionError> {
        const ignored_class = class;
        return .ok(none);
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

fn method_is(method: &Method, name: string, descriptor: string): bool {
    return method.name == name and method.descriptor == descriptor;
}

pub fn execute_native_method(context: &Context, vm: &VM, class_index: usize, method_index: usize, receiver: ?Reference, arguments: List<Value>): result<?Value, InstructionError> {
    var args = arguments;
    var classes = vm.method_area.classes[..];
    const class = &classes[class_index];
    var methods = class.methods[..];
    const method = &methods[method_index];
    if class.name == "java/lang/System" {
        if method_is(method, "registerNatives", "()V") { return JavaLangSystem.registerNatives(context); }
        if method_is(method, "setIn0", "(Ljava/io/InputStream;)V") { return JavaLangSystem.setIn0(context, vm, ref_arg(&args, 0)); }
        if method_is(method, "setOut0", "(Ljava/io/PrintStream;)V") { return JavaLangSystem.setOut0(context, vm, ref_arg(&args, 0)); }
        if method_is(method, "setErr0", "(Ljava/io/PrintStream;)V") { return JavaLangSystem.setErr0(context, vm, ref_arg(&args, 0)); }
        if method_is(method, "currentTimeMillis", "()J") { return JavaLangSystem.currentTimeMillis(context); }
        if method_is(method, "nanoTime", "()J") { return JavaLangSystem.nanoTime(context); }
        if method_is(method, "arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V") { return JavaLangSystem.arraycopy(context, vm, ref_arg(&args, 0), int_arg(&args, 1), ref_arg(&args, 2), int_arg(&args, 3), int_arg(&args, 4)); }
        if method_is(method, "identityHashCode", "(Ljava/lang/Object;)I") { return JavaLangSystem.identityHashCode(context, ref_arg(&args, 0)); }
        if method_is(method, "mapLibraryName", "(Ljava/lang/String;)Ljava/lang/String;") { return JavaLangSystem.mapLibraryName(context, ref_arg(&args, 0)); }
        if method_is(method, "initProperties", "(Ljava/util/Properties;)Ljava/util/Properties;") { return JavaLangSystem.initProperties(context, ref_arg(&args, 0)); }
        if method_is(method, "getProperty", "(Ljava/lang/String;)Ljava/lang/String;") { return JavaLangSystem.getProperty(context, vm, ref_arg(&args, 0)); }
    }

    if class.name == "java/lang/Object" {
        if method_is(method, "<init>", "()V") { return JavaLangObject.init(context, try receiver_ref(receiver)); }
        if method_is(method, "registerNatives", "()V") { return JavaLangObject.registerNatives(context); }
        if method_is(method, "hashCode", "()I") { return JavaLangObject.hashCode(context, try receiver_ref(receiver)); }
        if method_is(method, "getClass", "()Ljava/lang/Class;") { return JavaLangObject.getClass(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "clone", "()Ljava/lang/Object;") { return JavaLangObject.clone(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "notify", "()V") { return JavaLangObject.notify(context, try receiver_ref(receiver)); }
        if method_is(method, "notifyAll", "()V") { return JavaLangObject.notifyAll(context, try receiver_ref(receiver)); }
        if method_is(method, "wait", "(J)V") { return JavaLangObject.wait(context, try receiver_ref(receiver), long_arg(&args, 0)); }
    }

    if class.name == "java/lang/String" {
        if method_is(method, "intern", "()Ljava/lang/String;") { return JavaLangString.intern(context, try receiver_ref(receiver)); }
    }

    if class.name == "java/lang/StringBuilder" {
        if method_is(method, "<init>", "()V") { return java_lang_string_builder_init(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;") { return java_lang_string_builder_append(context, vm, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "toString", "()Ljava/lang/String;") { return java_lang_string_builder_to_string(context, vm, try receiver_ref(receiver)); }
    }

    if class.name == "java/lang/Class" {
        if method_is(method, "registerNatives", "()V") { return JavaLangClass.registerNatives(context); }
        if method_is(method, "getPrimitiveClass", "(Ljava/lang/String;)Ljava/lang/Class;") { return JavaLangClass.getPrimitiveClass(context, vm, ref_arg(&args, 0)); }
        if method_is(method, "desiredAssertionStatus0", "(Ljava/lang/Class;)Z") { return JavaLangClass.desiredAssertionStatus0(context, ref_arg(&args, 0)); }
        if method_is(method, "getDeclaredFields0", "(Z)[Ljava/lang/reflect/Field;") { return JavaLangClass.getDeclaredFields0(context, vm, try receiver_ref(receiver), int_arg(&args, 0)); }
        if method_is(method, "getDeclaredConstructors0", "(Z)[Ljava/lang/reflect/Constructor;") { return JavaLangClass.getDeclaredConstructors0(context, vm, try receiver_ref(receiver), int_arg(&args, 0)); }
        if method_is(method, "isPrimitive", "()Z") { return JavaLangClass.isPrimitive(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "forName0", "(Ljava/lang/String;ZLjava/lang/ClassLoader;Ljava/lang/Class;)Ljava/lang/Class;") { return JavaLangClass.forName0(context, vm, ref_arg(&args, 0), int_arg(&args, 1), ref_arg(&args, 2), ref_arg(&args, 3)); }
        if method_is(method, "isAssignableFrom", "(Ljava/lang/Class;)Z") { return JavaLangClass.isAssignableFrom(context, vm, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "getName0", "()Ljava/lang/String;") { return JavaLangClass.getName0(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "initClassName", "()Ljava/lang/String;") { return JavaLangClass.initClassName(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "descriptorString", "()Ljava/lang/String;") { return JavaLangClass.descriptorString(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "isArray", "()Z") { return JavaLangClass.isArray(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "getComponentType", "()Ljava/lang/Class;") { return JavaLangClass.getComponentType(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "isInterface", "()Z") { return JavaLangClass.isInterface(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "getModifiers", "()I") { return JavaLangClass.getModifiers(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "getSuperclass", "()Ljava/lang/Class;") { return JavaLangClass.getSuperclass(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "getClassAccessFlagsRaw0", "()I") { return JavaLangClass.getClassAccessFlagsRaw0(context, vm, try receiver_ref(receiver)); }
        if method_is(method, "getClassFileVersion0", "()I") { return JavaLangClass.getClassFileVersion0(context, try receiver_ref(receiver)); }
        if method_is(method, "isHidden", "()Z") { return JavaLangClass.isHidden(context, try receiver_ref(receiver)); }
        if method_is(method, "isRecord0", "()Z") { return JavaLangClass.isRecord0(context, try receiver_ref(receiver)); }
    }

    if class.name == "java/lang/ClassLoader" {
        if method_is(method, "registerNatives", "()V") { return JavaLangClassLoader.registerNatives(context); }
        if method_is(method, "findBuiltinLib", "(Ljava/lang/String;)Ljava/lang/String;") { return JavaLangClassLoader.findBuiltinLib(context, ref_arg(&args, 0)); }
    }

    if class.name == "java/lang/ClassLoader$NativeLibrary" {
        if method_is(method, "load", "(Ljava/lang/String;Z)V") { return JavaLangClassLoaderNativeLibrary.load(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1)); }
    }

    if class.name == "java/lang/reflect/Array" {
        if method_is(method, "newArray", "(Ljava/lang/Class;I)Ljava/lang/Object;") { return JavaLangReflectArray.newArray(context, vm, ref_arg(&args, 0), int_arg(&args, 1)); }
    }

    if class.name == "java/lang/Package" {
        if method_is(method, "getSystemPackage0", "(Ljava/lang/String;)Ljava/lang/String;") { return JavaLangPackage.getSystemPackage0(context, ref_arg(&args, 0)); }
    }

    if class.name == "java/lang/Float" {
        if method_is(method, "floatToRawIntBits", "(F)I") { return JavaLangFloat.floatToRawIntBits(context, float_arg(&args, 0)); }
        if method_is(method, "intBitsToFloat", "(I)F") { return JavaLangFloat.intBitsToFloat(context, int_arg(&args, 0)); }
    }

    if class.name == "java/lang/Double" {
        if method_is(method, "doubleToRawLongBits", "(D)J") { return JavaLangDouble.doubleToRawLongBits(context, double_arg(&args, 0)); }
        if method_is(method, "longBitsToDouble", "(J)D") { return JavaLangDouble.longBitsToDouble(context, long_arg(&args, 0)); }
    }

    if class.name == "java/lang/Thread" {
        if method_is(method, "registerNatives", "()V") { return JavaLangThread.registerNatives(context); }
        if method_is(method, "currentThread", "()Ljava/lang/Thread;") { return JavaLangThread.currentThread(context, vm); }
        if method_is(method, "isAlive", "()Z") { return JavaLangThread.isAlive(context, try receiver_ref(receiver)); }
        if method_is(method, "setPriority0", "(I)V") { return JavaLangThread.setPriority0(context, try receiver_ref(receiver), int_arg(&args, 0)); }
        if method_is(method, "start0", "()V") { return JavaLangThread.start0(context, try receiver_ref(receiver)); }
        if method_is(method, "sleep", "(J)V") { return JavaLangThread.sleep(context, long_arg(&args, 0)); }
        if method_is(method, "interrupt0", "()V") { return JavaLangThread.interrupt0(context, try receiver_ref(receiver)); }
        if method_is(method, "isInterrupted", "(Z)Z") { return JavaLangThread.isInterrupted(context, try receiver_ref(receiver), int_arg(&args, 0)); }
        if method_is(method, "holdsLock", "(Ljava/lang/Object;)Z") { return JavaLangThread.holdsLock(context, ref_arg(&args, 0)); }
        if method_is(method, "yield0", "()V") { return JavaLangThread.yield0(context); }
        if method_is(method, "clearInterruptEvent", "()V") { return JavaLangThread.clearInterruptEvent(context); }
        if method_is(method, "setNativeName", "(Ljava/lang/String;)V") { return JavaLangThread.setNativeName(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
    }

    if class.name == "java/lang/Throwable" {
        if method_is(method, "getStackTraceDepth", "()I") { return JavaLangThrowable.getStackTraceDepth(context, try receiver_ref(receiver)); }
        if method_is(method, "fillInStackTrace", "(I)Ljava/lang/Throwable;") { return JavaLangThrowable.fillInStackTrace(context, try receiver_ref(receiver), int_arg(&args, 0)); }
    }

    if class.name == "java/lang/Runtime" {
        if method_is(method, "availableProcessors", "()I") { return JavaLangRuntime.availableProcessors(context, try receiver_ref(receiver)); }
        if method_is(method, "freeMemory", "()J") { return JavaLangRuntime.freeMemory(context, try receiver_ref(receiver)); }
        if method_is(method, "totalMemory", "()J") { return JavaLangRuntime.totalMemory(context, try receiver_ref(receiver)); }
        if method_is(method, "maxMemory", "()J") { return JavaLangRuntime.maxMemory(context, try receiver_ref(receiver)); }
        if method_is(method, "gc", "()V") { return JavaLangRuntime.gc(context, try receiver_ref(receiver)); }
    }

    if class.name == "java/lang/Shutdown" {
        if method_is(method, "beforeHalt", "()V") { return JavaLangShutdown.beforeHalt(context); }
        if method_is(method, "halt0", "(I)V") { return JavaLangShutdown.halt0(context, int_arg(&args, 0)); }
    }

    if class.name == "java/lang/ref/Finalizer" {
        if method_is(method, "isFinalizationEnabled", "()Z") { return JavaLangRefFinalizer.isFinalizationEnabled(context); }
        if method_is(method, "reportComplete", "(Ljava/lang/Object;)V") { return JavaLangRefFinalizer.reportComplete(context, ref_arg(&args, 0)); }
    }

    if class.name == "java/lang/ref/Reference" {
        if method_is(method, "getAndClearReferencePendingList", "()Ljava/lang/ref/Reference;") { return JavaLangRefReference.getAndClearReferencePendingList(context); }
        if method_is(method, "hasReferencePendingList", "()Z") { return JavaLangRefReference.hasReferencePendingList(context); }
        if method_is(method, "waitForReferencePendingList", "()V") { return JavaLangRefReference.waitForReferencePendingList(context); }
        if method_is(method, "refersTo0", "(Ljava/lang/Object;)Z") { return JavaLangRefReference.refersTo0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "clear0", "()V") { return JavaLangRefReference.clear0(context, try receiver_ref(receiver)); }
    }

    if class.name == "sun/reflect/Reflection" {
        if method_is(method, "getCallerClass", "()Ljava/lang/Class;") { return SunReflectReflection.getCallerClass(context, vm); }
        if method_is(method, "getClassAccessFlags", "(Ljava/lang/Class;)I") { return SunReflectReflection.getClassAccessFlags(context, vm, ref_arg(&args, 0)); }
    }

    if class.name == "jdk/internal/reflect/Reflection" {
        if method_is(method, "getCallerClass", "()Ljava/lang/Class;") { return JdkInternalReflectReflection.getCallerClass(context, vm); }
        if method_is(method, "getClassAccessFlags", "(Ljava/lang/Class;)I") { return JdkInternalReflectReflection.getClassAccessFlags(context, vm, ref_arg(&args, 0)); }
    }

    if class.name == "java/security/AccessController" {
        if method_is(method, "getStackAccessControlContext", "()Ljava/security/AccessControlContext;") { return JavaSecurityAccessController.getStackAccessControlContext(context); }
    }

    if class.name == "sun/misc/VM" {
        if method_is(method, "initialize", "()V") { return SunMiscVM.initialize(context); }
    }

    if class.name == "sun/misc/Unsafe" {
        if method_is(method, "registerNatives", "()V") { return SunMiscUnsafe.registerNatives(context); }
        if method_is(method, "arrayBaseOffset", "(Ljava/lang/Class;)I") { return SunMiscUnsafe.arrayBaseOffset(context, ref_arg(&args, 0)); }
        if method_is(method, "arrayIndexScale", "(Ljava/lang/Class;)I") { return SunMiscUnsafe.arrayIndexScale(context, ref_arg(&args, 0)); }
        if method_is(method, "objectFieldOffset", "(Ljava/lang/reflect/Field;)J") { return SunMiscUnsafe.objectFieldOffset(context, vm, ref_arg(&args, 0)); }
        if method_is(method, "compareAndSwapInt", "(Ljava/lang/Object;JII)Z") { return SunMiscUnsafe.compareAndSwapInt(context, vm, ref_arg(&args, 0), long_arg(&args, 1), int_arg(&args, 2), int_arg(&args, 3)); }
        if method_is(method, "compareAndSwapLong", "(Ljava/lang/Object;JJJ)Z") { return SunMiscUnsafe.compareAndSwapLong(context, ref_arg(&args, 0), long_arg(&args, 1), long_arg(&args, 2), long_arg(&args, 3)); }
        if method_is(method, "compareAndSwapObject", "(Ljava/lang/Object;JLjava/lang/Object;Ljava/lang/Object;)Z") { return SunMiscUnsafe.compareAndSwapObject(context, vm, ref_arg(&args, 0), long_arg(&args, 1), ref_arg(&args, 2), ref_arg(&args, 3)); }
        if method_is(method, "getIntVolatile", "(Ljava/lang/Object;J)I") { return SunMiscUnsafe.getIntVolatile(context, vm, ref_arg(&args, 0), long_arg(&args, 1)); }
        if method_is(method, "getObjectVolatile", "(Ljava/lang/Object;J)Ljava/lang/Object;") { return SunMiscUnsafe.getObjectVolatile(context, vm, ref_arg(&args, 0), long_arg(&args, 1)); }
        if method_is(method, "putObjectVolatile", "(Ljava/lang/Object;JLjava/lang/Object;)V") { return SunMiscUnsafe.putObjectVolatile(context, vm, ref_arg(&args, 0), long_arg(&args, 1), ref_arg(&args, 2)); }
        if method_is(method, "allocateMemory", "(J)J") { return SunMiscUnsafe.allocateMemory(context, long_arg(&args, 0)); }
        if method_is(method, "putLong", "(JJ)V") { return SunMiscUnsafe.putLong(context, long_arg(&args, 0), long_arg(&args, 1)); }
        if method_is(method, "getByte", "(J)B") { return SunMiscUnsafe.getByte(context, long_arg(&args, 0)); }
        if method_is(method, "freeMemory", "(J)V") { return SunMiscUnsafe.freeMemory(context, long_arg(&args, 0)); }
        if method_is(method, "ensureClassInitialized", "(Ljava/lang/Class;)V") { return SunMiscUnsafe.ensureClassInitialized(context, ref_arg(&args, 0)); }
        if method_is(method, "addressSize", "()I") { return SunMiscUnsafe.addressSize(context); }
    }

    if class.name == "java/io/FileDescriptor" {
        if method_is(method, "initIDs", "()V") { return JavaIoFileDescriptor.initIDs(context); }
    }

    if class.name == "java/io/PrintStream" {
        if method_is(method, "println", "(Ljava/lang/String;)V") { return java_io_print_stream_println(context, vm, try receiver_ref(receiver), ref_arg(&args, 0)); }
    }

    if class.name == "java/io/FileInputStream" {
        if method_is(method, "initIDs", "()V") { return JavaIoFileInputStream.initIDs(context); }
    }

    if class.name == "java/io/FileOutputStream" {
        if method_is(method, "initIDs", "()V") { return JavaIoFileOutputStream.initIDs(context); }
    }

    if class.name == "java/io/UnixFileSystem" {
        if method_is(method, "initIDs", "()V") { return JavaIoUnixFileSystem.initIDs(context); }
        if method_is(method, "canonicalize0", "(Ljava/lang/String;)Ljava/lang/String;") { return JavaIoUnixFileSystem.canonicalize0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "getBooleanAttributes0", "(Ljava/io/File;)I") { return JavaIoUnixFileSystem.getBooleanAttributes0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "checkAccess0", "(Ljava/io/File;I)Z") { return JavaIoUnixFileSystem.checkAccess0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1)); }
        if method_is(method, "getLastModifiedTime0", "(Ljava/io/File;)J") { return JavaIoUnixFileSystem.getLastModifiedTime0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "getLength0", "(Ljava/io/File;)J") { return JavaIoUnixFileSystem.getLength0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "setPermission0", "(Ljava/io/File;IZZ)Z") { return JavaIoUnixFileSystem.setPermission0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1), int_arg(&args, 2), int_arg(&args, 3)); }
        if method_is(method, "createFileExclusively0", "(Ljava/lang/String;)Z") { return JavaIoUnixFileSystem.createFileExclusively0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "delete0", "(Ljava/io/File;)Z") { return JavaIoUnixFileSystem.delete0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "list0", "(Ljava/io/File;)[Ljava/lang/String;") { return JavaIoUnixFileSystem.list0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "createDirectory0", "(Ljava/io/File;)Z") { return JavaIoUnixFileSystem.createDirectory0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "rename0", "(Ljava/io/File;Ljava/io/File;)Z") { return JavaIoUnixFileSystem.rename0(context, try receiver_ref(receiver), ref_arg(&args, 0), ref_arg(&args, 1)); }
        if method_is(method, "setLastModifiedTime0", "(Ljava/io/File;J)Z") { return JavaIoUnixFileSystem.setLastModifiedTime0(context, try receiver_ref(receiver), ref_arg(&args, 0), long_arg(&args, 1)); }
        if method_is(method, "setReadOnly0", "(Ljava/io/File;)Z") { return JavaIoUnixFileSystem.setReadOnly0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
        if method_is(method, "getSpace0", "(Ljava/io/File;I)J") { return JavaIoUnixFileSystem.getSpace0(context, try receiver_ref(receiver), ref_arg(&args, 0), int_arg(&args, 1)); }
        if method_is(method, "getNameMax0", "(Ljava/lang/String;)J") { return JavaIoUnixFileSystem.getNameMax0(context, try receiver_ref(receiver), ref_arg(&args, 0)); }
    }

    if class.name == "java/util/concurrent/atomic/AtomicLong" {
        if method_is(method, "VMSupportsCS8", "()Z") { return JavaUtilConcurrentAtomicAtomicLong.VMSupportsCS8(context); }
    }

    if class.name == "java/util/zip/ZipFile" {
        if method_is(method, "initIDs", "()V") { return JavaUtilZipZipFile.initIDs(context); }
    }

    println("cava panic: unsupported native method");
    print("  class: ");
    println(class.name);
    print("  method: ");
    print(method.name);
    println(method.descriptor);
    panic("unsupported native method");
    return .err(InstructionError.unsupported_native);
}

fn seed_test_vm(vm: &VM, classes: []Class): void {
    var index: usize = 0;
    while index < classes.len() {
        vm.method_area.classes.push(copy classes[index]);
        index = index + 1;
    }
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
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var vm_classes = vm.method_area.classes[..];
    const original = vm.heap.allocate_object(0, &vm_classes[0]);
    assert(vm.heap.set_field(original, 0, .int_value(42)));
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };

    const result = try JavaLangObject.clone(&context, &vm, original);
    if result is value {
        switch value {
        case .ref_value(clone) {
            assert(!clone.equals(original));
            if vm.heap.get_field(clone, 0) is cloned_value {
                switch cloned_value {
                case .int_value(actual) { assert(actual == 42); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            assert(vm.heap.set_field(original, 0, .int_value(7)));
            if vm.heap.get_field(clone, 0) is cloned_after_original_update {
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
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };

    const modifiers = try JavaLangClass.getModifiers(&context, &vm, classes[0].class_object);
    if modifiers is modifiers_value {
        switch modifiers_value {
        case .int_value(actual) { assert(actual == 0x0021); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }

    const super_class = try JavaLangClass.getSuperclass(&context, &vm, classes[0].class_object);
    if super_class is super_value {
        switch super_value {
        case .ref_value(actual) { assert(actual.equals(classes[1].class_object)); }
        else { assert(false); }
        }
    } else {
        assert(false);
    }

    const object_super_class = try JavaLangClass.getSuperclass(&context, &vm, classes[1].class_object);
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
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
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

    const access_flags_value = try SunReflectReflection.getClassAccessFlags(&context, &vm, class_object);
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
    var vm = new_vm();
    seed_test_vm(&vm, classes[..]);
    var constant_pool: [:]Constant = [: 0] [];
    var context = Context {
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: native_code[..],
        constant_pool: constant_pool[..]
    };

    const first = try JavaLangThread.currentThread(&context, &vm);
    const second = try JavaLangThread.currentThread(&context, &vm);
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
            if vm.heap.get_field(first_ref, 1) is tid {
                switch tid {
                case .long_value(actual) { assert(actual == 1); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            if vm.heap.get_field(first_ref, 3) is priority {
                switch priority {
                case .int_value(actual) { assert(actual == 1); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            if vm.heap.get_field(first_ref, 0) is name {
                switch name {
                case .ref_value(name_ref) { assert(name_ref.equals(vm.heap.strings[0].reference)); }
                else { assert(false); }
                }
            } else {
                assert(false);
            }
            if vm.heap.get_field(first_ref, 2) is group {
                switch group {
                case .ref_value(group_ref) {
                    assert(group_ref.non_null());
                    if vm.heap.get_field(group_ref, 0) is group_name {
                        switch group_name {
                        case .ref_value(group_name_ref) { assert(group_name_ref.equals(vm.heap.strings[0].reference)); }
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

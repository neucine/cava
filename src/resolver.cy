import { Context } from .engine;
import { VM } from .vm;
import { Class, Field, InstructionError, Reference } from .types;

pub struct ResolvedMethod {
    pub class_index: usize;
    pub method_index: usize;
}

fn bytes_equal(left: []const u8, right: []const u8): bool {
    if left.len() != right.len() {
        return false;
    }
    var index: usize = 0;
    while index < left.len() {
        if left[index] != right[index] {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn constant_utf8(context: &Context, index: u16): result<string, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
    case .utf8(value) { return .ok(string.from(value.bytes())); }
    else { return .err(InstructionError.invalid_constant); }
    }
}

pub fn constant_class_name(context: &Context, index: u16): result<string, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
    case .class_ref(name_index) { return constant_utf8(context, name_index); }
    else { return .err(InstructionError.invalid_constant); }
    }
}

fn constant_utf8_equals(context: &Context, index: u16, expected: string): result<bool, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[index as usize] {
    case .utf8(value) { return .ok(value == expected); }
    else { return .err(InstructionError.invalid_constant); }
    }
}

pub fn find_class_index_by_constant(context: &Context, vm: &VM, index: u16): result<usize, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .class_ref(actual) { name_index = actual; }
    else { return .err(InstructionError.invalid_constant); }
    }
    if name_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    switch context.constant_pool[name_index as usize] {
    case .utf8(name) { return vm.resolve_class_index(copy name); }
    else { return .err(InstructionError.invalid_constant); }
    }
}

pub fn find_class_index(context: &Context, vm: &VM, name: string): result<usize, InstructionError> {
    return vm.resolve_class_index(copy name);
}

fn class_index_by_name(classes: []Class, name: string): ?usize {
    var index: usize = 0;
    while index < classes.len() {
        const class = &classes[index];
        if class.name == name {
            return index;
        }
        index = index + 1;
    }
    return none;
}

fn class_instance_var_count(classes: []Class, class_index: usize): u16 {
    if class_index >= classes.len() {
        return 0;
    }
    const class = &classes[class_index];
    var count: u16 = 0;
    var index: usize = 0;
    while index < class.fields.len() {
        const field = &class.fields[index];
        if !field.is_static() {
            count = count + 1;
        }
        index = index + 1;
    }
    return count;
}

fn hierarchy_instance_var_count(classes: []Class, class_index: usize): u16 {
    if class_index >= classes.len() {
        return 0;
    }
    const class = &classes[class_index];
    var count: u16 = 0;
    const super_name = class.super_class;
    if super_name != "" {
        if class_index_by_name(classes, super_name) is super_index {
            count = hierarchy_instance_var_count(classes, super_index);
        }
    }
    return count + class_instance_var_count(classes, class_index);
}

fn field_slot_offset(classes: []Class, current_class_index: usize, declaring_class_name: string): ?u16 {
    if current_class_index >= classes.len() {
        return none;
    }
    const class = &classes[current_class_index];
    var super_count: u16 = 0;
    const super_name = class.super_class;
    if super_name != "" {
        if class_index_by_name(classes, super_name) is super_index {
            super_count = hierarchy_instance_var_count(classes, super_index);
            if field_slot_offset(classes, super_index, declaring_class_name) is super_offset {
                return super_offset;
            }
        }
    }
    if class.name == declaring_class_name {
        return super_count;
    }
    return none;
}

pub fn field_runtime_slot(vm: &VM, reference: Reference, field: Field): ?u16 {
    if vm.heap.object_class_index(reference) is object_class_index {
        if field_slot_offset(vm.method_area.classes[..], object_class_index, field.class_name) is offset {
            return offset + field.slot;
        }
    }
    return none;
}

fn find_field_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.fields.len() {
        const field = &class.fields[index];
        const name_matches = try constant_utf8_equals(context, name_index, field.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, field.descriptor);
        if name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_field_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<Field, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        switch find_field_index_by_constants(class, context, name_index, descriptor_index) {
        case .ok(field_index) {
            return .ok(class.fields[field_index]);
        }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

pub fn find_field_by_name_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name: string, descriptor: string, is_static: bool): result<Field, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        if class.field_index(name, descriptor, is_static) is field_index {
            return .ok(class.fields[field_index as usize]);
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

pub fn find_field_index(class: &Class, name: string, descriptor: string): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.fields.len() {
        const field = &class.fields[index];
        if field.name == name and field.descriptor == descriptor {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_static_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.methods.len() {
        const method = &class.methods[index];
        const name_matches = try constant_utf8_equals(context, name_index, method.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, method.descriptor);
        if method.is_static() and name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_instance_method_index_by_constants(class: &Class, context: &Context, name_index: u16, descriptor_index: u16): result<usize, InstructionError> {
    var index: usize = 0;
    while index < class.methods.len() {
        const method = &class.methods[index];
        const name_matches = try constant_utf8_equals(context, name_index, method.name);
        const descriptor_matches = try constant_utf8_equals(context, descriptor_index, method.descriptor);
        if !method.is_static() and name_matches and descriptor_matches {
            return .ok(index);
        }
        index = index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

fn find_static_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<ResolvedMethod, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        switch find_static_method_index_by_constants(class, context, name_index, descriptor_index) {
        case .ok(method_index) {
            return .ok(ResolvedMethod { class_index: current_index, method_index: method_index });
        }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

fn find_instance_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<ResolvedMethod, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        switch find_instance_method_index_by_constants(class, context, name_index, descriptor_index) {
        case .ok(method_index) {
            return .ok(ResolvedMethod { class_index: current_index, method_index: method_index });
        }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

fn find_interface_method_index_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name_index: u16, descriptor_index: u16): result<ResolvedMethod, InstructionError> {
    if class_index >= vm.method_area.classes.len() {
        return .err(InstructionError.invalid_constant);
    }
    var classes = vm.method_area.classes[..];
    switch find_instance_method_index_by_constants(&classes[class_index], context, name_index, descriptor_index) {
    case .ok(method_index) {
        return .ok(ResolvedMethod { class_index: class_index, method_index: method_index });
    }
    case .err(error_value) {
        const ignored = error_value;
    }
    }

    var interface_index: usize = 0;
    while interface_index < classes[class_index].interfaces.len() {
        switch vm.resolve_class_index(copy classes[class_index].interfaces[interface_index]) {
        case .ok(parent_index) {
            switch find_interface_method_index_in_hierarchy(context, vm, parent_index, name_index, descriptor_index) {
            case .ok(found) { return .ok(found); }
            case .err(error_value) {
                const ignored = error_value;
            }
            }
        }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
        interface_index = interface_index + 1;
    }
    return .err(InstructionError.invalid_constant);
}

pub fn find_instance_method_by_name_in_hierarchy(context: &Context, vm: &VM, class_index: usize, name: string, descriptor: string): result<ResolvedMethod, InstructionError> {
    var current_index = class_index;
    while true {
        var classes = vm.method_area.classes[..];
        const class = &classes[current_index];
        if class.method_index(name, descriptor, false) is method_index {
            return .ok(ResolvedMethod { class_index: current_index, method_index: method_index as usize });
        }
        if class.super_class == "" {
            return .err(InstructionError.invalid_constant);
        }
        current_index = try vm.resolve_class_index(copy class.super_class);
    }
    return .err(InstructionError.invalid_constant);
}

pub fn resolve_field(context: &Context, vm: &VM, index: u16): result<Field, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .field_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
    case .name_and_type(pair) {
        name_index = pair.name_index;
        descriptor_index = pair.descriptor_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_field_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_static_method(context: &Context, vm: &VM, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .method_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
    case .name_and_type(pair) {
        name_index = pair.name_index;
        descriptor_index = pair.descriptor_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_static_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_instance_method(context: &Context, vm: &VM, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .method_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
    case .name_and_type(pair) {
        name_index = pair.name_index;
        descriptor_index = pair.descriptor_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_instance_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

pub fn resolve_interface_method(context: &Context, vm: &VM, index: u16): result<ResolvedMethod, InstructionError> {
    if index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }

    var class_index: u16 = 0;
    var name_and_type_index: u16 = 0;
    switch context.constant_pool[index as usize] {
    case .interface_method_ref(member) {
        class_index = member.class_index;
        name_and_type_index = member.name_and_type_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    if name_and_type_index as usize >= context.constant_pool.len() {
        return .err(InstructionError.invalid_constant);
    }
    var name_index: u16 = 0;
    var descriptor_index: u16 = 0;
    switch context.constant_pool[name_and_type_index as usize] {
    case .name_and_type(pair) {
        name_index = pair.name_index;
        descriptor_index = pair.descriptor_index;
    }
    else { return .err(InstructionError.invalid_constant); }
    }

    const actual_class_index = try find_class_index_by_constant(context, vm, class_index);
    return find_interface_method_index_in_hierarchy(context, vm, actual_class_index, name_index, descriptor_index);
}

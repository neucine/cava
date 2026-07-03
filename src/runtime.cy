import { Context, FrameResult } from .engine;
import { find_class_index_by_constant } from .resolver;
import { VM } from .vm;
import { Class, ExceptionHandler, InstructionError, Reference } from .types;

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

pub fn find_loaded_class_index(classes: []Class, name: string): ?usize {
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

pub fn class_matches(classes: []Class, actual_index: usize, expected_index: usize): bool {
    var class_view = classes;
    var current = actual_index;
    while current < class_view.len() {
        if current == expected_index {
            return true;
        }

        const class = &class_view[current];
        const expected_class = &class_view[expected_index];
        var interfaces = class.interfaces[..];
        var interface_index: usize = 0;
        while interface_index < interfaces.len() {
            if bytes_equal(interfaces[interface_index].bytes(), expected_class.name.bytes()) {
                return true;
            }
            interface_index = interface_index + 1;
        }

        if find_loaded_class_index(class_view, copy class.super_class) is super_index {
            current = super_index;
        } else {
            return false;
        }
    }
    return false;
}

fn class_named(classes: []Class, index: usize, name: string): bool {
    if index >= classes.len() {
        return false;
    }
    var class_view = classes;
    const class = &class_view[index];
    return class.name == name;
}

pub fn reference_assignable_to(classes: []Class, actual_index: usize, expected_index: usize): bool {
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
            const interface_name = &interfaces[interface_index];
            if find_loaded_class_index(class_view, copy interface_name) is actual_interface_index {
                if reference_assignable_to(classes, actual_interface_index, expected_index) {
                    return true;
                }
            } else {
                if interface_name == expected_class.name {
                    return true;
                }
            }
            interface_index = interface_index + 1;
        }
        if find_loaded_class_index(class_view, copy actual_class.super_class) is super_index {
            return reference_assignable_to(classes, super_index, expected_index);
        }
        return false;
    }

    if actual_class.is_array {
        if class_named(classes, expected_index, "java/lang/Object") {
            return true;
        }
        if expected_class.is_array {
            return bytes_equal(actual_class.component_type.bytes(), expected_class.component_type.bytes());
        }
        return false;
    }

    if find_loaded_class_index(class_view, copy actual_class.super_class) is super_index {
        return reference_assignable_to(classes, super_index, expected_index);
    }
    return false;
}

fn handler_matches(context: &Context, vm: &VM, handler: ExceptionHandler, exception: Reference): result<bool, InstructionError> {
    if handler.catch_type == 0 {
        return .ok(true);
    }
    var exception_class_index: usize = 0;
    if vm.heap.object_class_index(exception) is actual_exception_class_index {
        exception_class_index = actual_exception_class_index;
    } else {
        return .err(InstructionError.invalid_constant);
    }
    const catch_class_index = try find_class_index_by_constant(context, vm, handler.catch_type);
    return .ok(class_matches(vm.method_area.classes[..], exception_class_index, catch_class_index));
}

pub fn dispatch_exception(context: &Context, vm: &VM, exception: Reference): result<bool, InstructionError> {
    var classes = vm.method_area.classes[..];
    if context.class_index >= classes.len() {
        return .ok(false);
    }
    if context.method_index >= classes[context.class_index].methods.len() {
        return .ok(false);
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
                return .ok(true);
            }
        }
        index = index + 1;
    }
    return .ok(false);
}

pub fn apply_method_result(context: &Context, vm: &VM, result: FrameResult): result<void, InstructionError> {
    switch result {
    case .return_value(value) {
        if value is actual {
            context.frame.push(actual);
        }
    }
    case .exception(reference) {
        if !(try dispatch_exception(context, vm, reference)) {
            context.frame.throw_exception(reference);
        }
    }
    }
    return .ok();
}

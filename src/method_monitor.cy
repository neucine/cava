import { Runtime } from .runtime;
import { VM } from .vm;
import { InstructionError, MethodAccessFlags, Reference } from .types;

pub fn enter_monitor(runtime: ?Runtime, vm: &VM, reference: Reference): void ! InstructionError {
    if reference.is_null() {
        throw InstructionError.invalid_constant;
    }
    if runtime is active_runtime {
        var acquired = false;
        while !acquired {
            if vm.heap.monitor_try_enter(reference) is actual {
                acquired = actual;
            } else {
                throw InstructionError.invalid_constant;
            }
            if !acquired and !active_runtime.pause(1) {
                throw InstructionError.invalid_constant;
            }
        }
        return;
    }
    if !vm.heap.monitor_enter(reference) {
        throw InstructionError.invalid_constant;
    }
    return;
}

pub fn enter_method_monitor(runtime: ?Runtime, vm: &VM, class_index: usize, method_index: usize, receiver: ?Reference): ?Reference ! InstructionError {
    const access = vm.method_area.classes[class_index].methods[method_index].access_flags;
    if !(MethodAccessFlags.synchronized in access) {
        return none;
    }
    var reference = Reference.init_null();
    if MethodAccessFlags.static_flag in access {
        reference = vm.method_area.classes[class_index].class_object;
        if reference.is_null() {
            const class_class_index = try vm.resolve_class_index("java/lang/Class");
            var classes = vm.method_area.classes[..];
            reference = vm.heap.allocate_object(class_class_index, &classes[class_class_index]);
            const class = &classes[class_index];
            class.class_object = reference;
        }
    } else {
        if receiver is actual {
            reference = actual;
        } else {
            throw InstructionError.invalid_constant;
        }
    }
    try enter_monitor(runtime, vm, reference);
    const held: ?Reference = reference;
    const _cava_optional_243: ?Reference = held;
    return _cava_optional_243;
}

pub fn exit_method_monitor(vm: &VM, monitor: ?Reference): void ! InstructionError {
    if monitor is reference {
        if !vm.heap.monitor_exit(reference) {
            throw InstructionError.invalid_constant;
        }
    }
    return;
}

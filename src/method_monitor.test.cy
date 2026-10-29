import { Constant } from .classfile;
import { Context, execute_method_frame_with_vm, new_frame } from .engine;
import { enter_method_monitor, exit_method_monitor } from .method_monitor;
import { execute_native_method } from .native;
import { VM, new_vm } from .vm;
import { Class, Method, Reference, Value, class_access_flags, method_access_flags, null_ref } from .types;

fn monitor_test_method(access: u16, name: string, descriptor: string, code: [:]u8): Method {
    const length = code.len() as u32;
    return Method {
        class_name: "java/lang/Thread",
        access_flags: method_access_flags(access),
        name: name,
        descriptor: descriptor,
        code: code,
        max_stack: 2,
        max_locals: 1,
        code_len: length,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: 0,
        return_descriptor: "V",
    };
}

fn install_monitor_test_class(vm: &VM): Reference {
    const class = Class {
        name: "java/lang/Thread",
        descriptor: "Ljava/lang/Thread;",
        access_flags: class_access_flags(1),
        super_class: "",
        interfaces: [],
        fields: [],
        methods: [
            monitor_test_method(32, "normal", "()V", [0xb1]),
            monitor_test_method(32, "throwing", "()V", [0x2a, 0xbf]),
            monitor_test_method(32, "invalid", "()V", [0x01, 0xc3]),
            monitor_test_method(0x128, "holdsLock", "(Ljava/lang/Object;)Z", []),
            monitor_test_method(0x120, "holdsLock", "(Ljava/lang/Object;)Z", []),
            monitor_test_method(0x120, "start0", "()V", [])
        ],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: true,
        class_object: null_ref,
    };
    vm.method_area.classes.push(class);
    var classes = vm.method_area.classes[..];
    const receiver = vm.heap.allocate_object(0, &classes[0]);
    const mirror = vm.heap.allocate_object(0, &classes[0]);
    const installed = &classes[0];
    installed.class_object = mirror;
    return receiver;
}

test "synchronized interpreted methods release monitors on every completion path" {
    var vm = new_vm();
    const receiver = install_monitor_test_class(&vm);
    var pool: List<Constant> = [];
    var method_index: usize = 0;
    while method_index < 3 {
        var frame = new_frame(0, method_index, 1, 2);
        frame.store(0, .ref_value(receiver));
        const completion = execute_method_frame_with_vm(&vm, 0, method_index, frame, pool[..]) catch (problem) {
            assert(method_index == 2);
            assert(!vm.heap.monitor_held_by_current_thread(receiver));
            method_index = method_index + 1;
            continue;
        };
        if method_index == 0 {
            switch completion {
                .return_value => {}
                .exception => unreachable;
            }
        } else {
            assert(method_index == 1);
            switch completion {
                .exception(reference) => {
                    assert(reference.equals(receiver));
                }
                .return_value => unreachable;
            }
        }
        assert(!vm.heap.monitor_held_by_current_thread(receiver));
        method_index = method_index + 1;
    }
    assert(vm.heap.monitor_enter(receiver));
    const monitor = enter_method_monitor(none, &vm, 0, 0, receiver) catch (problem) {
        assert(false);
        return;
    };
    exit_method_monitor(&vm, monitor) catch (problem) {
        assert(false);
        return;
    };
    assert(vm.heap.monitor_held_by_current_thread(receiver));
    assert(vm.heap.monitor_exit(receiver));
    assert(!vm.heap.monitor_held_by_current_thread(receiver));
    vm.destroy();
}

test "synchronized native methods use receiver or declaring class mirror and release on error" {
    var vm = new_vm();
    const receiver = install_monitor_test_class(&vm);
    const mirror = vm.method_area.classes[0].class_object;
    var pool: List<Constant> = [];
    const code: [:]u8 = [];
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 1, 2),
        code: code[..],
        constant_pool: pool[..],
    };
    var method_index: usize = 3;
    while method_index < 5 {
        var expected = receiver;
        if method_index == 3 {
            expected = mirror;
        }
        const arguments: List<Value> = [.ref_value(expected)];
        const value = execute_native_method(&context, &vm, 0, method_index, receiver, arguments) catch (problem) {
            assert(false);
            return;
        };
        if value is actual {
            switch actual {
                .boolean_value(held) => {
                    assert(held == 1);
                }
                _ => unreachable;
            }
        } else {
            assert(false);
        }
        assert(!vm.heap.monitor_held_by_current_thread(expected));
        method_index = method_index + 1;
    }
    const unexpected = execute_native_method(&context, &vm, 0, 5, receiver, []) catch (problem) {
        assert(!vm.heap.monitor_held_by_current_thread(receiver));
        vm.destroy();
        return;
    };
    assert(false);
}

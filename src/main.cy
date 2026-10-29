import { execute_method_area_with_runtime, execution_exit_code, print_execution_error } from .engine;
import { VM } from .vm;
import { Runtime, new_runtime } from .runtime;
import { args } from std.process;

struct ExecuteEntryRequest {
    runtime: Runtime;
    class_index: usize;
    java_args: []const string;
}

struct RunClassFileRequest {
    runtime: Runtime;
    path: string;
    java_args: []const string;
}

fn execute_entry_with_vm(vm: &VM, request: ExecuteEntryRequest): i32 {
    if vm.method_area.method_index(request.class_index, "main", "([Ljava/lang/String;)V") is actual_method_index {
        const method_index = actual_method_index as usize;
        const ignored_system = vm.method_area.resolve_class("java/lang/System");
        const ignored_print_stream = vm.method_area.resolve_class("java/io/PrintStream");
        const ignored_output_stream = vm.method_area.resolve_class("java/io/OutputStream");
        vm.initialize_system_out();
        if vm.method_area.find_class_index("java/lang/System") is system_index {
            if vm.method_area.method_index(system_index, "initializeSystemClass", "()V") is initialize_index {
                const empty_args: [0]string = [];
                const system_completion = execute_method_area_with_runtime(request.runtime.alias_handles(), vm, system_index, initialize_index as usize, vm.method_area.classes[system_index].constant_pool[..], empty_args[..]) catch (error_value) {
                    print_execution_error(error_value);
                    return execution_exit_code(error_value);
                };
            }
        }
        const main_completion = execute_method_area_with_runtime(request.runtime.alias_handles(), vm, request.class_index, method_index, vm.method_area.classes[request.class_index].constant_pool[..], request.java_args) catch (error_value) {
            print_execution_error(error_value);
            return execution_exit_code(error_value);
        };
        return 0;
    } else {
        println("main method not found");
        return 4;
    }
}

fn run_class_file_with_vm(vm: &VM, request: RunClassFileRequest): i32 {
    const class_index = vm.method_area.load_class_file(request.path) catch (problem) {
        println("class read failed");
        return 1;
    };
    return execute_entry_with_vm(vm, ExecuteEntryRequest {
        runtime: request.runtime.alias_handles(),
        class_index: class_index,
        java_args: request.java_args
    });
}

fn run_class_file(path: string, java_args: []const string): i32 {
    const runtime = new_runtime();
    const code = runtime.state.with_result<RunClassFileRequest, i32>(RunClassFileRequest {
        runtime: runtime.alias_handles(),
        path: path,
        java_args: java_args
    }, run_class_file_with_vm) catch (problem) {
        runtime.finish();
        return 24;
    };
    runtime.finish();
    return code;
}

fn main(): i32 {
    var values = args();
    var code: i32 = 64;
    if values.len() >= 2 {
        var class_path = values[1].clone();
        var java_args: List<string> = [];
        var index: usize = 2;
        while index < values.len() {
            java_args.push(values[index].clone());
            index = index + 1;
        }
        code = run_class_file(class_path, java_args[..]);
    } else {
        println("usage: cava <classfile> [args...]");
    }
    return code;
}

import { ClassFile, ClassfileError, new_classfile, parse_classfile } from .classfile;
import { new_heap } from .heap;
import { execute_classfile_method_area } from .instruction;
import { MethodArea, MethodAreaError, new_method_area } from .method_area;
import { InstructionError } from .types;
import { read_file } from std.fs;
import { args } from std.process;

fn instruction_exit_code(error_value: InstructionError): i32 {
    if error_value == InstructionError.unsupported_opcode {
        return 20;
    }
    if error_value == InstructionError.unsupported_native {
        return 21;
    }
    if error_value == InstructionError.invalid_constant {
        return 22;
    }
    if error_value == InstructionError.missing_return {
        return 23;
    }
    return 24;
}

fn parse_entry_classfile(source: string): result<ClassFile, ClassfileError> {
    var classfile = new_classfile();
    try parse_classfile(source, &classfile);
    return .ok(classfile);
}

fn load_entry_area(classfile: &ClassFile): result<MethodArea, ClassfileError> {
    var area = new_method_area();
    const ignored = try area.define_class(classfile);
    return .ok(area);
}

fn execute_entry(area_value: MethodArea, classfile: &ClassFile): i32 {
    var area = area_value;
    area.define_hello_world_builtins();
    const class_index: usize = 0;
    if area.method_index(class_index, "main", "([Ljava/lang/String;)V") is actual_method_index {
        const method_index = actual_method_index as usize;
        var heap = new_heap();
        area.initialize_system_out(&heap);
        switch execute_classfile_method_area(class_index, method_index, classfile, &area, &heap) {
        case .ok(result) {
            const ignored = result;
            heap.clear();
            drop heap;
            area.clear();
            drop area;
            return 0;
        }
        case .err(error_value) {
            if error_value == InstructionError.unsupported_opcode {
                println("execution failed: unsupported opcode");
            } else {
                if error_value == InstructionError.unsupported_native {
                    println("execution failed: unsupported native");
                } else {
                    if error_value == InstructionError.invalid_constant {
                        println("execution failed: invalid constant");
                    } else {
                        if error_value == InstructionError.missing_return {
                            println("execution failed: missing return");
                        } else {
                            println("execution failed");
                        }
                    }
                }
            }
            heap.clear();
            drop heap;
            area.clear();
            drop area;
            return instruction_exit_code(error_value);
        }
        }
    } else {
        println("main method not found");
        drop area;
        return 4;
    }
}

fn run_class_file(path: string): i32 {
    const read_result = read_file(path);
    switch read_result {
    case .ok(source) {
        var owned_source = source;
        var classfile: ClassFile = new_classfile();
        switch parse_entry_classfile(owned_source) {
        case .ok(parsed) { classfile = parsed; }
        case .err(error_value) {
            const ignored = error_value;
            println("classfile parse failed");
            return 2;
        }
        }

        switch load_entry_area(&classfile) {
        case .ok(area) {
            const code = execute_entry(area, &classfile);
            classfile.clear();
            drop classfile;
            return code;
        }
        case .err(error_value) {
            const ignored = error_value;
            println("class derive failed");
            classfile.clear();
            drop classfile;
            return 3;
        }
        }
    }
    case .err(error_value) {
        const ignored = error_value;
        println("class read failed");
        return 1;
    }
    }
}

fn main(): i32 {
    const values = args();
    if values.len() < 2 {
        println("usage: cava <classfile>");
        return 64;
    }
    const code = run_class_file(values[1]);
    drop values;
    return code;
}

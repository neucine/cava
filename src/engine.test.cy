import { ClassFile, Constant } from .classfile;
import { execute_next, find_class_index_by_constant, print_instruction_error_context } from .instruction;
import { class_matches } from .method_area;
import { VM, new_vm } from .vm;
import { Class, ExceptionHandler, InstructionError, Reference, Value } from .types;
import { Runtime } from .runtime;
import {
    max_call_stack,
    ThreadStatus,
    FrameResult,
    Frame,
    new_frame,
    Thread,
    new_thread,
    Context,
    execution_exit_code,
    print_execution_error,
    handler_matches,
    dispatch_exception,
    apply_method_result,
    execute_method_frame_with_context,
    execute_method_frame_with_vm,
    execute_method_frame_with_runtime,
    execute_method_area_with_vm,
    execute_method_area_with_runtime,
    execute_classfile_method_area_with_vm,
    expect_ref_for_engine,
    assert_int_value
} from .engine;

test "frame manages locals operand stack and pc" {
    var frame = new_frame(2, 3, 2, 4);
    assert(frame.class_index == 2);
    assert(frame.method_index == 3);
    assert(frame.pc == 0);
    assert(frame.offset == 1);
    assert(frame.local_vars.len() == 2);
    assert(frame.depth() == 0);

    frame.store(0, .int_value(41));
    frame.push(frame.load(0));
    frame.push(.int_value(1));
    assert(frame.depth() == 2);
    assert_int_value(frame.pop(), 1);
    assert_int_value(frame.pop(), 41);

    frame.next(5);
    assert(frame.pc == 5);
    frame.next(0 - 2);
    assert(frame.pc == 3);

    const return_value: Value = .int_value(42);
    frame.return_value(return_value);
    if frame.result is result {
        switch result {
            case .return_value(value) {
                if value is actual {
                    assert_int_value(actual, 42);
                } else {
                    assert(false);
                }
            }
            case .exception {
                assert(false);
            }
        }
    } else {
        assert(false);
    }
}

test "thread pushes and pops frames" {
    var thread = new_thread(7, string.from("main".bytes()));
    assert(thread.id == 7);
    assert(thread.status == ThreadStatus.started);
    assert(thread.depth() == 0);
    assert(!thread.has_active());

    assert(thread.push_frame(new_frame(0, 1, 1, 1)));
    assert(thread.push_frame(new_frame(0, 2, 1, 1)));
    assert(thread.depth() == 2);
    assert(thread.has_active());
    if thread.active_index() is active {
        assert(thread.stack[active].method_index == 2);
    } else {
        assert(false);
    }

    if thread.pop_frame() is frame {
        assert(frame.method_index == 2);
    } else {
        assert(false);
    }
    assert(thread.depth() == 1);

    const popped = thread.pop_frame();
    const empty = thread.pop_frame();
    assert(popped != none);
    assert(empty == none);
}

test "context reads big endian operands and padding" {
    const code: [12]u8 = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66];
    var constant_pool: [:]Constant = [: 0][];
    var context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 1, 4),
        code: code[..],
        constant_pool: constant_pool[..]
    };

    assert(context.read_u1() == 49);
    assert(context.frame.offset == 2);
    assert(context.read_u2() == 0x3233);
    assert(context.frame.offset == 4);

    context.frame.pc = 5;
    context.frame.offset = 1;
    context.padding();
    assert(context.frame.offset == 3);
    assert(context.read_i4() == 0x38394142);

    const negative_code: [3]u8 = [0, 255, 243];
    var negative_context = Context {
        runtime: none,
        class_index: 0,
        method_index: 0,
        frame: new_frame(0, 0, 0, 0),
        code: negative_code[..],
        constant_pool: constant_pool[..]
    };
    assert(negative_context.read_i2() == (0 - 13));
}

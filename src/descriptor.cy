import { InstructionError } from .types;

pub fn method_argument_count(descriptor: string): result<usize, InstructionError> {
    const bytes = descriptor.bytes();
    if bytes.len() < 2 or bytes[0] != 40 {
        return .err(InstructionError.invalid_constant);
    }

    var index: usize = 1;
    var count: usize = 0;
    while index < bytes.len() and bytes[index] != 41 {
        while index < bytes.len() and bytes[index] == 91 {
            index = index + 1;
        }
        if index >= bytes.len() {
            return .err(InstructionError.invalid_constant);
        }
        if bytes[index] == 76 {
            while index < bytes.len() and bytes[index] != 59 {
                index = index + 1;
            }
            if index >= bytes.len() {
                return .err(InstructionError.invalid_constant);
            }
        }
        index = index + 1;
        count = count + 1;
    }

    if index >= bytes.len() or bytes[index] != 41 {
        return .err(InstructionError.invalid_constant);
    }
    return .ok(count);
}

pub fn reference_array_component_descriptor(class_name: string): string {
    const name_bytes = class_name.bytes();
    if name_bytes.len() > 0 and name_bytes[0] == 91 {
        return string.from(name_bytes);
    }

    var bytes = [: name_bytes.len() + 2]u8;
    bytes.push(76);
    var index: usize = 0;
    while index < name_bytes.len() {
        bytes.push(name_bytes[index]);
        index = index + 1;
    }
    bytes.push(59);
    const out = string.from(bytes[..]);
    return out;
}

pub fn reference_array_descriptor(component_descriptor: string): string {
    const component_bytes = component_descriptor.bytes();
    var bytes = [: component_bytes.len() + 1]u8;
    bytes.push(91);
    var index: usize = 0;
    while index < component_bytes.len() {
        bytes.push(component_bytes[index]);
        index = index + 1;
    }
    const out = string.from(bytes[..]);
    return out;
}

pub fn array_component_descriptor(descriptor: string): string {
    const bytes = descriptor.bytes();
    if bytes.len() == 0 or bytes[0] != 91 {
        return string.from(bytes[0..0]);
    }
    return string.from(bytes[1..bytes.len()]);
}

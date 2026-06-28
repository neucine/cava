import { parse_class_header } from .classfile;
import { default_value } from .types;

fn main(): i32 {
    switch default_value("I") {
    case .int_value(value) {
        return value;
    }
    case .byte_value(value) { const ignored = value; return 1; }
    case .short_value(value) { const ignored = value; return 1; }
    case .char_value(value) { const ignored = value; return 1; }
    case .long_value(value) { const ignored = value; return 1; }
    case .float_value(value) { const ignored = value; return 1; }
    case .double_value(value) { const ignored = value; return 1; }
    case .boolean_value(value) { const ignored = value; return 1; }
    case .return_address_value(value) { const ignored = value; return 1; }
    case .ref_value(value) { const ignored = value; return 1; }
    }
}

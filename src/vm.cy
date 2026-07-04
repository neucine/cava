import { Heap, new_heap } from .heap;
import { MethodArea, new_method_area } from .method_area;
import { InstructionError, Reference, java_utf16_units_from_utf8 } from .types;

pub struct VM {
    pub method_area: MethodArea;
    pub heap: Heap;

    pub fn clear(self: &VM): void {
        self.heap.clear();
        self.method_area.clear();
    }

    pub fn resolve_class_index(self: &VM, name: string): result<usize, InstructionError> {
        var classes = self.method_area.classes[..];
        var index: usize = 0;
        while index < classes.len() {
            const class = &classes[index];
            if class.name == name {
                return .ok(index);
            }
            index = index + 1;
        }
        switch self.method_area.resolve_class(copy name) {
        case .ok(class_index) { return .ok(class_index); }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn allocate_java_string(self: &VM, value: []const u8): result<Reference, InstructionError> {
        const string_class_index = try self.resolve_class_index("java/lang/String");
        var classes = self.method_area.classes[..];
        if self.heap.interned_string_reference(value) is existing_reference {
            return .ok(existing_reference);
        }
        const reference = self.heap.allocate_object_with_hierarchy(string_class_index, classes);
        const string_class = &classes[string_class_index];
        if string_class.field_index("value", "[C", false) is value_field_index {
            const chars = java_utf16_units_from_utf8(value);
            const chars_reference = self.heap.allocate_array(0, "C".bytes(), chars.len());
            var char_index: usize = 0;
            while char_index < chars.len() {
                if !self.heap.set_element(chars_reference, char_index, .char_value(chars[char_index])) {
                    drop chars;
                    return .err(InstructionError.invalid_constant);
                }
                char_index = char_index + 1;
            }
            drop chars;
            var fields = string_class.fields[..];
            const field = &fields[value_field_index as usize];
            if !self.heap.set_field(reference, field.slot, .ref_value(chars_reference)) {
                return .err(InstructionError.invalid_constant);
            }
        }
        if string_class.field_index("coder", "B", false) is coder_field_index {
            var fields = string_class.fields[..];
            const field = &fields[coder_field_index as usize];
            if !self.heap.set_field(reference, field.slot, .byte_value(0)) {
                return .err(InstructionError.invalid_constant);
            }
        }
        self.heap.register_string_bytes(reference, value);
        return .ok(reference);
    }

    pub fn print_java_string(self: &VM, reference: Reference, newline: bool): result<void, InstructionError> {
        const string_class_index = try self.resolve_class_index("java/lang/String");
        var classes = self.method_area.classes[..];
        if classes[string_class_index].field_index("value", "[C", false) is value_field_index {
            const slot = classes[string_class_index].fields[value_field_index as usize].slot;
            if self.heap.get_field(reference, slot) is value {
                switch value {
                case .ref_value(chars_reference) {
                    if self.heap.array_length(chars_reference) is length {
                        var bytes: List<u8> = [];
                        var index: usize = 0;
                        while index < length {
                            if self.heap.get_element(chars_reference, index) is element {
                                switch element {
                                case .char_value(ch) { bytes.push(ch as u8); }
                                case .byte_value(ch) { bytes.push(ch as u8); }
                                else { bytes.push(0); }
                                }
                            }
                            index = index + 1;
                        }
                        const text = string.from(bytes[..]);
                        if newline {
                            println(text);
                        } else {
                            print(text);
                        }
                        drop text;
                        drop bytes;
                        return .ok();
                    }
                }
                case .byte_value(ignored) { const unused = ignored; }
                case .short_value(ignored) { const unused = ignored; }
                case .char_value(ignored) { const unused = ignored; }
                case .int_value(ignored) { const unused = ignored; }
                case .long_value(ignored) { const unused = ignored; }
                case .float_value(ignored) { const unused = ignored; }
                case .double_value(ignored) { const unused = ignored; }
                case .boolean_value(ignored) { const unused = ignored; }
                case .return_address_value(ignored) { const unused = ignored; }
                }
            }
        }
        return .err(InstructionError.invalid_constant);
    }

    pub fn initialize_system_out(self: &VM): void {
        var system_index: usize = 0;
        if self.method_area.find_class_index("java/lang/System") is actual_system_index {
            system_index = actual_system_index;
        } else {
            return;
        }
        var print_stream_index: usize = 0;
        if self.method_area.find_class_index("java/io/PrintStream") is actual_print_stream_index {
            print_stream_index = actual_print_stream_index;
        } else {
            return;
        }
        var classes = self.method_area.classes[..];
        const reference = self.heap.allocate_object_with_hierarchy(print_stream_index, classes);
        if self.method_area.find_class_index("java/io/OutputStream") is output_stream_index {
            const output_reference = self.heap.allocate_object_with_hierarchy(output_stream_index, classes);
            const ignored_set = self.heap.set_field(reference, 0, .ref_value(output_reference));
        }
        var system_class = &classes[system_index];
        if self.method_area.field_index(system_index, "out", "Ljava/io/PrintStream;") is field_index_value {
            var fields = system_class.fields[..];
            const field = &fields[field_index_value as usize];
            if field.is_static() {
                system_class.static_vars[field.slot as usize] = .ref_value(reference);
            }
        }
        if self.method_area.field_index(system_index, "err", "Ljava/io/PrintStream;") is field_index_value {
            var fields = system_class.fields[..];
            const field = &fields[field_index_value as usize];
            if field.is_static() {
                system_class.static_vars[field.slot as usize] = .ref_value(reference);
            }
        }
        self.initialize_system_props(system_index);
    }

    fn initialize_system_props(self: &VM, system_index: usize): void {
        var properties_index: usize = 0;
        if self.method_area.find_class_index("java/util/Properties") is actual_properties_index {
            properties_index = actual_properties_index;
        } else {
            return;
        }
        var hashtable_index: usize = 0;
        if self.method_area.find_class_index("java/util/Hashtable") is actual_hashtable_index {
            hashtable_index = actual_hashtable_index;
        } else {
            return;
        }
        if self.method_area.field_index(system_index, "props", "Ljava/util/Properties;") is props_field_index {
            var classes = self.method_area.classes[..];
            var system_class = &classes[system_index];
            var system_fields = system_class.fields[..];
            const props_field = &system_fields[props_field_index as usize];
            if props_field.is_static() {
                const props = self.heap.allocate_object_with_hierarchy(properties_index, classes);
                const hashtable_class = &classes[hashtable_index];
                if hashtable_class.field_index("table", "[Ljava/util/Hashtable$Entry;", false) is table_field_index {
                    var hashtable_fields = hashtable_class.fields[..];
                    const table_field = &hashtable_fields[table_field_index as usize];
                    const table = self.heap.allocate_array(0, "Ljava/util/Hashtable$Entry;".bytes(), 11);
                    const ignored = self.heap.set_field(props, table_field.slot, .ref_value(table));
                }
                system_class.static_vars[props_field.slot as usize] = .ref_value(props);
            }
        }
    }
}

pub fn new_vm(): VM {
    return VM {
        method_area: new_method_area(),
        heap: new_heap(),
    };
}

import { AttributeInfo, ByteReader, ClassFile, ClassfileError, Constant, ConstantMemberRef, ConstantNameAndType, MemberInfo, new_classfile, parse_classfile } from .classfile;
import { Class, ExceptionHandler, Field, Method, Reference, Value, byte_buffer, class_access_flags, default_value, field_access_flags, method_access_flags, null_ref } from .types;
import { FsError, read_file } from std.fs;

pub enum MethodAreaError: i32 {
    classfile = 0,
    not_found,
    permission_denied,
    already_exists,
    invalid_path,
    io_error,
}

fn method_area_error_from_fs(err: FsError): MethodAreaError {
    if err == FsError.not_found {
        return MethodAreaError.not_found;
    }
    if err == FsError.permission_denied {
        return MethodAreaError.permission_denied;
    }
    if err == FsError.already_exists {
        return MethodAreaError.already_exists;
    }
    if err == FsError.invalid_path {
        return MethodAreaError.invalid_path;
    }
    return MethodAreaError.io_error;
}

pub struct SymbolPool {
    pub symbols: List<string>;

    pub fn clear(self: &SymbolPool): void {
        while self.symbols.len() > 0 {
            var symbol = self.symbols.pop();
            drop symbol;
        }
    }

    pub fn contains(self: &SymbolPool, value: []const u8): bool {
        const needle = string.from(value);
        var found = false;
        var index: usize = 0;
        while index < self.symbols.len() {
            if self.symbols[index] == needle {
                found = true;
            }
            index = index + 1;
        }
        drop needle;
        return found;
    }

    pub fn add(self: &SymbolPool, value: []const u8): void {
        if self.contains(value) {
            return;
        }
        const symbol = string.from(value);
        self.symbols.push(symbol);
        drop symbol;
    }
}

pub fn new_symbol_pool(): SymbolPool {
    return SymbolPool {
        symbols: [],
    };
}

pub struct ResolvedMethod {
    pub class_index: usize;
    pub method_index: usize;
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
            if interfaces[interface_index] == expected_class.name {
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
            return actual_class.component_type == expected_class.component_type;
        }
        return false;
    }

    if find_loaded_class_index(class_view, copy actual_class.super_class) is super_index {
        return reference_assignable_to(classes, super_index, expected_index);
    }
    return false;
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

pub fn runtime_field_slot(classes: []Class, object_class_index: usize, field: Field): ?u16 {
    if field_slot_offset(classes, object_class_index, field.class_name) is offset {
        return offset + field.slot;
    }
    return none;
}

fn contains_class_index(visited: &List<usize>, class_index: usize): bool {
    var index: usize = 0;
    while index < visited.len() {
        if visited[index] == class_index {
            return true;
        }
        index = index + 1;
    }
    return false;
}

fn bytes_match_at(source: []const u8, index: usize, needle: []const u8): bool {
    if index + needle.len() > source.len() {
        return false;
    }
    var needle_index: usize = 0;
    while needle_index < needle.len() {
        if source[index + needle_index] != needle[needle_index] {
            return false;
        }
        needle_index = needle_index + 1;
    }
    return true;
}

fn project_root_from_example_class_path(path: string): ?string {
    const path_bytes = path.bytes();
    const segment = "/examples/classes/".bytes();
    var index: usize = 0;
    while index < path_bytes.len() {
        if bytes_match_at(path_bytes, index, segment) {
            return string.from(path_bytes[0..index]);
        }
        index = index + 1;
    }
    return none;
}

pub struct MethodArea {
    pub classes: List<Class>;
    pub symbols: SymbolPool;
    pub class_sources: List<string>;
    pub application_class_root: string;
    pub jdk_class_root: string;

    pub fn clear(self: &MethodArea): void {
        while self.classes.len() > 0 {
            var class = self.classes.pop();
            class.clear();
            drop class;
        }
        self.symbols.clear();
        var source_index: usize = 0;
        while source_index < self.class_sources.len() {
            self.class_sources[source_index] = "";
            source_index = source_index + 1;
        }
        self.class_sources.clear();
        self.application_class_root = "";
        self.jdk_class_root = "";
    }

    pub fn find_class_index(self: &MethodArea, name: string): ?usize {
        var classes = self.classes[..];
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

    pub fn has_class(self: &MethodArea, name: string): bool {
        return self.find_class_index(name) != none;
    }

    pub fn resolve_class(self: &MethodArea, class_name: string): result<usize, MethodAreaError> {
        const class_name_bytes = class_name.bytes();
        if class_name_bytes.len() > 0 and class_name_bytes[0] == 91 {
            return .ok(self.define_array_class(copy class_name));
        }
        if self.find_class_index(copy class_name) is existing {
            return .ok(existing);
        }

        switch self.load_class_from_path(copy self.application_class_root, copy class_name) {
        case .ok(index) { return .ok(index); }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
        return self.load_class_from_path(copy self.jdk_class_root, copy class_name);
    }

    pub fn class_count(self: &MethodArea): usize {
        return self.classes.len();
    }

    pub fn classes_view(self: &MethodArea): []Class {
        return self.classes[..];
    }

    pub fn field_index(self: &MethodArea, class_index: usize, name: string, descriptor: string): ?i32 {
        if class_index >= self.classes.len() {
            return none;
        }

        var index: usize = 0;
        while index < self.classes[class_index].fields.len() {
            const field = &self.classes[class_index].fields[index];
            if field.name == name and field.descriptor == descriptor {
                return index as i32;
            }
            index = index + 1;
        }
        return none;
    }

    pub fn method_index(self: &MethodArea, class_index: usize, name: string, descriptor: string): ?i32 {
        if class_index >= self.classes.len() {
            return none;
        }

        var index: usize = 0;
        while index < self.classes[class_index].methods.len() {
            const method = &self.classes[class_index].methods[index];
            if method.name == name and method.descriptor == descriptor {
                return index as i32;
            }
            index = index + 1;
        }
        return none;
    }

    pub fn method_max_locals(self: &MethodArea, class_index: usize, method_index: usize): u16 {
        return self.classes[class_index].methods[method_index].max_locals;
    }

    pub fn method_max_stack(self: &MethodArea, class_index: usize, method_index: usize): u16 {
        return self.classes[class_index].methods[method_index].max_stack;
    }

    pub fn resolve_class_ref(self: &MethodArea, classfile: &ClassFile, constant_index: u16): result<usize, ClassfileError> {
        const name = try classfile.class_name(constant_index);
        var resolved: ?usize = none;
        if name != "" {
            if name.bytes()[0] == 91 {
                resolved = self.define_array_class(copy name);
            }
        }
        if resolved == none {
            if self.find_class_index(copy name) is existing {
                resolved = existing;
            }
        }
        drop name;
        if resolved is found {
            return .ok(found);
        }
        return .err(ClassfileError.invalid_constant_index);
    }

    pub fn resolve_field_ref(self: &MethodArea, classfile: &ClassFile, constant_index: u16): result<ResolvedFieldRef, ClassfileError> {
        const member = try classfile.member_ref(constant_index);
        var resolved: ?ResolvedFieldRef = none;
        if self.find_class_index(copy member.class_name) is class_index {
            if self.field_index(class_index, copy member.name, copy member.descriptor) is field_index {
                resolved = ResolvedFieldRef {
                    class_index: class_index,
                    field_index: field_index,
                };
            }
        }
        drop member;
        if resolved is out {
            return .ok(out);
        }
        return .err(ClassfileError.invalid_constant_index);
    }

    pub fn resolve_method_ref(self: &MethodArea, classfile: &ClassFile, constant_index: u16): result<ResolvedMethodRef, ClassfileError> {
        const member = try classfile.member_ref(constant_index);
        var resolved: ?ResolvedMethodRef = none;
        if self.find_class_index(copy member.class_name) is class_index {
            if self.method_index(class_index, copy member.name, copy member.descriptor) is method_index_value {
                resolved = ResolvedMethodRef {
                    class_index: class_index,
                    method_index: method_index_value,
                };
            }
        }
        drop member;
        if resolved is out {
            return .ok(out);
        }
        return .err(ClassfileError.invalid_constant_index);
    }

    pub fn define_array_class(self: &MethodArea, name: string): usize {
        const name_bytes = name.bytes();
        if self.find_class_index(copy name) is existing {
            drop name;
            return existing;
        }

        self.symbols.add(name_bytes);
        var class = derive_array_class(name);
        drop name;
        self.classes.push(copy class);
        const index = self.classes.len() - 1;
        class.clear();
        drop class;
        return index;
    }

    pub fn define_class(self: &MethodArea, classfile: &ClassFile): result<usize, ClassfileError> {
        const name = try classfile.class_name(classfile.this_class);
        if self.find_class_index(copy name) is existing {
            return .ok(existing);
        }

        self.symbols.add(name.bytes());
        drop name;
        var class = try derive_class(classfile);
        class.constant_pool = classfile.clone_constant_pool();
        self.classes.push(class);
        const index = self.classes.len() - 1;
        return .ok(index);
    }

    pub fn load_class_from_bytes(self: &MethodArea, data: []const u8): result<usize, ClassfileError> {
        return self.load_class_from_source(string.from(data));
    }

    pub fn load_class_from_source(self: &MethodArea, source: string): result<usize, ClassfileError> {
        var classfile = new_classfile();
        const source_copy = string.from(source.bytes());
        try parse_classfile(source_copy, &classfile);
        drop source_copy;
        const name = try classfile.class_name(classfile.this_class);
        if self.find_class_index(copy name) is existing {
            return duplicate_loaded_class(existing, source, classfile, name);
        }

        self.symbols.add(name.bytes());
        drop name;
        var class = try derive_class(&classfile);
        class.constant_pool = classfile.clone_constant_pool();
        self.classes.push(class);
        const index = self.classes.len() - 1;
        self.class_sources.push(source);
        return .ok(index);
    }

    pub fn load_class_from_path(self: &MethodArea, root: string, class_name: string): result<usize, MethodAreaError> {
        if self.find_class_index(copy class_name) is existing {
            return .ok(existing);
        }

        var path = class_file_path(root, class_name);
        const read_result = read_file(path);
        drop path;

        switch read_result {
        case .ok(source) {
            const loaded = self.load_class_from_source(source);
            switch loaded {
            case .ok(index) {
                self.load_super_classes(root, index);
                self.define_array_references_for_class(index);
                self.define_descriptor_array_references_for_class(index);
                return .ok(index);
            }
            case .err(err) {
                const ignored = err;
                return .err(MethodAreaError.classfile);
            }
            }
        }
        case .err(err) {
            return .err(method_area_error_from_fs(err));
        }
        }
    }

    pub fn load_class_file(self: &MethodArea, path: string): result<usize, MethodAreaError> {
        self.update_roots_from_class_path(path);
        const read_result = read_file(path);
        switch read_result {
        case .ok(source) {
            const loaded = self.load_class_from_source(source);
            switch loaded {
            case .ok(index) {
                self.load_super_classes(copy self.jdk_class_root, index);
                self.define_array_references_for_class(index);
                self.define_descriptor_array_references_for_class(index);
                return .ok(index);
            }
            case .err(err) {
                const ignored = err;
                return .err(MethodAreaError.classfile);
            }
            }
        }
        case .err(err) {
            return .err(method_area_error_from_fs(err));
        }
        }
    }

    fn update_roots_from_class_path(self: &MethodArea, path: string): void {
        if project_root_from_example_class_path(path) is root {
            self.application_class_root = $"{root}/examples/classes";
            self.jdk_class_root = $"{root}/jdk/classes";
            drop root;
        }
    }

    fn load_super_classes(self: &MethodArea, root: string, class_index: usize): void {
        if class_index >= self.classes.len() {
            return;
        }
        const super_class = copy self.classes[class_index].super_class;
        self.define_descriptor_array_references_for_class(class_index);
        if super_class == "" {
            drop super_class;
            return;
        }
        const loaded = self.load_class_from_path(root, copy super_class);
        drop super_class;
        switch loaded {
        case .ok(index) {
            const ignored = index;
        }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
    }

    pub fn define_builtin_class(self: &MethodArea, name: string): usize {
        if self.find_class_index(name) is existing {
            return existing;
        }
        self.classes.push(builtin_class(name));
        return self.classes.len() - 1;
    }

    pub fn define_hello_world_builtins(self: &MethodArea): void {
        const object_index = self.define_builtin_class_value("java/lang/Object", builtin_object_class());
        const string_index = self.define_builtin_class("java/lang/String");
        const print_stream_index = self.define_builtin_class_value("java/io/PrintStream", builtin_print_stream_class());
        const system_index = self.define_builtin_class_value("java/lang/System", builtin_system_class());
        const string_builder_index = self.define_builtin_class_value("java/lang/StringBuilder", builtin_string_builder_class());
        const ignored = object_index + string_index + print_stream_index + system_index + string_builder_index;
    }

    pub fn load_bootstrap_jdk_classes(self: &MethodArea): void {
        self.load_required_class(copy self.jdk_class_root, "java/lang/Object");
        self.load_required_class(copy self.jdk_class_root, "java/lang/Class");
        self.load_required_class(copy self.jdk_class_root, "java/lang/String");
        self.load_required_class(copy self.jdk_class_root, "java/io/PrintStream");
        self.load_required_class(copy self.jdk_class_root, "java/lang/System");
    }

    pub fn load_constant_references_for_class(self: &MethodArea, root: string, class_index: usize): void {
        var visited: List<usize> = [];
        self.load_constant_references_for_class_visited(root, class_index, &visited);
        visited.clear();
        drop visited;
    }

    fn load_constant_references_for_class_visited(self: &MethodArea, root: string, class_index: usize, visited: &List<usize>): void {
        if class_index >= self.classes.len() {
            return;
        }
        if contains_class_index(visited, class_index) {
            return;
        }
        visited.push(class_index);

        var constant_index: usize = 0;
        while constant_index < self.classes[class_index].constant_pool.len() {
            switch self.classes[class_index].constant_pool[constant_index] {
            case .class_ref(name_index) {
                if (name_index as usize) < self.classes[class_index].constant_pool.len() {
                    switch self.classes[class_index].constant_pool[name_index as usize] {
                    case .utf8(name) {
                        const name_bytes = name.bytes();
                        if name_bytes.len() > 0 {
                            if name_bytes[0] == 91 {
                                const ignored_array = self.define_array_class(string.from(name_bytes));
                            } else {
                                const array_name = array_descriptor_from_class_name(copy name);
                                const ignored_array = self.define_array_class(array_name);
                                const class_name = string.from(name_bytes);
                                const loaded = self.load_class_from_path(root, class_name);
                                drop class_name;
                                switch loaded {
                                case .ok(loaded_index) {
                                    self.load_constant_references_for_class_visited(root, loaded_index, visited);
                                }
                                case .err(error_value) {
                                    const ignored_error = error_value;
                                }
                                }
                            }
                        }
                    }
                    case .unusable(ignored) { const unused = ignored; }
                    case .integer(ignored) { const unused = ignored; }
                    case .float(ignored) { const unused = ignored; }
                    case .long(ignored) { const unused = ignored; }
                    case .double(ignored) { const unused = ignored; }
                    case .class_ref(ignored) { const unused = ignored; }
                    case .string_ref(ignored) { const unused = ignored; }
                    case .field_ref(ignored) { const unused = ignored; }
                    case .method_ref(ignored) { const unused = ignored; }
                    case .interface_method_ref(ignored) { const unused = ignored; }
                    case .name_and_type(ignored) { const unused = ignored; }
                    case .method_handle(ignored) { const unused = ignored; }
                    case .method_type(ignored) { const unused = ignored; }
                    case .dynamic(ignored) { const unused = ignored; }
                    case .invoke_dynamic(ignored) { const unused = ignored; }
                    case .module_ref(ignored) { const unused = ignored; }
                    case .package_ref(ignored) { const unused = ignored; }
                    }
                }
            }
            case .unusable(ignored) { const unused = ignored; }
            case .utf8(ignored) { const unused = ignored; }
            case .integer(ignored) { const unused = ignored; }
            case .float(ignored) { const unused = ignored; }
            case .long(ignored) { const unused = ignored; }
            case .double(ignored) { const unused = ignored; }
            case .string_ref(ignored) { const unused = ignored; }
            case .field_ref(ignored) { const unused = ignored; }
            case .method_ref(ignored) { const unused = ignored; }
            case .interface_method_ref(ignored) { const unused = ignored; }
            case .name_and_type(ignored) { const unused = ignored; }
            case .method_handle(ignored) { const unused = ignored; }
            case .method_type(ignored) { const unused = ignored; }
            case .dynamic(ignored) { const unused = ignored; }
            case .invoke_dynamic(ignored) { const unused = ignored; }
            case .module_ref(ignored) { const unused = ignored; }
            case .package_ref(ignored) { const unused = ignored; }
            }
            constant_index = constant_index + 1;
        }
    }

    fn load_required_class(self: &MethodArea, root: string, class_name: string): void {
        switch self.load_class_from_path(root, class_name) {
        case .ok(index) {
            self.define_array_references_for_class(index);
        }
        case .err(error_value) {
            const ignored = error_value;
        }
        }
    }

    fn define_array_references_for_class(self: &MethodArea, class_index: usize): void {
        if class_index >= self.classes.len() {
            return;
        }
        var constant_index: usize = 0;
        while constant_index < self.classes[class_index].constant_pool.len() {
            switch self.classes[class_index].constant_pool[constant_index] {
            case .class_ref(name_index) {
                if (name_index as usize) < self.classes[class_index].constant_pool.len() {
                    switch self.classes[class_index].constant_pool[name_index as usize] {
                    case .utf8(name) {
                        const name_bytes = name.bytes();
                        if name_bytes.len() > 0 {
                            if name_bytes[0] == 91 {
                                const ignored_array = self.define_array_class(string.from(name_bytes));
                            } else {
                                const array_name = array_descriptor_from_class_name(copy name);
                                const ignored_array = self.define_array_class(array_name);
                            }
                        }
                    }
                    case .unusable(ignored) { const unused = ignored; }
                    case .integer(ignored) { const unused = ignored; }
                    case .float(ignored) { const unused = ignored; }
                    case .long(ignored) { const unused = ignored; }
                    case .double(ignored) { const unused = ignored; }
                    case .class_ref(ignored) { const unused = ignored; }
                    case .string_ref(ignored) { const unused = ignored; }
                    case .field_ref(ignored) { const unused = ignored; }
                    case .method_ref(ignored) { const unused = ignored; }
                    case .interface_method_ref(ignored) { const unused = ignored; }
                    case .name_and_type(ignored) { const unused = ignored; }
                    case .method_handle(ignored) { const unused = ignored; }
                    case .method_type(ignored) { const unused = ignored; }
                    case .dynamic(ignored) { const unused = ignored; }
                    case .invoke_dynamic(ignored) { const unused = ignored; }
                    case .module_ref(ignored) { const unused = ignored; }
                    case .package_ref(ignored) { const unused = ignored; }
                    }
                }
            }
            case .unusable(ignored) { const unused = ignored; }
            case .utf8(ignored) { const unused = ignored; }
            case .integer(ignored) { const unused = ignored; }
            case .float(ignored) { const unused = ignored; }
            case .long(ignored) { const unused = ignored; }
            case .double(ignored) { const unused = ignored; }
            case .string_ref(ignored) { const unused = ignored; }
            case .field_ref(ignored) { const unused = ignored; }
            case .method_ref(ignored) { const unused = ignored; }
            case .interface_method_ref(ignored) { const unused = ignored; }
            case .name_and_type(ignored) { const unused = ignored; }
            case .method_handle(ignored) { const unused = ignored; }
            case .method_type(ignored) { const unused = ignored; }
            case .dynamic(ignored) { const unused = ignored; }
            case .invoke_dynamic(ignored) { const unused = ignored; }
            case .module_ref(ignored) { const unused = ignored; }
            case .package_ref(ignored) { const unused = ignored; }
            }
            constant_index = constant_index + 1;
        }
    }

    fn define_descriptor_array_references_for_class(self: &MethodArea, class_index: usize): void {
        if class_index >= self.classes.len() {
            return;
        }
        var descriptors: List<string> = [];
        var field_index: usize = 0;
        while field_index < self.classes[class_index].fields.len() {
            descriptors.push(copy self.classes[class_index].fields[field_index].descriptor);
            field_index = field_index + 1;
        }
        var method_index: usize = 0;
        while method_index < self.classes[class_index].methods.len() {
            descriptors.push(copy self.classes[class_index].methods[method_index].descriptor);
            method_index = method_index + 1;
        }
        while descriptors.len() > 0 {
            var descriptor = descriptors.pop();
            self.define_descriptor_array_references(descriptor.bytes());
            drop descriptor;
        }
    }

    fn define_descriptor_array_references(self: &MethodArea, descriptor: []const u8): void {
        var index: usize = 0;
        while index < descriptor.len() {
            if descriptor[index] == 91 {
                const end = descriptor_array_end(descriptor, index);
                if end > index {
                    const array_name = string.from(descriptor[index..end]);
                    const ignored_array = self.define_array_class(array_name);
                }
                index = end;
            } else {
                index = index + 1;
            }
        }
    }

    pub fn define_builtin_class_value(self: &MethodArea, name: string, class: Class): usize {
        const ignored_name = name;
        self.classes.push(class);
        return self.classes.len() - 1;
    }

}

fn duplicate_loaded_class(existing: usize, source: string, classfile: ClassFile, name: string): result<usize, ClassfileError> {
    drop name;
    drop classfile;
    drop source;
    return .ok(existing);
}

pub fn new_method_area(): MethodArea {
    return MethodArea {
        classes: [],
        symbols: new_symbol_pool(),
        class_sources: [],
        application_class_root: "examples/classes",
        jdk_class_root: "jdk/classes",
    };
}

fn empty_code(): [:]u8 {
    const native_code: [0]u8 = [];
    return byte_buffer(native_code[..]);
}

fn owned_text(value: []const u8): string {
    return string.from(value);
}

fn builtin_field(class_name: string, name: string, descriptor: string, access: u16, index: u16, slot: u16): Field {
    return Field {
        class_name: owned_text(class_name.bytes()),
        access_flags: field_access_flags(access),
        name: owned_text(name.bytes()),
        descriptor: owned_text(descriptor.bytes()),
        index: index,
        slot: slot,
    };
}

fn builtin_method(class_name: string, name: string, descriptor: string, access: u16, parameter_count: u32, return_descriptor: string): Method {
    return Method {
        class_name: owned_text(class_name.bytes()),
        access_flags: method_access_flags(access),
        name: owned_text(name.bytes()),
        descriptor: owned_text(descriptor.bytes()),
        code: empty_code(),
        max_stack: 0,
        max_locals: 0,
        code_len: 0,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
        parameter_count: parameter_count,
        return_descriptor: owned_text(return_descriptor.bytes()),
    };
}

fn builtin_object_class(): Class {
    const class_object = Reference.init_null();
    var methods: List<Method> = [builtin_method("java/lang/Object", "<init>", "()V", 0x0101, 0, "V")];
    const out = Class {
        name: "java/lang/Object",
        descriptor: "Ljava/lang/Object;",
        access_flags: class_access_flags(0x0021),
        super_class: "",
        interfaces: [],
        fields: [],
        methods: methods,
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "Object.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: class_object,
    };
    return out;
}

fn builtin_print_stream_class(): Class {
    return Class {
        name: "java/io/PrintStream",
        descriptor: "Ljava/io/PrintStream;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [],
        methods: [builtin_method("java/io/PrintStream", "println", "(Ljava/lang/String;)V", 0x0101, 1, "V")],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: "PrintStream.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
}

fn builtin_system_class(): Class {
    const out_field = builtin_field("java/lang/System", "out", "Ljava/io/PrintStream;", 0x0009, 0, 0);
    return Class {
        name: "java/lang/System",
        descriptor: "Ljava/lang/System;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [out_field],
        methods: [builtin_method("java/lang/System", "getProperty", "(Ljava/lang/String;)Ljava/lang/String;", 0x0109, 1, "Ljava/lang/String;")],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [.ref_value(null_ref)],
        source_file: "System.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
}

fn builtin_string_builder_class(): Class {
    const value_field = builtin_field("java/lang/StringBuilder", "value", "Ljava/lang/String;", 0x0001, 0, 0);
    return Class {
        name: "java/lang/StringBuilder",
        descriptor: "Ljava/lang/StringBuilder;",
        access_flags: class_access_flags(0x0021),
        super_class: "java/lang/Object",
        interfaces: [],
        fields: [value_field],
        methods: [
            builtin_method("java/lang/StringBuilder", "<init>", "()V", 0x0101, 0, "V"),
            builtin_method("java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", 0x0101, 1, "Ljava/lang/StringBuilder;"),
            builtin_method("java/lang/StringBuilder", "toString", "()Ljava/lang/String;", 0x0101, 0, "Ljava/lang/String;"),
        ],
        constant_pool: [],
        instance_vars: 1,
        static_vars: [],
        source_file: "StringBuilder.java",
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
}

fn builtin_class(name: string): Class {
    return Class {
        name: string.from(name.bytes()),
        descriptor: class_descriptor_from_name(name),
        access_flags: class_access_flags(0x0021),
        super_class: owned_text("java/lang/Object".bytes()),
        interfaces: [],
        fields: [],
        methods: [],
        constant_pool: [],
        instance_vars: 0,
        static_vars: [],
        source_file: owned_text("".bytes()),
        is_array: false,
        component_type: owned_text("".bytes()),
        element_type: owned_text("".bytes()),
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: Reference.init_null(),
    };
}

fn array_descriptor_from_class_name(name: string): string {
    return $"[L{name};";
}

fn descriptor_array_end(descriptor: []const u8, start: usize): usize {
    var index = start;
    while index < descriptor.len() and descriptor[index] == 91 {
        index = index + 1;
    }
    if index >= descriptor.len() {
        return descriptor.len();
    }
    if descriptor[index] == 76 {
        while index < descriptor.len() and descriptor[index] != 59 {
            index = index + 1;
        }
        if index < descriptor.len() {
            return index + 1;
        }
        return descriptor.len();
    }
    return index + 1;
}

pub fn class_file_path(root: string, class_name: string): string {
    const root_bytes = root.bytes();
    if root_bytes.len() == 0 {
        return $"{class_name}.class";
    }
    if root_bytes[root_bytes.len() - 1] == 47 {
        return $"{root}{class_name}.class";
    }
    return $"{root}/{class_name}.class";
}

pub struct ResolvedFieldRef {
    pub class_index: usize;
    pub field_index: i32;
}

pub struct ResolvedMethodRef {
    pub class_index: usize;
    pub method_index: i32;
}

pub fn first_type(descriptor: []const u8): []const u8 {
    if descriptor.len() == 0 {
        return descriptor;
    }

    const tag = descriptor[0];
    if tag == 66 or tag == 67 or tag == 68 or tag == 70 or tag == 73 or tag == 74 or tag == 83 or tag == 90 or tag == 86 {
        return descriptor[0..1];
    }
    if tag == 76 {
        var index: usize = 1;
        while index < descriptor.len() {
            if descriptor[index] == 59 {
                return descriptor[0..index + 1];
            }
            index = index + 1;
        }
        return descriptor[0..0];
    }
    if tag == 91 {
        const component = first_type(descriptor[1..descriptor.len()]);
        if component.len() == 0 {
            return component;
        }
        return descriptor[0..component.len() + 1];
    }
    return descriptor[0..0];
}

pub fn method_parameter_count(descriptor: []const u8): usize {
    if descriptor.len() == 0 or descriptor[0] != 40 {
        return 0;
    }

    var index: usize = 1;
    var count: usize = 0;
    while index < descriptor.len() and descriptor[index] != 41 {
        const param = first_type(descriptor[index..descriptor.len()]);
        if param.len() == 0 {
            return count;
        }
        count = count + 1;
        index = index + param.len();
    }
    return count;
}

pub fn method_return_descriptor(descriptor: []const u8): []const u8 {
    var index: usize = 0;
    while index < descriptor.len() {
        if descriptor[index] == 41 {
            return descriptor[index + 1..descriptor.len()];
        }
        index = index + 1;
    }
    return descriptor[0..0];
}

pub fn array_component_type(name: []const u8): []const u8 {
    if name.len() == 0 or name[0] != 91 {
        return name[0..0];
    }
    return name[1..name.len()];
}

pub fn array_element_type(name: []const u8): []const u8 {
    if name.len() == 0 or name[0] != 91 {
        return name[0..0];
    }
    var index: usize = 0;
    while index < name.len() {
        if name[index] != 91 {
            return name[index..name.len()];
        }
        index = index + 1;
    }
    return name[0..0];
}

pub fn array_dimensions(name: []const u8): u32 {
    var dimensions: u32 = 1;
    var index: usize = 1;
    if name.len() == 0 or name[0] != 91 {
        return 0;
    }
    while index < name.len() {
        if name[index] == 91 {
            dimensions = dimensions + 1;
        }
        index = index + 1;
    }
    return dimensions;
}

fn class_descriptor_from_name(name: string): string {
    return $"L{name};";
}

pub fn derive_array_class(name: string): Class {
    const name_bytes = name.bytes();
    var fields: List<Field> = [];
    var methods: List<Method> = [];
    var static_vars: List<Value> = [];
    return Class {
        name: string.from(name_bytes),
        descriptor: string.from(name_bytes),
        access_flags: class_access_flags(0x0001),
        super_class: "java/lang/Object",
        interfaces: ["java/io/Serializable", "java/lang/Cloneable"],
        fields: fields,
        methods: methods,
        constant_pool: [],
        instance_vars: 0,
        static_vars: static_vars,
        source_file: "",
        is_array: true,
        component_type: string.from(array_component_type(name_bytes)),
        element_type: string.from(array_element_type(name_bytes)),
        dimensions: array_dimensions(name_bytes),
        defined: true,
        linked: false,
        class_object: null_ref,
    };
}

struct CodeInfo {
    code: [:]u8;
    max_stack: u16;
    max_locals: u16;
    code_len: u32;
    exception_count: u32;
    exception_handlers: List<ExceptionHandler>;
    local_var_count: u32;
    line_number_count: u32;
}

fn empty_code_info(): CodeInfo {
    return CodeInfo {
        code: byte_buffer("".bytes()),
        max_stack: 0,
        max_locals: 0,
        code_len: 0,
        exception_count: 0,
        exception_handlers: [],
        local_var_count: 0,
        line_number_count: 0,
    };
}

fn apply_code_attribute_info(classfile: &ClassFile, name_index: u16, raw: []const u8, info: &CodeInfo): result<void, ClassfileError> {
    const name = try classfile.utf8(name_index);
    var reader = ByteReader.init(raw);
    const is_line_number_table = name == "LineNumberTable";
    const is_local_variable_table = name == "LocalVariableTable";
    if is_line_number_table {
        const count = try reader.read_u2();
        info.line_number_count = info.line_number_count + (count as u32);
        try reader.skip((count as usize) * 4);
    } else {
        if is_local_variable_table {
            const count = try reader.read_u2();
            info.local_var_count = info.local_var_count + (count as u32);
            try reader.skip((count as usize) * 10);
        }
    }
    drop reader;
    drop name;
    return .ok();
}

fn code_info_from_attribute(classfile: &ClassFile, name_index: u16, raw: []const u8): result<CodeInfo, ClassfileError> {
    const name = try classfile.utf8(name_index);
    const is_code = name == "Code";
    drop name;
    if !is_code {
        const out = empty_code_info();
        return .ok(out);
    }

    var reader = ByteReader.init(raw);
    const max_stack = try reader.read_u2();
    const max_locals = try reader.read_u2();
    const code_len = try reader.read_u4();
    const code_start = reader.offset;
    const code = byte_buffer(raw[code_start..code_start + (code_len as usize)]);
    try reader.skip(code_len as usize);
    const exception_count = try reader.read_u2();
    var exception_handlers: List<ExceptionHandler> = [];
    var exception_index: usize = 0;
    while exception_index < exception_count as usize {
        exception_handlers.push(ExceptionHandler {
            start_pc: try reader.read_u2(),
            end_pc: try reader.read_u2(),
            handle_pc: try reader.read_u2(),
            catch_type: try reader.read_u2(),
        });
        exception_index = exception_index + 1;
    }
    var out = CodeInfo {
        code: code,
        max_stack: max_stack,
        max_locals: max_locals,
        code_len: code_len,
        exception_count: exception_count as u32,
        exception_handlers: exception_handlers,
        local_var_count: 0,
        line_number_count: 0,
    };
    const attributes_count = try reader.read_u2();
    var index: usize = 0;
    while index < attributes_count as usize {
        const nested_name_index = try reader.read_u2();
        const nested_length = try reader.read_u4();
        const nested_raw = try reader.read_bytes(nested_length as usize);
        try apply_code_attribute_info(classfile, nested_name_index, nested_raw[..], &out);
        drop nested_raw;
        index = index + 1;
    }
    drop reader;
    return .ok(out);
}

fn member_code_info(classfile: &ClassFile, attributes: []AttributeInfo): result<CodeInfo, ClassfileError> {
    var out = empty_code_info();
    var index: usize = 0;
    while index < attributes.len() {
        const current = try code_info_from_attribute(classfile, attributes[index].name_index, attributes[index].raw[..]);
        if current.code_len != 0 or current.max_stack != 0 or current.max_locals != 0 {
            drop out;
            return .ok(current);
        }
        drop current;
        index = index + 1;
    }
    return .ok(out);
}

fn derive_interfaces_into(classfile: &ClassFile, interfaces: &List<string>): result<void, ClassfileError> {
    const raw_interfaces = classfile.interfaces[..];
    var index: usize = 0;
    while index < raw_interfaces.len() {
        const class_ref_index = raw_interfaces[index] as usize;
        if class_ref_index >= classfile.constant_pool.len() {
            return .err(ClassfileError.invalid_constant_index);
        }
        switch classfile.constant_pool[class_ref_index] {
        case .class_ref(name_index) {
            if name_index as usize >= classfile.constant_pool.len() {
                return .err(ClassfileError.invalid_constant_index);
            }
            switch classfile.constant_pool[name_index as usize] {
            case .utf8(name) {
                var interface_name = string.from(name.bytes());
                interfaces.push(interface_name);
                interface_name = "";
            }
            else { return .err(ClassfileError.invalid_constant_kind); }
            }
        }
        else { return .err(ClassfileError.invalid_constant_kind); }
        }
        index = index + 1;
    }
    return .ok();
}

fn derive_fields(classfile: &ClassFile, class_name: string): result<List<Field>, ClassfileError> {
    var fields: List<Field> = [];
    var static_slot: u16 = 0;
    var instance_slot: u16 = 0;
    const field_infos = classfile.fields[..];
    var index: usize = 0;
    while index < field_infos.len() {
        const descriptor = try classfile.utf8(field_infos[index].descriptor_index);
        const access_flags = field_infos[index].access_flags;
        const is_static = (access_flags & 8) != 0;
        var slot: u16 = instance_slot;
        if is_static {
            slot = static_slot;
            static_slot = static_slot + 1;
        } else {
            instance_slot = instance_slot + 1;
        }
        fields.push(Field {
            class_name: string.from(class_name.bytes()),
            access_flags: field_access_flags(access_flags),
            name: try classfile.utf8(field_infos[index].name_index),
            descriptor: descriptor,
            index: index as u16,
            slot: slot,
        });
        index = index + 1;
    }
    return .ok(fields);
}

fn derive_static_vars(fields: &List<Field>): List<Value> {
    var values: List<Value> = [];
    var index: usize = 0;
    while index < fields.len() {
        const field = &fields[index];
        if field.is_static() {
            values.push(default_value(field.descriptor.bytes()));
        }
        index = index + 1;
    }
    return values;
}

fn instance_var_count(fields: &List<Field>): u16 {
    var count: u16 = 0;
    var index: usize = 0;
    while index < fields.len() {
        const field = &fields[index];
        if !field.is_static() {
            count = count + 1;
        }
        index = index + 1;
    }
    return count;
}

fn derive_source_file(classfile: &ClassFile): result<string, ClassfileError> {
    const attributes = classfile.attributes[..];
    var index: usize = 0;
    while index < attributes.len() {
        const name = try classfile.utf8(attributes[index].name_index);
        if name == "SourceFile" {
            var reader = ByteReader.init(attributes[index].raw[..]);
            const source_file_index = try reader.read_u2();
            const out = try classfile.utf8(source_file_index);
            drop reader;
            drop name;
            return .ok(out);
        }
        drop name;
        index = index + 1;
    }
    return .ok("");
}

fn derive_methods(classfile: &ClassFile, class_name: string): result<List<Method>, ClassfileError> {
    var methods: List<Method> = [];
    const method_infos = classfile.methods[..];
    var index: usize = 0;
    while index < method_infos.len() {
        const descriptor = try classfile.utf8(method_infos[index].descriptor_index);
        const parameter_count = method_parameter_count(descriptor.bytes()) as u32;
        const return_descriptor = string.from(method_return_descriptor(descriptor.bytes()));
        const code = try member_code_info(classfile, method_infos[index].attributes[..]);
        const method_code = byte_buffer(code.code[..]);
        var exception_handlers: List<ExceptionHandler> = [];
        if code.exception_count != 0 {
            exception_handlers = copy code.exception_handlers;
        }
        methods.push(Method {
            class_name: string.from(class_name.bytes()),
            access_flags: method_access_flags(method_infos[index].access_flags),
            name: try classfile.utf8(method_infos[index].name_index),
            descriptor: descriptor,
            code: method_code,
            max_stack: code.max_stack,
            max_locals: code.max_locals,
            code_len: code.code_len,
            exception_count: code.exception_count,
            exception_handlers: exception_handlers,
            local_var_count: code.local_var_count,
            line_number_count: code.line_number_count,
            parameter_count: parameter_count,
            return_descriptor: return_descriptor,
        });
        drop code;
        index = index + 1;
    }
    return .ok(methods);
}

pub fn derive_class(classfile: &ClassFile): result<Class, ClassfileError> {
    const class_name = try classfile.class_name(classfile.this_class);
    var fields = try derive_fields(classfile, class_name);
    var methods = try derive_methods(classfile, class_name);
    var interfaces: List<string> = [];
    try derive_interfaces_into(classfile, &interfaces);
    var super_class = "";
    if classfile.super_class != 0 {
        super_class = try classfile.class_name(classfile.super_class);
    }
    const instance_vars = instance_var_count(&fields);
    const static_vars = derive_static_vars(&fields);
    var out = Class {
        name: string.from(class_name.bytes()),
        descriptor: class_descriptor_from_name(class_name),
        access_flags: class_access_flags(classfile.access_flags),
        super_class: super_class,
        interfaces: interfaces,
        fields: fields,
        methods: methods,
        constant_pool: [],
        instance_vars: instance_vars,
        static_vars: static_vars,
        source_file: try derive_source_file(classfile),
        is_array: false,
        component_type: "",
        element_type: "",
        dimensions: 0,
        defined: true,
        linked: false,
        class_object: null_ref,
    };
    drop class_name;
    return .ok(out);
}

test "method descriptor parser extracts parameter count and return type" {
    const descriptor = "([Ljava/lang/String;I)Ljava/lang/Object;".bytes();
    const first = first_type(descriptor[1..descriptor.len()]);
    assert(first.len() == 19);
    assert(first[0] == 91);
    assert(first[18] == 59);
    assert(method_parameter_count(descriptor) == 2);

    const ret = method_return_descriptor(descriptor);
    assert(ret.len() == 18);
    assert(ret[0] == 76);
    assert(ret[17] == 59);
}

test "method area parses array class descriptor metadata" {
    const name = "[[Ljava/lang/String;";
    var class = derive_array_class(name);

    assert(class.is_array);
    assert(class.name.len() == 20);
    assert(class.descriptor.len() == 20);
    assert(class.super_class.len() == 16);
    assert(class.interfaces.len() == 2);
    const component_type = class.component_type.bytes();
    const element_type = class.element_type.bytes();
    assert(component_type[0] == 91);
    assert(element_type[0] == 76);
    assert(class.dimensions == 2);
    assert(class.fields.len() == 0);
    assert(class.methods.len() == 0);
}

test "symbol pool deduplicates byte names" {
    var pool = new_symbol_pool();
    pool.add("abc".bytes());
    pool.add("abc".bytes());
    assert(pool.contains("abc".bytes()));
    assert(!pool.contains("xyz".bytes()));
    assert(pool.symbols.len() == 1);
    pool.clear();
    drop pool;
}

test "method area defines parsed classes once" {
    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main"),
            .class_ref(1)
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 0,
        interfaces: [],
        fields: [],
        methods: [],
        attributes: [],
    };

    var area = new_method_area();
    const first = try area.define_class(&classfile);
    const second = try area.define_class(&classfile);

    assert(first == 0);
    assert(second == 0);
    assert(area.classes.len() == 1);
    assert(area.has_class("Main"));
    assert(area.symbols.symbols.len() == 1);
}

test "method area synthesizes array classes once" {
    var area = new_method_area();
    const first = area.define_array_class("[I");
    const second = area.define_array_class("[I");

    assert(first == 0);
    assert(second == 0);
    assert(area.classes.len() == 1);
    assert(area.classes[0].is_array);
    const component_type = area.classes[0].component_type.bytes();
    assert(component_type[0] == 73);
    assert(area.has_class("[I"));
}

test "method area loads class from bytes" {
    var data: [:]u8 = [
        0xCA, 0xFE, 0xBA, 0xBE, // magic
        0, 0, 0, 52, // minor, major
        0, 3, // constant_pool_count
        1, 0, 4, 77, 97, 105, 110, // #1 utf8 Main
        7, 0, 1, // #2 class Main
        0, 33, // access_flags
        0, 2, // this_class
        0, 0, // super_class
        0, 0, // interfaces_count
        0, 0, // fields_count
        0, 0, // methods_count
        0, 0 // attributes_count
    ];

    var area = new_method_area();
    const index = try area.load_class_from_bytes(data[..]);
    assert(index == 0);
    assert(area.has_class("Main"));
    assert(area.classes[0].descriptor.len() == 6);
}

test "method area resolves class field and method refs" {
    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main"),
            .class_ref(1),
            .utf8("answer"),
            .utf8("I"),
            .name_and_type(ConstantNameAndType { name_index: 3, descriptor_index: 4 }),
            .field_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 5 }),
            .utf8("run"),
            .utf8("()I"),
            .name_and_type(ConstantNameAndType { name_index: 7, descriptor_index: 8 }),
            .method_ref(ConstantMemberRef { class_index: 2, name_and_type_index: 9 })
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 0,
        interfaces: [],
        fields: [MemberInfo { access_flags: 8, name_index: 3, descriptor_index: 4, attributes: [] }],
        methods: [MemberInfo { access_flags: 9, name_index: 7, descriptor_index: 8, attributes: [] }],
        attributes: [],
    };

    var area = new_method_area();
    const class_index = try area.define_class(&classfile);
    const resolved_class = try area.resolve_class_ref(&classfile, 2);
    const resolved_field = try area.resolve_field_ref(&classfile, 6);
    const resolved_method = try area.resolve_method_ref(&classfile, 10);

    assert(class_index == 0);
    assert(resolved_class == 0);
    assert(resolved_field.class_index == 0);
    assert(resolved_field.field_index == 0);
    assert(resolved_method.class_index == 0);
    assert(resolved_method.method_index == 0);
}

test "class file path builds classpath-relative paths" {
    var relative = class_file_path("classes", "java/lang/Object");
    assert(relative == "classes/java/lang/Object.class");

    var rooted = class_file_path("classes/", "Main");
    assert(rooted == "classes/Main.class");

    var bare = class_file_path("", "Main");
    assert(bare == "Main.class");

    drop relative;
    drop rooted;
    drop bare;
}

test "method area derives class metadata from classfile" {
    var code_raw: [:]u8 = [
        0, 2, // max_stack
        0, 1, // max_locals
        0, 0, 0, 2, // code_length
        4, 172, // iconst_1, ireturn
        0, 0, // exception_table_length
        0, 2, // attributes_count
        0, 15, // LineNumberTable name_index
        0, 0, 0, 6, // LineNumberTable length
        0, 1, // line_number_table_length
        0, 0, // start_pc
        0, 42, // line_number
        0, 16, // LocalVariableTable name_index
        0, 0, 0, 12, // LocalVariableTable length
        0, 1, // local_variable_table_length
        0, 0, // start_pc
        0, 2, // length
        0, 10, // name_index
        0, 8, // descriptor_index
        0, 0 // index
    ];

    var source_raw: [:]u8 = [0, 14];

    var classfile = ClassFile {
        minor_version: 0,
        major_version: 52,
        constant_pool: [
            .unusable(0),
            .utf8("Main"),
            .class_ref(1),
            .utf8("java/lang/Object"),
            .class_ref(3),
            .utf8("Runnable"),
            .class_ref(5),
            .utf8("answer"),
            .utf8("I"),
            .utf8("value"),
            .utf8("run"),
            .utf8("()I"),
            .utf8("Code"),
            .utf8("SourceFile"),
            .utf8("Main.java"),
            .utf8("LineNumberTable"),
            .utf8("LocalVariableTable")
        ],
        access_flags: 33,
        this_class: 2,
        super_class: 4,
        interfaces: [6],
        fields: [MemberInfo { access_flags: 8, name_index: 7, descriptor_index: 8, attributes: [] }, MemberInfo { access_flags: 1, name_index: 9, descriptor_index: 8, attributes: [] }],
        methods: [MemberInfo { access_flags: 9, name_index: 10, descriptor_index: 11, attributes: [AttributeInfo { name_index: 12, length: 44, raw: byte_buffer(code_raw[..]) }] }],
        attributes: [AttributeInfo { name_index: 13, length: 2, raw: byte_buffer(source_raw[..]) }],
    };

    var class = try derive_class(&classfile);
    assert(class.name.bytes()[0] == 77);
    assert(class.descriptor.len() == 6);
    assert(class.descriptor.bytes()[0] == 76);
    assert(class.super_class.bytes()[0] == 106);
    assert(class.source_file.bytes()[0] == 77);
    assert(class.source_file.bytes().len() == 9);
    assert(class.interfaces.len() == 1);
    assert(class.interfaces[0].bytes()[0] == 82);
    assert(class.fields.len() == 2);
    assert(class.fields[0].is_static());
    assert(class.fields[0].slot == 0);
    assert(!class.fields[1].is_static());
    assert(class.fields[1].slot == 0);
    assert(class.instance_vars == 1);
    assert(class.static_vars.len() == 1);
    switch class.static_vars[0] {
    case .int_value(value) { assert(value == 0); }
    case .byte_value(value) { const ignored = value; assert(false); }
    case .short_value(value) { const ignored = value; assert(false); }
    case .char_value(value) { const ignored = value; assert(false); }
    case .long_value(value) { const ignored = value; assert(false); }
    case .float_value(value) { const ignored = value; assert(false); }
    case .double_value(value) { const ignored = value; assert(false); }
    case .boolean_value(value) { const ignored = value; assert(false); }
    case .return_address_value(value) { const ignored = value; assert(false); }
    case .ref_value(value) { const ignored = value; assert(false); }
    }
    assert(class.methods.len() == 1);
    assert(class.methods[0].max_stack == 2);
    assert(class.methods[0].max_locals == 1);
    assert(class.methods[0].code_len == 2);
    assert(class.methods[0].code[0] == 4);
    assert(class.methods[0].code[1] == 172);
    assert(class.methods[0].line_number_count == 1);
    assert(class.methods[0].local_var_count == 1);
    assert(class.methods[0].parameter_count == 0);
    assert(class.methods[0].return_descriptor.bytes()[0] == 73);
    class.clear();
    drop class;
    classfile.clear();
    drop classfile;
}

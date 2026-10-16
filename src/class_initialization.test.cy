import { InitializationDecision, new_class_initializers } from .class_initialization;

test "class initialization tracks recursive ownership and completion" {
    const initializers = new_class_initializers();
    assert(initializers.begin(1) == InitializationDecision.run_initializer);
    assert(initializers.begin(1) == InitializationDecision.recursive);
    initializers.finish(1, true);
    assert(initializers.begin(1) == InitializationDecision.complete);
    initializers.destroy();
}

test "class initialization does not retry a failed initializer" {
    const initializers = new_class_initializers();
    assert(initializers.begin(1) == InitializationDecision.run_initializer);
    initializers.finish(1, false);
    assert(initializers.begin(1) == InitializationDecision.failed);
    initializers.destroy();
}

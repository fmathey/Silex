#include <cstdint>
#include <cstdlib>
#include <iostream>

[[noreturn, gnu::cold, gnu::noinline]] void integerRuntimeError(const char* message) {
    std::cerr << "integer benchmark runtime error: " << message << '\n';
    std::exit(1);
}

template <typename T> inline T checkedAdd(T left, T right) {
    T result;
    if (__builtin_add_overflow(left, right, &result)) [[unlikely]] {
        integerRuntimeError("integer overflow in addition");
    }
    return result;
}

template <typename T> inline T checkedSubtract(T left, T right) {
    T result;
    if (__builtin_sub_overflow(left, right, &result)) [[unlikely]] {
        integerRuntimeError("integer overflow in subtraction");
    }
    return result;
}

struct Component {
    std::int64_t position;
    std::int64_t velocity;
    std::int64_t acceleration;
};

inline void updateComponent(Component& component) {
    component.velocity = checkedAdd(component.velocity, component.acceleration);
    if (component.velocity > 1000) {
        component.acceleration = -3;
    }
    if (component.velocity < -1000) {
        component.acceleration = 3;
    }

    component.position = checkedAdd(component.position, component.velocity);
    if (component.position > 1000000) {
        component.position = checkedSubtract(component.position, std::int64_t{1000000});
    }
    if (component.position < -1000000) {
        component.position = checkedAdd(component.position, std::int64_t{1000000});
    }
}

int main() {
    Component component0 { 0, -1000, 3 };
    Component component1 { 100, -750, -3 };
    Component component2 { 200, -500, 3 };
    Component component3 { 300, -250, -3 };
    Component component4 { 400, 0, 3 };
    Component component5 { 500, 250, -3 };
    Component component6 { 600, 500, 3 };
    Component component7 { 700, 750, -3 };
    std::int64_t batch = 0;

    while (batch < 2500000) {
        updateComponent(component0);
        updateComponent(component1);
        updateComponent(component2);
        updateComponent(component3);
        updateComponent(component4);
        updateComponent(component5);
        updateComponent(component6);
        updateComponent(component7);
        batch = checkedAdd(batch, std::int64_t{1});
    }

    const std::int64_t positionChecksum = checkedAdd(
        checkedAdd(
            checkedAdd(component0.position, component1.position),
            checkedAdd(component2.position, component3.position)
        ),
        checkedAdd(
            checkedAdd(component4.position, component5.position),
            checkedAdd(component6.position, component7.position)
        )
    );
    const std::int64_t velocityChecksum = checkedAdd(
        checkedAdd(
            checkedAdd(component0.velocity, component1.velocity),
            checkedAdd(component2.velocity, component3.velocity)
        ),
        checkedAdd(
            checkedAdd(component4.velocity, component5.velocity),
            checkedAdd(component6.velocity, component7.velocity)
        )
    );
    std::cout << positionChecksum << '\n' << velocityChecksum << '\n';
}

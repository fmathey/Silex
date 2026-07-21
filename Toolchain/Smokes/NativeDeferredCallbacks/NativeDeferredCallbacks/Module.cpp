#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <thread>
#include <vector>
#include <SilexNative/NativeDeferredCallbacks.h>

extern "C" std::int64_t silexGeneratedLiveDeferredCallbackContexts();
extern "C" std::int64_t silexGeneratedLiveDeferredCallbackEvents();
extern "C" std::int64_t silexGeneratedLiveCapturedValueStates();
extern "C" std::int64_t silexGeneratedAcceptedDeferredCallbackEvents();
extern "C" std::int64_t silexGeneratedDispatchedDeferredCallbackEvents();
extern "C" std::int64_t silexGeneratedDestroyedDeferredCallbackEvents();
extern "C" std::int64_t silexGeneratedCancelledDeferredCallbackEnqueues();
extern "C" void silexGeneratedArmDeferredCallbackEnqueueTestGate();
extern "C" void silexGeneratedWaitForDeferredCallbackEnqueueTestGate();
extern "C" void silexGeneratedReleaseDeferredCallbackEnqueueTestGate();

struct SilexNative_NativeDeferredCallbacks_Watch {
    void (*callback)(void*, std::int64_t);
    void* context;
    std::thread::id ownerThread;
    std::vector<std::thread> workers;
    std::atomic<bool> releaseWorkers{false};
    std::atomic<std::int64_t> firstWaveCount{0};
    std::atomic<std::int64_t> completedWorkers{0};
    std::int64_t expectedWorkers = 0;

    SilexNative_NativeDeferredCallbacks_Watch(
        void (*callback)(void*, std::int64_t),
        void* context
    );
    ~SilexNative_NativeDeferredCallbacks_Watch();
};

namespace {

SilexNative_NativeDeferredCallbacks_Watch* activeWatch = nullptr;
std::atomic<std::int64_t> attemptedCallbacks{0};
std::atomic<std::int64_t> acceptedCallbacks{0};
std::atomic<std::int64_t> lateCallbacks{0};
std::atomic<std::int64_t> destroyedWatches{0};
std::atomic<std::int64_t> liveCallbacks{0};
std::atomic<std::int64_t> liveContexts{0};
std::atomic<std::int64_t> liveEvents{0};
std::atomic<std::int64_t> liveResources{0};
std::atomic<std::int64_t> liveWorkers{0};

void reportNullReturnCleanup() {
    std::printf(
        "null deferred cleanup %lld %lld %lld\n",
        static_cast<long long>(silexGeneratedLiveDeferredCallbackContexts()),
        static_cast<long long>(silexGeneratedLiveDeferredCallbackEvents()),
        static_cast<long long>(silexGeneratedLiveCapturedValueStates())
    );
}

void invokeCallback(
    SilexNative_NativeDeferredCallbacks_Watch* watch,
    std::int64_t value,
    bool late
) {
    attemptedCallbacks.fetch_add(1, std::memory_order_relaxed);
    if (late) {
        lateCallbacks.fetch_add(1, std::memory_order_relaxed);
    } else {
        acceptedCallbacks.fetch_add(1, std::memory_order_relaxed);
    }
    liveEvents.fetch_add(1, std::memory_order_relaxed);
    watch->callback(watch->context, value);
    liveEvents.fetch_sub(1, std::memory_order_relaxed);
}

void finishWorker(SilexNative_NativeDeferredCallbacks_Watch* watch) {
    watch->completedWorkers.fetch_add(1, std::memory_order_release);
    liveWorkers.fetch_sub(1, std::memory_order_relaxed);
}

} // namespace

SilexNative_NativeDeferredCallbacks_Watch::SilexNative_NativeDeferredCallbacks_Watch(
    void (*callbackValue)(void*, std::int64_t),
    void* contextValue
)
    : callback(callbackValue)
    , context(contextValue)
    , ownerThread(std::this_thread::get_id()) {
    liveCallbacks.fetch_add(1, std::memory_order_relaxed);
    liveContexts.fetch_add(1, std::memory_order_relaxed);
    liveResources.fetch_add(1, std::memory_order_relaxed);
}

SilexNative_NativeDeferredCallbacks_Watch::~SilexNative_NativeDeferredCallbacks_Watch() {
    for (std::thread& worker : workers) {
        if (worker.joinable()) worker.join();
    }
    liveCallbacks.fetch_sub(1, std::memory_order_relaxed);
    liveContexts.fetch_sub(1, std::memory_order_relaxed);
    liveResources.fetch_sub(1, std::memory_order_relaxed);
}

extern "C" SilexNative_NativeDeferredCallbacks_Watch*
silexNative_NativeDeferredCallbacks_start_watch(
    void (*callback)(void*, std::int64_t),
    void* callbackContext
) {
    activeWatch = new SilexNative_NativeDeferredCallbacks_Watch(callback, callbackContext);
    return activeWatch;
}

extern "C" SilexNative_NativeDeferredCallbacks_Watch*
silexNative_NativeDeferredCallbacks_create_ordinary_watch() {
    return new SilexNative_NativeDeferredCallbacks_Watch(nullptr, nullptr);
}

extern "C" SilexNative_NativeDeferredCallbacks_Watch*
silexNative_NativeDeferredCallbacks_start_null_watch(
    void (*callback)(void*, std::int64_t),
    void* callbackContext
) {
    std::atexit(reportNullReturnCleanup);
    callback(callbackContext, 17);
    return nullptr;
}

extern "C" void silexNative_NativeDeferredCallbacks_emit(std::int64_t value) {
    if (activeWatch == nullptr) return;
    invokeCallback(activeWatch, value, false);
}

extern "C" void silexNative_NativeDeferredCallbacks_start_workers(
    std::int64_t producerCount,
    std::int64_t eventsPerProducer
) {
    auto* watch = activeWatch;
    watch->expectedWorkers = producerCount;
    watch->workers.reserve(static_cast<std::size_t>(producerCount));
    for (std::int64_t producer = 0; producer < producerCount; ++producer) {
        watch->workers.emplace_back([watch, producer, eventsPerProducer]() {
            liveWorkers.fetch_add(1, std::memory_order_relaxed);
            invokeCallback(watch, producer * 100000, false);
            watch->firstWaveCount.fetch_add(1, std::memory_order_release);
            while (!watch->releaseWorkers.load(std::memory_order_acquire)) {
                std::this_thread::yield();
            }
            for (std::int64_t sequence = 1; sequence < eventsPerProducer; ++sequence) {
                invokeCallback(watch, producer * 100000 + sequence, false);
            }
            finishWorker(watch);
        });
    }
}

extern "C" void silexNative_NativeDeferredCallbacks_start_cancellation_workers(
    std::int64_t producerCount
) {
    auto* watch = activeWatch;
    watch->expectedWorkers = producerCount;
    watch->workers.reserve(static_cast<std::size_t>(producerCount));
    for (std::int64_t producer = 0; producer < producerCount; ++producer) {
        watch->workers.emplace_back([watch, producer]() {
            liveWorkers.fetch_add(1, std::memory_order_relaxed);
            invokeCallback(watch, producer, false);
            watch->firstWaveCount.fetch_add(1, std::memory_order_release);
            while (!watch->releaseWorkers.load(std::memory_order_acquire)) {
                std::this_thread::yield();
            }
            invokeCallback(watch, 100000 + producer, true);
            finishWorker(watch);
        });
    }
}

extern "C" bool silexNative_NativeDeferredCallbacks_first_wave_ready() {
    return activeWatch->firstWaveCount.load(std::memory_order_acquire) ==
        activeWatch->expectedWorkers;
}

extern "C" void silexNative_NativeDeferredCallbacks_release_workers() {
    activeWatch->releaseWorkers.store(true, std::memory_order_release);
}

extern "C" void silexNative_NativeDeferredCallbacks_engage_cancellation_workers() {
    silexGeneratedArmDeferredCallbackEnqueueTestGate();
    activeWatch->releaseWorkers.store(true, std::memory_order_release);
    silexGeneratedWaitForDeferredCallbackEnqueueTestGate();
}

extern "C" bool silexNative_NativeDeferredCallbacks_workers_done() {
    return activeWatch->completedWorkers.load(std::memory_order_acquire) ==
        activeWatch->expectedWorkers;
}

extern "C" void silexNative_NativeDeferredCallbacks_yield_workers() {
    std::this_thread::yield();
}

extern "C" bool silexNative_NativeDeferredCallbacks_on_owner_thread() {
    return activeWatch != nullptr &&
        std::this_thread::get_id() == activeWatch->ownerThread;
}

extern "C" void silexNative_NativeDeferredCallbacks_stop_watch(
    SilexNative_NativeDeferredCallbacks_Watch* watch
) {
    silexGeneratedReleaseDeferredCallbackEnqueueTestGate();
    if (watch->callback != nullptr) invokeCallback(watch, -1, true);
    watch->releaseWorkers.store(true, std::memory_order_release);
    if (activeWatch == watch) activeWatch = nullptr;
    delete watch;
    destroyedWatches.fetch_add(1, std::memory_order_relaxed);
}

extern "C" void silexNative_NativeDeferredCallbacks_reset_counters() {
    attemptedCallbacks.store(0, std::memory_order_relaxed);
    acceptedCallbacks.store(0, std::memory_order_relaxed);
    lateCallbacks.store(0, std::memory_order_relaxed);
    destroyedWatches.store(0, std::memory_order_relaxed);
}

extern "C" std::int64_t silexNative_NativeDeferredCallbacks_attempted_callbacks() {
    return attemptedCallbacks.load(std::memory_order_relaxed);
}

extern "C" std::int64_t silexNative_NativeDeferredCallbacks_accepted_callbacks() {
    return acceptedCallbacks.load(std::memory_order_relaxed);
}

extern "C" std::int64_t silexNative_NativeDeferredCallbacks_late_callbacks() {
    return lateCallbacks.load(std::memory_order_relaxed);
}

extern "C" std::int64_t silexNative_NativeDeferredCallbacks_destroyed_watches() {
    return destroyedWatches.load(std::memory_order_relaxed);
}

extern "C" bool silexNative_NativeDeferredCallbacks_runtime_counts_zero() {
    return liveCallbacks.load(std::memory_order_relaxed) == 0 &&
        liveContexts.load(std::memory_order_relaxed) == 0 &&
        liveEvents.load(std::memory_order_relaxed) == 0 &&
        liveResources.load(std::memory_order_relaxed) == 0 &&
        liveWorkers.load(std::memory_order_relaxed) == 0;
}

extern "C" std::int64_t
silexNative_NativeDeferredCallbacks_generated_live_contexts() {
    return silexGeneratedLiveDeferredCallbackContexts();
}

extern "C" std::int64_t
silexNative_NativeDeferredCallbacks_generated_live_events() {
    return silexGeneratedLiveDeferredCallbackEvents();
}

extern "C" std::int64_t
silexNative_NativeDeferredCallbacks_generated_live_capture_states() {
    return silexGeneratedLiveCapturedValueStates();
}

extern "C" std::int64_t
silexNative_NativeDeferredCallbacks_generated_accepted_events() {
    return silexGeneratedAcceptedDeferredCallbackEvents();
}

extern "C" std::int64_t
silexNative_NativeDeferredCallbacks_generated_dispatched_events() {
    return silexGeneratedDispatchedDeferredCallbackEvents();
}

extern "C" std::int64_t
silexNative_NativeDeferredCallbacks_generated_destroyed_events() {
    return silexGeneratedDestroyedDeferredCallbackEvents();
}

extern "C" std::int64_t
silexNative_NativeDeferredCallbacks_generated_cancelled_enqueues() {
    return silexGeneratedCancelledDeferredCallbackEnqueues();
}

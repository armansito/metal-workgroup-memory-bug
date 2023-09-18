#include <metal_stdlib>

using namespace metal;

kernel void entry_point(uint3               local_id    [[thread_position_in_threadgroup]],
                        device uint&        flag        [[buffer(0)]],
                        device atomic_uint& output      [[buffer(1)]],
                        threadgroup uint&   shared_flag [[threadgroup(0)]]) {
    if (local_id.x == 0u) {
        shared_flag = 0xffffffffu;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (local_id.x == 0u) {
        shared_flag = flag;
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);
    uint abort = shared_flag;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (abort != 0u) {
        return;
    }

    atomic_fetch_add_explicit(&output, 1, memory_order_relaxed);
}

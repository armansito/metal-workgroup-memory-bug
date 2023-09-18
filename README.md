The code in this repository demonstrates a bug in the Metal shader compiler that omits a necessary
load from threadgroup shared memory in the presence of a branch and a memory barrier. The issue is
reproduced when shared memory is declared as dynamic (i.e. as an entry-point parameter) but NOT when
it is declared as a local variable.

## Running the program

To run the broken shader using dynamic threadgroup memory:
```
$ cargo run --features broken
```

To run the working shader using a fixed-sized local threadgroup variable:
```
$ cargo run
```

## The erroneous program

The broken program looks like this (see `wg-mem-as-arg.metal`):

```Metal
kernel void entry_point(uint3               local_id    [[thread_position_in_threadgroup]],
                        constant uint&      flag        [[buffer(0)]],
                        device atomic_uint& output      [[buffer(1)]],
                        threadgroup uint&   shared_flag [[threadgroup(0)]]) {
    shared_flag = 0xffffffffu;
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
```

This program does the following:

1. Initialize a threadgroup shared variable called `shared_flag` to all 1s and execute a barrier.
Following the barrier, this value is expected to be visible to all threads in the threadgroup.

⚠️  NOTE: This technically causes undefined behavior since all threads write to the same variable. If
I change only one thread to perform a write than the compiled AIR changes to the expected behavior.
This is subtle but interesting nonetheless.

2. Conditionally assign the value of `flag` to `shared_flag`. `flag` is a uniform variable stored
in global memory and it always holds the value `0`, which is assigned by the CPU before the dispatch.
The assignment is performed only by the first thread in the thread group (i.e. `local_id.x == 0u` is
true).

3. Execute a barrier, load the value of `shared_flag` into a new local variable called `abort`, and
execute a barrier again. The expectation is that the assignment into `shared_flag` in the first
conditional is visible to all threads during the load. Following the second barrier, all threads in
a thread group should see the same value for `abort`, which is expected to be 0.

4. Exit if `abort` is not 0. Otherwise, increment device memory atomic (`output`) by 1.

Because `flag` always contains 0 and because all assignments and loads over `shared_flag` are
synchronized, the final atomic increment should always execute. The CPU side dispatches 10
thread groups with 64 threads each.

The expected value of `output` is 640, however the program above produces 10. I tested this on both
Apple M1 Pro and M1 Max. However, if I change the entry-point declaration to use a local threadgroup
variable, I get the correct result:

```Metal
kernel void entry_point(uint3               local_id [[thread_position_in_threadgroup]],
                        constant uint&      flag     [[buffer(0)]],
                        device atomic_uint& output   [[buffer(1)]]) {
    threadgroup uint shared_flag = 0xffffffffu;
    threadgroup_barrier(mem_flags::mem_threadgroup);
...
```

## Looking at the LLVM disassembly of the shader AIR

A comparison of the compiled AIR from both shaders reveals something interesting. The working
version of the program has thread group memory loads/stores and barriers in the expected places:

`wg-mem-as-local.air.ll`:
```LLVM
; @shared_flag is
; @_ZZ11entry_pointDv3_jRU11MTLconstantKjRU9MTLdeviceN5metal7_atomicIjvEEE11shared_flag
; in the source
;
; Initialize shared_flag to 0xffffffff or -1
@shared_flag = internal unnamed_addr addrspace(3) global i32 -1, align 4

; Function Attrs: convergent nounwind
define void @entry_point(
    <3 x i32> %0,
    ptr addrspace(2) noalias nocapture readonly dereferenceable(4) %1,
    ptr addrspace(1) noalias nocapture dereferenceable(4) %2) local_unnamed_addr #0 {
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; first barrier
  %4 = extractelement <3 x i32> %0, i64 0                            ; if (local_id.x == 0)
  %5 = icmp eq i32 %4, 0                                             ; ,,
  br i1 %5, label %6, label %8                                       ; ,,

6:                                                ; preds = %3       ; {
  %7 = load i32, ptr addrspace(2) %1, align 4, !tbaa !22             ;     // load `flag` (%7)
  store i32 %7, ptr addrspace(3) @shared_flag, align 4, !tbaa !22    ;     shared_flag = %7;
  br label %8                                                        ; }

8:                                                ; preds = %6, %3
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; barrier
  %9 = load i32, ptr addrspace(3) @shared_flag, align 4, !tbaa !22   ; // load `shared_flag` (%9)
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; barrier
  %10 = icmp eq i32 %9, 0                                            ; if (%9 == 0) {
  br i1 %10, label %11, label %14                                    ; // label %11 increments `output`
                                                                     ; // and carries on to label %14.
                                                                     ; // label %14 returns
```

Now look at the broken version of the program, which uses dynamic thread group memory:

`wg-mem-as-arg.air.ll`
```LLVM
; Function Attrs: convergent nounwind
define void @entry_point(
    <3 x i32> %0,
    ptr addrspace(2) noalias nocapture readonly dereferenceable(4) %1,
    ptr addrspace(1) noalias nocapture dereferenceable(4) %2,
    ptr addrspace(3) noalias nocapture dereferenceable(4) %3) local_unnamed_addr #0 {
  store i32 -1, ptr addrspace(3) %3, align 4, !tbaa !23              ; shared_flag = -1
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; barrier
  %5 = extractelement <3 x i32> %0, i64 0                            ; if (local_id.x) == 0)
  %6 = icmp eq i32 %5, 0                                             ; ,,
  br i1 %6, label %7, label %10                                      ; ,,

7:                                                ; preds = %4       ; {
  %8 = load i32, ptr addrspace(2) %1, align 4, !tbaa !23             ;     // load `flag` (%8)
  store i32 %8, ptr addrspace(3) %3, align 4, !tbaa !23              ;     shared_flag = %8
  %9 = icmp eq i32 %8, 0                                             ;     %9 = (%8 == 0)
  br label %10                                                       ; }

10:                                               ; preds = %7, %4
  %11 = phi i1 [ %9, %7 ], [ false, %4 ]                             ; // Pick %9 if the branch was
                                                                     ; // taken. Otherwise pick `false`
                                                                     ; // This value is %11
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; barrier
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; barrier
  br i1 %11, label %12, label %15                                    ; // label %12 increments `output`
                                                                     ; // and carries on to label %15.
                                                                     ; // label %15 returns
```
This looks very different. In particular, the decision to return (i.e. the value of `%11` based on
whether or not `shared_flag == 0`) is non-uniform and potentially differs depending on whether the
branch was taken. It involves no loads from thread group memory and the condition to return has been
elided to be based on the value of `flag` at the time of the assignment. The two successive barrier
calls have no meaningful effect since the value of `shared_flag` is never read.

Based on this, it should be obvious that the first thread of each thread group will take the branch and
execute `%7` but all other threads will branch directly to `%10`. `%11` will be `true` for the first
thread in all thread groups and `false` for all others. This explains why the output is `10` instead
of `640`.

This is observable with any thread group count. For a thread group count of `N`, I've observed that
the broken program outputs `N` while the working program outputs `N * 64` (the expected result).

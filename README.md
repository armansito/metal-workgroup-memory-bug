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
```

This program does the following:

1. Initialize a threadgroup shared variable called `shared_flag` to all 1s and execute a barrier.
Following the barrier, this value is expected to be visible to all threads in the threadgroup. Only
one thread is designated to perform the assignment and the assignment should be well-defined.

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
thread groups with 96 threads each.

The expected value of `output` is 960, however the program above produces 320. In fact, the result is
320 no matter how large the thread groups are.

I tested this on both
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
    ptr addrspace(1) noalias nocapture readonly dereferenceable(4) %1,
    ptr addrspace(1) noalias nocapture dereferenceable(4) %2,
    ptr addrspace(3) noalias nocapture dereferenceable(4) %3) local_unnamed_addr #0 {
  %5 = extractelement <3 x i32> %0, i64 0                            ; if (local_id.x == 0)
  %6 = icmp eq i32 %5, 0                                             ; ,,
  br i1 %6, label %7, label %8                                       ; ,,

7:                                                ; preds = %4       ; {
  store i32 -1, ptr addrspace(3) %3, align 4, !tbaa !23              ;     shared_flag = -1;
  br label %8                                                        ; }

8:                                                ; preds = %7, %4
  %9 = phi i1 [ true, %7 ], [ false, %4 ]                            ; // %9 represents whether the
                                                                     ; // the branch was taken. I.e.,
                                                                     ; // %9 = (local_id.x == 0u);
                                                                     ;
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; // barrier
  br i1 %9, label %12, label %10                                     ; if (local_id.x != 0u) {

10:                                               ; preds = %8       ; {
  %11 = load i32, ptr addrspace(3) %3, align 4, !tbaa !23            ;    %11 = shared_flag;
  br label %14

12:                                               ; preds = %8       ; } else {
  %13 = load i32, ptr addrspace(1) %1, align 4, !tbaa !23            ;    %13 = flag;
  store i32 %13, ptr addrspace(3) %3, align 4, !tbaa !23             ;    shared_flag = %13;
  br label %14                                                       ; }

14:                                               ; preds = %12, %10
  %15 = phi i32 [ %11, %10 ], [ %13, %12 ]                           ; // Pick the value of `shared_flag` (%11)
                                                                     ; // if (local_id.x != 0u). Otherwise pick
                                                                     ; // the value of `flag` (%13).
                                                                     ; // This value is %15.
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; barrier
  tail call void @air.wg.barrier(i32 2, i32 1) #1                    ; barrier
  %16 = icmp eq i32 %15, 0                                           ; // increment output if `%15` is 0u.
  br i1 %16, label %17, label %20                                    ; // otherwise return
```
This looks very different. In particular, the decision to return (i.e. the value of `%15` based on
whether or not `local_id.x == 0u`) is non-uniform is based on the value of `shared_flag` or `flag`
depending on whether the branch was taken without taking the store (`shared_flag = flag`) and the
following barrier into account. The two successive barrier calls have no meaningful effect since the
value of `shared_flag` is loaded only in one of the branches and BEFORE the barriers.

Based on this, the value of `%15` appears to be racy though should always be `0u` if
`local_id.x == 0u`.

It is interesting that the total count is always 320 no matter how big the thread groups are. This
could possibly be explained by a lack of a race condition among the threads within a SIMD group
(which has the size of 32 on M1), so that all threads in the the SIMD group that `local_id.x == 0u`
falls on observe the store into `shared_flag` even if they are masked off during the store
instruction. This is mostly speculation but it is plausible.

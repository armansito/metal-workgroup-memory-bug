; ModuleID = 'wg-mem-as-local.air'
source_filename = "wg-mem-as-local.metal"
target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"
target triple = "air64-apple-macosx13.0.0"

%"struct.metal::_atomic" = type { i32 }

@_ZZ11entry_pointDv3_jRU11MTLconstantKjRU9MTLdeviceN5metal7_atomicIjvEEE11shared_flag = internal unnamed_addr addrspace(3) global i32 -1, align 4

; Function Attrs: convergent nounwind
define void @entry_point(<3 x i32> %0, ptr addrspace(2) noalias nocapture readonly dereferenceable(4) %1, ptr addrspace(1) noalias nocapture dereferenceable(4) %2) local_unnamed_addr #0 {
  tail call void @air.wg.barrier(i32 2, i32 1) #1
  %4 = extractelement <3 x i32> %0, i64 0
  %5 = icmp eq i32 %4, 0
  br i1 %5, label %6, label %8

6:                                                ; preds = %3
  %7 = load i32, ptr addrspace(2) %1, align 4, !tbaa !22
  store i32 %7, ptr addrspace(3) @_ZZ11entry_pointDv3_jRU11MTLconstantKjRU9MTLdeviceN5metal7_atomicIjvEEE11shared_flag, align 4, !tbaa !22
  br label %8

8:                                                ; preds = %6, %3
  tail call void @air.wg.barrier(i32 2, i32 1) #1
  %9 = load i32, ptr addrspace(3) @_ZZ11entry_pointDv3_jRU11MTLconstantKjRU9MTLdeviceN5metal7_atomicIjvEEE11shared_flag, align 4, !tbaa !22
  tail call void @air.wg.barrier(i32 2, i32 1) #1
  %10 = icmp eq i32 %9, 0
  br i1 %10, label %11, label %14

11:                                               ; preds = %8
  %12 = getelementptr inbounds %"struct.metal::_atomic", ptr addrspace(1) %2, i64 0, i32 0
  %13 = tail call i32 @air.atomic.global.add.u.i32(ptr addrspace(1) nocapture %12, i32 1, i32 0, i32 2, i1 true) #2
  br label %14

14:                                               ; preds = %11, %8
  ret void
}

; Function Attrs: convergent nounwind
declare void @air.wg.barrier(i32, i32) local_unnamed_addr #1

; Function Attrs: nounwind memory(argmem: readwrite)
declare i32 @air.atomic.global.add.u.i32(ptr addrspace(1) nocapture, i32, i32, i32, i1) local_unnamed_addr #2

attributes #0 = { convergent nounwind "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "frame-pointer"="all" "less-precise-fpmad"="false" "no-infs-fp-math"="true" "no-jump-tables"="false" "no-nans-fp-math"="true" "no-signed-zeros-fp-math"="true" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "unsafe-fp-math"="true" "use-soft-float"="false" }
attributes #1 = { convergent nounwind }
attributes #2 = { nounwind memory(argmem: readwrite) }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7}
!air.kernel = !{!8}
!air.compile_options = !{!15, !16, !17}
!llvm.ident = !{!18}
!air.version = !{!19}
!air.language_version = !{!20}
!air.source_file_name = !{!21}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 13, i32 3]}
!1 = !{i32 1, !"wchar_size", i32 4}
!2 = !{i32 7, !"air.max_device_buffers", i32 31}
!3 = !{i32 7, !"air.max_constant_buffers", i32 31}
!4 = !{i32 7, !"air.max_threadgroup_buffers", i32 31}
!5 = !{i32 7, !"air.max_textures", i32 128}
!6 = !{i32 7, !"air.max_read_write_textures", i32 8}
!7 = !{i32 7, !"air.max_samplers", i32 16}
!8 = !{ptr @entry_point, !9, !10}
!9 = !{}
!10 = !{!11, !12, !13}
!11 = !{i32 0, !"air.thread_position_in_threadgroup", !"air.arg_type_name", !"uint3", !"air.arg_name", !"local_id"}
!12 = !{i32 1, !"air.buffer", !"air.buffer_size", i32 4, !"air.location_index", i32 0, i32 1, !"air.read", !"air.address_space", i32 2, !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"uint", !"air.arg_name", !"flag"}
!13 = !{i32 2, !"air.buffer", !"air.buffer_size", i32 4, !"air.location_index", i32 1, i32 1, !"air.read_write", !"air.address_space", i32 1, !"air.struct_type_info", !14, !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"metal::_atomic", !"air.arg_name", !"output"}
!14 = !{i32 0, i32 4, i32 0, !"uint", !"__s"}
!15 = !{!"air.compile.denorms_disable"}
!16 = !{!"air.compile.fast_math_enable"}
!17 = !{!"air.compile.framebuffer_fetch_enable"}
!18 = !{!"Apple metal version 31001.720 (metalfe-31001.720.3)"}
!19 = !{i32 2, i32 5, i32 0}
!20 = !{!"Metal", i32 3, i32 0, i32 0}
!21 = !{!"/Users/armansito/Code/personal/metal-broken-workgroupUniformLoad/wg-mem-as-local.metal"}
!22 = !{!23, !23, i64 0}
!23 = !{!"int", !24, i64 0}
!24 = !{!"omnipotent char", !25, i64 0}
!25 = !{!"Simple C++ TBAA"}

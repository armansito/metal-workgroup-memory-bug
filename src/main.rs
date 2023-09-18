use {
    anyhow::{Context, Result},
    objc::rc::autoreleasepool,
};

#[cfg(feature = "broken")]
fn load_shader_src() -> &'static str {
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/wg-mem-as-arg.metal"))
}

#[cfg(not(feature = "broken"))]
fn load_shader_src() -> &'static str {
    include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/wg-mem-as-local.metal"
    ))
}

fn run() -> Result<()> {
    let device = mtl::Device::system_default().context("No device found")?;
    let library = device
        .new_library_with_source(load_shader_src(), &mtl::CompileOptions::new())
        .map_err(anyhow::Error::msg)
        .context("failed to compile shader")?;
    let entry_point = library
        .get_function("entry_point", None)
        .map_err(anyhow::Error::msg)
        .context("failed to find entry point")?;

    let desc = mtl::ComputePipelineDescriptor::new();
    desc.set_thread_group_size_is_multiple_of_thread_execution_width(true);
    desc.set_compute_function(Some(&entry_point));
    let pipeline = device
        .new_compute_pipeline_state(&desc)
        .map_err(anyhow::Error::msg)
        .context("failed to create compute pipeline state")?;

    let cmd_queue = device.new_command_queue();
    let cmd_buffer = cmd_queue.new_command_buffer();
    let cmd_encoder = cmd_buffer.new_compute_command_encoder();

    let data: u32 = 0;
    let flag = device.new_buffer_with_data(
        [data].as_ptr() as *const _,
        std::mem::size_of::<u32>() as u64,
        mtl::MTLResourceOptions::StorageModeShared,
    );
    let output = device.new_buffer_with_data(
        [data].as_ptr() as *const _,
        std::mem::size_of::<u32>() as u64,
        mtl::MTLResourceOptions::StorageModeShared,
    );

    cmd_encoder.set_compute_pipeline_state(&pipeline);
    cmd_encoder.set_buffer(0, Some(&flag), 0);
    cmd_encoder.set_buffer(1, Some(&output), 0);
    // The arguments for setThreadgroupMemoryLength:atIndex: are swapped in metal-rs:
    cmd_encoder.set_threadgroup_memory_length(0, std::mem::size_of::<u32>() as u64);
    cmd_encoder.dispatch_thread_groups(mtl::MTLSize::new(10, 1, 1), mtl::MTLSize::new(96, 1, 1));
    cmd_encoder.end_encoding();

    cmd_buffer.commit();
    cmd_buffer.wait_until_completed();

    let ptr = output.contents() as *mut u32;
    println!("Output: {}", unsafe { *ptr });

    Ok(())
}

fn main() {
    autoreleasepool(|| run().expect("failed"));
}

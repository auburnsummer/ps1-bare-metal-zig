const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;

pub fn waitForGp0Ready() void {
    while (!psx.GPU_STAT.cmd_ready) {}
}

pub fn setupGpu(
    mode: gpuc.VideoMode,
    h_res: gpuc.HorizontalResolution,
    v_res: gpuc.VerticalResolution,
    width: u32,
    height: u32,
) void {
    // Set the origin of the displayed framebuffer. These "magic" values,
    // derived from the GPU's internal clocks, will center the picture on most
    // displays and upscalers.
    const x: u32 = 0x760;
    const y: u32 = if (mode == .pal) 0xa3 else 0x88;

    const offset_x = (width * gpuc.getGpuClockMultiplerH(h_res)) / 2;
    const offset_y = (height / gpuc.getGpuClockMultipleV(v_res)) / 2;

    psx.GPU_GP1.* = gpuc.gp1ResetGpu();
    psx.GPU_GP1.* = gpuc.gp1FbRangeH(
        @truncate(x - offset_x),
        @truncate(x + offset_x),
    );
    psx.GPU_GP1.* = gpuc.gp1FbRangeV(
        @truncate(y - offset_y),
        @truncate(y + offset_y),
    );
    psx.GPU_GP1.* = gpuc.gp1FbMode(
        h_res,
        v_res,
        mode,
        false,
        .bits_15,
    );
    psx.GPU_GP1.* = gpuc.gp1Blank(false);
}

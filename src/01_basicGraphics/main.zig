const std = @import("std");
const psx = @import("./ps1/registers.zig");
const logging = @import("./libc/logging.zig");

pub fn setupGPU(mode: psx.VideoMode, width: u32, height: u32) void {
    // Set the origin of the displayed framebuffer. These "magic" values,
    // derived from the GPU's internal clocks, will center the picture on most
    // displays and upscalers.
    std.log.info("aa", .{});
    const x: u32 = 0x760;
    const y: u32 = if (mode == .pal) 0xa3 else 0x88;

    // Set the resolution. The GPU provides a number of fixed horizontal (256,
    // 320, 368, 512, 640) and vertical (240-256, 480-512) resolutions to pick
    // from, which affect how fast pixels are output and thus how "stretched"
    // the framebuffer will appear.
    const h_res: psx.HorizontalResolution = .res_320;
    const v_res: psx.VerticalResolution = .res_240;

    // Set the number of displayed rows and columns. These values are in GPU
    // clock units rather than pixels, thus they are dependent on the selected
    // resolution.
    const offset_x = (width * psx.getGpuClockMultiplerH(h_res)) / 2;
    const offset_y = (height / psx.getGpuClockMultipleV(v_res)) / 2;

    // Hand all parameters over to the GPU by sending GP1 commands.
    psx.GPU_GP1.* = psx.gp1ResetGpu();
    psx.GPU_GP1.* = psx.gp1FbRangeH(
        @truncate(x - offset_x),
        @truncate(x + offset_x),
    );
    psx.GPU_GP1.* = psx.gp1FbRangeV(
        @truncate(y - offset_y),
        @truncate(y + offset_y),
    );
    psx.GPU_GP1.* = psx.gp1FbMode(
        h_res,
        v_res,
        mode,
        false,
        .bits_15,
    );
}

const screen_width = 320;
const screen_height = 240;

pub fn main() noreturn {
    // Initialize the serial interface. The initSerialIO() function is defined
    // in libc/logging.zig and does basically the same things we did in the
    // previous example.
    //
    // Afterwards, we may use `std.log` to print messages to SIO1. (This is set up
    // in entry.zig.)
    logging.initSerialIO();
    // Read the GPU's status register to check if it was left in PAL or NTSC
    // mode by the BIOS/loader.
    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        setupGPU(.pal, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        setupGPU(.ntsc, screen_width, screen_height);
    }

    while (true) {
        std.log.info("hello", .{});
    }
}

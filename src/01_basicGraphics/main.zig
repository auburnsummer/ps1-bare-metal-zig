const std = @import("std");
const psx = @import("./ps1/registers.zig");
const gpu = @import("./ps1/gpu_cmd.zig");
const logging = @import("./libc/logging.zig");

pub fn setupGPU(mode: gpu.VideoMode, width: u32, height: u32) void {
    // Set the origin of the displayed framebuffer. These "magic" values,
    // derived from the GPU's internal clocks, will center the picture on most
    // displays and upscalers.
    const x: u32 = 0x760;
    const y: u32 = if (mode == .pal) 0xa3 else 0x88;

    // Set the resolution. The GPU provides a number of fixed horizontal (256,
    // 320, 368, 512, 640) and vertical (240-256, 480-512) resolutions to pick
    // from, which affect how fast pixels are output and thus how "stretched"
    // the framebuffer will appear.
    const h_res: gpu.HorizontalResolution = .res_320;
    const v_res: gpu.VerticalResolution = .res_240;

    // Set the number of displayed rows and columns. These values are in GPU
    // clock units rather than pixels, thus they are dependent on the selected
    // resolution.
    const offset_x = (width * gpu.getGpuClockMultiplerH(h_res)) / 2;
    const offset_y = (height / gpu.getGpuClockMultipleV(v_res)) / 2;

    // Hand all parameters over to the GPU by sending GP1 commands.
    psx.GPU_GP1.* = gpu.gp1ResetGpu();
    psx.GPU_GP1.* = gpu.gp1FbRangeH(
        @truncate(x - offset_x),
        @truncate(x + offset_x),
    );
    psx.GPU_GP1.* = gpu.gp1FbRangeV(
        @truncate(y - offset_y),
        @truncate(y + offset_y),
    );
    psx.GPU_GP1.* = gpu.gp1FbMode(
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

    // Wait for the GPU to become ready, then send some GP0 commands to tell it
    // which area of the framebuffer we want to draw to and enable dithering.
    gpu.waitForGp0Ready();
    psx.GPU_GP0.* = gpu.gp0SetPage(.{}, true, false);
    psx.GPU_GP0.* = gpu.gp0FbOffset1(0, 0);
    psx.GPU_GP0.* = gpu.gp0FbOffset2(screen_width - 1, screen_height - 1);
    psx.GPU_GP0.* = gpu.gp0FbOrigin(0, 0);

    // Send a VRAM fill command to quickly fill our area with a dark green. Note
    // that the coordinates passed to this specific command are *not* relative
    // to the ones we've just sent to the GPU!
    gpu.waitForGp0Ready();
    psx.GPU_GP0.* = gpu.gp0VramFill(.{ .r = 32, .g = 76, .b = 79 });
    psx.GPU_GP0.* = gpu.gp0XY(0, 0);
    psx.GPU_GP0.* = gpu.gp0WidthHeight(screen_width, screen_height);

    // Tell the GPU to draw a Gouraud shaded triangle whose vertices are red,
    // green and blue respectively at the center of our drawing area.
    gpu.waitForGp0Ready();
    psx.GPU_GP0.* = gpu.gp0ShadedTriangle(.{ .r = 255, .g = 0, .b = 0 }, true, false, false);
    psx.GPU_GP0.* = gpu.gp0XY(screen_width / 2, 32);
    psx.GPU_GP0.* = gpu.gp0Rgb(.{ .r = 0, .g = 255, .b = 0 });
    psx.GPU_GP0.* = gpu.gp0XY(32, screen_height - 32);
    psx.GPU_GP0.* = gpu.gp0Rgb(.{ .r = 0, .g = 0, .b = 255 });
    psx.GPU_GP0.* = gpu.gp0XY(screen_width - 32, screen_height - 32);

    // Send two GP1 commands to set the origin of the area we want to display
    // and switch on the display output.
    gpu.waitForGp0Ready();
    psx.GPU_GP1.* = gpu.gp1FbOffset(0, 0);
    psx.GPU_GP1.* = gpu.gp1Blank(false);

    while (true) {
        std.log.info("hello", .{});
    }
}

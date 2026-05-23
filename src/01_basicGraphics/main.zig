// ps1-bare-metal - (C) 2023-2025 spicyjpeg
// ps1-bare-metal-zig - (C) 2026 auburnsummer

// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.

// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// THER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

// In this tutorial we're going to initialize the GPU, set it up and display
// some simple hardware-rendered graphics (namely, a shaded triangle).

// While the PS1's GPU may appear complicated and daunting, its principle of
// operation is in actual fact very simple. At a high level it is simply a
// "rasterization machine" capable of drawing triangles, quads, rectangles and
// lines in 2D space (with 3D transformations being entirely the CPU's
// responsibility) and of displaying a rectangular cutout of its 1024x512x16bpp
// framebuffer, which resides in dedicated memory (VRAM). It is controlled using
// only two registers, one (GP0) for drawing commands and the other (GP1) for
// display control and other commands; we're going to see how to configure the
// video output and draw our triangle by writing the right commands to these
// registers.

// This tutorial will use the ps1/gpu_cmd.zig file I wrote, which contains
// functions for commands supported by the GPU. If you wish to write such a
// file yourself, you'll want to check out the GPU register and command documentation
// at:
//     https://psx-spx.consoledev.net/graphicsprocessingunitgpu

const std = @import("std");
const logging = @import("runtime").logging;
const psx = @import("ps1").registers;
const gpu = @import("ps1").gpu;

fn waitForGp0Ready() void {
    // Block until the GPU reports to be ready to accept commands through its
    // status register (which has the same address as GP1 but is read-only).
    while (!psx.GPU_STAT.cmd_ready) {}
}

fn setupGpu(mode: gpu.VideoMode, width: u32, height: u32) void {
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
    // Initialize the serial interface. The initSerialIo() function is defined
    // in libc/logging.zig and does basically the same things we did in the
    // previous example.
    //
    // Afterwards, we may use `std.log` to print messages to SIO1. (This is set up
    // in entry.zig.)
    logging.initSerialIo();

    // Read the GPU's status register to check if it was left in PAL or NTSC
    // mode by the BIOS/loader.
    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        setupGpu(.pal, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        setupGpu(.ntsc, screen_width, screen_height);
    }

    // Wait for the GPU to become ready, then send some GP0 commands to tell it
    // which area of the framebuffer we want to draw to and enable dithering.
    waitForGp0Ready();
    psx.GPU_GP0.* = gpu.gp0SetPage(.{}, true, false);
    psx.GPU_GP0.* = gpu.gp0FbOffset1(0, 0);
    psx.GPU_GP0.* = gpu.gp0FbOffset2(screen_width - 1, screen_height - 1);
    psx.GPU_GP0.* = gpu.gp0FbOrigin(0, 0);

    // Send a VRAM fill command to quickly fill our area with a dark green. Note
    // that the coordinates passed to this specific command are *not* relative
    // to the ones we've just sent to the GPU!
    waitForGp0Ready();
    psx.GPU_GP0.* = gpu.gp0VramFill(.{ .r = 32, .g = 76, .b = 79 });
    psx.GPU_GP0.* = gpu.gp0XY(0, 0);
    psx.GPU_GP0.* = gpu.gp0WidthHeight(screen_width, screen_height);

    // Tell the GPU to draw a Gouraud shaded triangle whose vertices are red,
    // green and blue respectively at the center of our drawing area.
    waitForGp0Ready();
    psx.GPU_GP0.* = gpu.gp0ShadedTriangle(.{ .r = 255, .g = 0, .b = 0 }, true, false, false);
    psx.GPU_GP0.* = gpu.gp0XY(screen_width / 2, 32);
    psx.GPU_GP0.* = gpu.gp0Rgb(.{ .r = 0, .g = 255, .b = 0 });
    psx.GPU_GP0.* = gpu.gp0XY(32, screen_height - 32);
    psx.GPU_GP0.* = gpu.gp0Rgb(.{ .r = 0, .g = 0, .b = 255 });
    psx.GPU_GP0.* = gpu.gp0XY(screen_width - 32, screen_height - 32);

    // Send two GP1 commands to set the origin of the area we want to display
    // and switch on the display output.
    waitForGp0Ready();
    psx.GPU_GP1.* = gpu.gp1FbOffset(0, 0);
    psx.GPU_GP1.* = gpu.gp1Blank(false);

    while (true) {}
}

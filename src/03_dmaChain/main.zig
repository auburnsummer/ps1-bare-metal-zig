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

// /*
//  * In the previous two examples we saw how to control the GPU and draw graphics
//  * by writing commands directly to the GP0 and GP1 registers. While this
//  * approach is simple and easy to understand, it also limits performance: the
//  * CPU always has to wait for the GPU to go idle before being able to send it a
//  * new command, otherwise the GPU may miss it; similarly, the GPU can only
//  * process commands while the CPU is actively feeding it.
//  *
//  * To get around these limitations the GPU (along with most of the PS1's other
//  * peripherals) can instead be given access to RAM and read GP0 commands from it
//  * automatically, without needing the CPU to feed it. This is accomplished
//  * through a middleman peripheral known as the direct memory access (DMA)
//  * controller, and is the key to high-performance graphics on the PS1. We'll see
//  * how to allocate a buffer in RAM, fill it with commands and then set up the
//  * GPU's DMA channel to read from it in the background while we're preparing the
//  * next frame's command buffer.
//  */

const std = @import("std");
const logging = @import("runtime").logging;
const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;
const gpu = @import("runtime").gpu;

const screen_width: u10 = 320;
const screen_height = 240;

fn waitForVSync() void {
    // The GPU won't tell us directly whenever it is done sending a frame to the
    // display, but it will send a signal to another peripheral known as the
    // interrupt controller (which will be covered in a future tutorial). We can
    // thus wait until the interrupt controller's vertical blank flag gets set,
    // then reset (acknowledge) it so that it can be set again by the GPU.
    while (!psx.IRQ_STAT.vblank) {}

    // acknowledge
    psx.IRQ_STAT.vblank = false;
}

pub fn setupGpu(
    mode: gpuc.VideoMode,
    width: u32,
    height: u32,
) void {
    const x: u32 = 0x760;
    const y: u32 = if (mode == .pal) 0xa3 else 0x88;

    const h_res: gpuc.HorizontalResolution = .res_320;
    const v_res: gpuc.VerticalResolution = .res_240;

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

    // Enable and reset the GPU's DMA channel, then tell the GPU to fetch GP0
    // commands from DMA whenever available.
    psx.DMA_DPCR.gpu.enable = true;
    psx.DMA_CHCR(.gpu).* = @bitCast(@as(u32, 0));

    psx.GPU_GP1.* = gpuc.gp1DmaRequestMode(.cpu_to_gp0);
}

fn clip(x: i16) u16 {
    return @max(0, x);
}

pub fn main() noreturn {
    logging.initSerialIo();

    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        setupGpu(.pal, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        setupGpu(.ntsc, screen_width, screen_height);
    }

    var x: i16 = 0;
    var dx: i16 = 1;
    var y: i16 = 0;
    var dy: i16 = 1;

    var using_second_frame: bool = false;

    while (true) {
        // Determine the VRAM location of the current frame. We're going to
        // place the two frames next to each other in VRAM, at (0, 0) and
        // (320, 0) respectively.
        const frame_x: u10 = if (using_second_frame) screen_width else 0;
        const frame_y = 0;

        using_second_frame = !using_second_frame;

        // Tell the GPU which area of VRAM belongs to the frame we're going to
        // use and enable dithering.
        gpu.waitForGp0Ready();
        psx.GPU_GP0.* = gpuc.gp0SetPage(.{}, true, false);
        psx.GPU_GP0.* = gpuc.gp0FbOffset1(frame_x, frame_y);
        psx.GPU_GP0.* = gpuc.gp0FbOffset2(
            frame_x + screen_width - 1,
            frame_y + screen_height - 1,
        );
        psx.GPU_GP0.* = gpuc.gp0FbOrigin(frame_x, frame_y);

        // Fill the framebuffer with solid gray.
        gpu.waitForGp0Ready();
        psx.GPU_GP0.* = gpuc.gp0VramFill(.{ .r = 64, .g = 64, .b = 64 });
        psx.GPU_GP0.* = gpuc.gp0XY(frame_x, frame_y);
        psx.GPU_GP0.* = gpuc.gp0WidthHeight(screen_width, screen_height);

        // Draw the yellow bouncing square using a rectangle command.
        gpu.waitForGp0Ready();
        psx.GPU_GP0.* = gpuc.gp0Rectangle(
            .{ .r = 255, .g = 255, .b = 0 },
            false,
            false,
            false,
            .px_variable,
        );
        psx.GPU_GP0.* = gpuc.gp0XY(clip(x), clip(y));
        psx.GPU_GP0.* = gpuc.gp0WidthHeight(32, 32);

        // Update the position of the square.
        x = x +| dx;
        y = y +| dy;

        if (x <= 0 or x >= (screen_width - 32)) {
            dx = -dx;
        }
        if (y <= 0 or y >= (screen_height - 32)) {
            dy = -dy;
        }

        // Wait for the GPU to finish drawing and displaying the contents of the
        // previous frame, then tell it to start sending the newly drawn frame
        // to the video output.
        gpu.waitForGp0Ready();
        waitForVSync();

        psx.GPU_GP1.* = gpuc.gp1FbOffset(frame_x, frame_y);
    }
}

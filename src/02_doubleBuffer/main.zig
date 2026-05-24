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

// We saw how to initialize the GPU and get basic graphics on screen in the last
// tutorial. It's now time to add motion to the mix: we're going to draw a
// square which, in true DVD player screensaver fashion, will bounce around on
// the screen.
//
// This may sound simple in theory, but there are a few caveats we'll have to
// look out for. First of all we will need some sort of timer for our animation,
// ideally something synchronized to the display output in order to avoid
// updating the position of our square while the picture is still being sent by
// the GPU to the monitor (and stabilize the frame rate). We'll also have to
// ensure the frame we are sending in the first place is not actively being
// updated by the GPU, otherwise screen tearing will be prominent. Hiding a
// frame while it is being drawn may sound tricky, but there is a very simple
// way to accomplish it: we are going to keep *two* frames in VRAM, and draw one
// while the other is being displayed. Once drawing is done and the other frame
// has been fully sent to the display, we're going to swap the buffers (so that
// the newly rendered frame will be displayed) and start over.
//
// This is an extremely common practice (the device you are looking at right now
// is no doubt using it) known as double buffering, and you can read more about
// it here:
//     https://gameprogrammingpatterns.com/double-buffer.html
//

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

pub fn main() noreturn {
    logging.initSerialIo();

    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        // waitForGp0Ready and setupGpu from the previous example are moved to a seperate module.
        gpu.setupGpu(.pal, .res_320, .res_240, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        gpu.setupGpu(.ntsc, .res_320, .res_240, screen_width, screen_height);
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
        psx.GPU_GP0.* = gpuc.gp0XY(@abs(x), @abs(y));
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

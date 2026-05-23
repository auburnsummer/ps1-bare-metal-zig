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
const gpu = @import("ps1").gpu;

const screen_width = 320;
const screen_height = 240;

pub fn main() noreturn {
    logging.initSerialIo();

    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        gpu.setupGpu(.pal, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        gpu.setupGpu(.ntsc, screen_width, screen_height);
    }

    while (true) {}
}

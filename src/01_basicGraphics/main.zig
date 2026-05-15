const std = @import("std");
const psx = @import("./ps1/registers.zig");
const logging = @import("./libc/logging.zig");

pub fn main() noreturn {
    // Initialize the serial interface. The initSerialIO() function is defined
    // in libc/logging.zig and does basically the same things we did in the
    // previous example.

    // Afterwards, we can use `std.log` to print messages to SIO1. (This is set up
    // in entry.zig.)
    logging.initSerialIO();

    // Read the GPU's status register to check if it was left in PAL or NTSC
    // mode by the BIOS/loader.
    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
    } else {
        std.log.info("Using NTSC mode", .{});
    }

    while (true) {}
}

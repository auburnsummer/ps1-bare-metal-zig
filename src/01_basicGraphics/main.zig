const std = @import("std");
const psx = @import("./ps1/registers.zig");
const logging = @import("./libc/logging.zig");
var my_cool_global: u32 = 0;

pub fn main() noreturn {
    // Initialize the serial interface. The initSerialIO() function is defined
    // in libc/logging.zig and does basically the same things we did in the
    // previous example.
    //
    // Afterwards, we can use `std.log` to print messages to SIO1. This is set up
    // in entry.zig.
    logging.initSerialIO();

    psx.GPU_GP1.* = .{ .display_enable = .{ .display_on_off = 0 } };
    psx.writeGP1(psx.DisplayEnable{ .display_on_off = 0 });

    while (true) {
        my_cool_global += 1;
        std.log.info("Hello World! my_cool_global = {}", .{my_cool_global});
    }
}

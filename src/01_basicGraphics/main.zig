const std = @import("std");
const psx = @import("./ps1/registers.zig");

const logging = @import("./libc/logging.zig");

// This sets the log function used by, e.g. std.log to our custom log
// function which writes to SIO1. The implementation is in libc/logging.zig and
// is similar to what we did the previous example. `logging.initSerialIO()` must
// be called before any logging will work.
//
// The default log function will attempt to write to stderr, which
// doesn't exist.
pub const std_options: std.Options = .{
    .logFn = logging.logFn,
};

var my_cool_global: u32 = 0;

export fn main() noreturn {
    // Initialize the serial interface. The initSerialIO() function is defined
    // in libc/logging.zig and does basically the same things we did in the
    // previous example.
    logging.initSerialIO();

    psx.GPU_GP1.* = .{ .display_enable = .{ .display_on_off = 0 } };
    psx.writeGP1(psx.DisplayEnable{ .display_on_off = 0 });

    while (true) {
        my_cool_global += 1;
        std.log.info("Hello World! my_cool_global = {}", .{my_cool_global});
    }
}

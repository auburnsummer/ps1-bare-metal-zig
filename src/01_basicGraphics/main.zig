const std = @import("std");
const psx = @import("./ps1/registers.zig");

const misc = @import("./libc/misc.zig");

// Override std.log to use write to SIO1.
pub const std_options: std.Options = .{
    .logFn = misc.logFn,
};

export fn _start() noreturn {
    misc.initSerialIO();

    while (true) {
        std.log.info("Hello World!", .{});
    }
}

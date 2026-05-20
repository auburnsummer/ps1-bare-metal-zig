const psx = @import("../ps1/registers.zig");
const std = @import("std");

pub fn initSerialIO() void {
    psx.SIO_CTRL(1).reset = true;

    psx.SIO_MODE(1).* = .{
        .baud = .mul1,
        .char_length = .bits_8,
        .stop_bit_length = .bits_1,
    };

    psx.SIO_BAUD(1).* = psx.F_CPU / 115200;

    psx.SIO_CTRL(1).* = .{
        .tx_enable = true,
        .rx_enable = true,
        .rts = true,
    };
}

pub fn printCharacter(char: u8) void {
    // Wait until the serial interface is ready to send a new byte, then write
    // it to the data register.
    // NOTE: the serial interface checks for an external signal (CTS) and will
    // *not* send any data until it is asserted. To avoid blocking forever if
    // CTS is not asserted, we have to check for it manually and abort if
    // necessary.
    while (psx.SIO_STAT(1).cts and !psx.SIO_STAT(1).tx_ready) {}

    if (psx.SIO_STAT(1).cts) {
        psx.SIO_TX_DATA(1).* = char;
    }
}

pub fn printString(string: []const u8) void {
    for (string) |char| {
        printCharacter(char);
    }
}
const MAXIMUM_LOG_SIZE = 64;

pub fn logFn(
    comptime level: std.log.Level,
    comptime _: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Emit the level.
    printString(comptime level.asText() ++ ":");

    // then print out the rest.
    var buffer: [MAXIMUM_LOG_SIZE]u8 = undefined;

    const message = std.fmt.bufPrint(buffer[0..], format ++ "\n", args);
    if (message) |slice| {
        printString(slice);
    } else |_| {
        printString("[printString: Not enough space in buffer]");
    }
}

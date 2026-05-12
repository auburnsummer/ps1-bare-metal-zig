const psx = @import("../ps1/registers.zig");
const std = @import("std");

// Add the necessary memcpy/memset/memmove symbols to the binary which
// are used by std.fmt.bufPrint.
// Comptime in this case tells the compiler the import is required
// for its side effects (i.e. adding the symbols)
comptime {
    _ = @import("./mem.zig");
}

pub fn initSerialIO() void {
    // Reset the serial interface and initialize it to output data at 115200bps,
    // 8 data bits, 1 stop bit and no parity.
    psx.SIO_CTRL(1).reset = true;

    psx.SIO_MODE(1).* = .{
        .baudrate_reload_factor = .mul1,
        .character_length = 3, // 8 data bits
        .sio1_stop_bit_length = 1,
    };

    psx.SIO_BAUD(1).* = psx.F_CPU / 115200;

    psx.SIO_CTRL(1).* = .{
        .tx_enable = true,
        .rx_enable = true,
        .sio1_rts_output_level = true,
    };
}

pub fn printCharacter(char: u8) void {
    // Wait until the serial interface is ready to send a new byte, then write
    // it to the data register.
    // NOTE: the serial interface checks for an external signal (CTS) and will
    // *not* send any data until it is asserted. To avoid blocking forever if
    // CTS is not asserted, we have to check for it manually and abort if
    // necessary.
    while (psx.SIO_STAT(1).sio1_cts_input_level and !psx.SIO_STAT(1).tx_not_full) {}

    if (psx.SIO_STAT(1).sio1_cts_input_level) {
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

    var buffer: [MAXIMUM_LOG_SIZE]u8 = undefined;

    const message = std.fmt.bufPrint(buffer[0..], format ++ "\n", args);
    if (message) |slice| {
        printString(slice);
    } else |_| {
        printString("oh no");
    }
}

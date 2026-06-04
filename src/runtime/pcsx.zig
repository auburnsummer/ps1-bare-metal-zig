const psx = @import("ps1").registers;
const std = @import("std");

/// "PCSX"
pub const PCSX_ID = 0x58534350;

/// Return true if we are running in the PCSX-Redux emulator.
pub fn isPcsxRedux() bool {
    return psx.PCSX_REDUX_ID.* == PCSX_ID;
}

pub fn putChar(char: u8) void {
    psx.PCSX_CONSOLE_PUTCHAR.* = char;
}

pub fn printString(s: []const u8) void {
    for (s) |c| {
        putChar(c);
    }
}

pub fn pcsxBreak() void {
    psx.PCSX_DEBUG_BREAK.* = 0;
}

pub fn pcsxMessage(s: [*:0]const u8) void {
    psx.PCSX_MESSAGE.* = s;
}
const MAXIMUM_LOG_SIZE = 80;

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

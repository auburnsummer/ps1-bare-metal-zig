/// Since we always run at OReleaseFast, normal
/// asserts won't work as expected. So I'm using this
/// instead.
pub fn assert(cond: bool, message: []const u8) void {
    if (!cond) {
        @panic(message);
    }
}

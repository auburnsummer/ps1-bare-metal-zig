// lib/compiler_rt/memcpy.zig
export fn memcpy(noalias dest: ?[*]u8, noalias src: ?[*]const u8, len: usize) ?[*]u8 {
    @setRuntimeSafety(false);

    const d: [*]volatile u8 = @ptrCast(dest.?);
    const s: [*]volatile u8 = @ptrCast(@constCast(src.?));
    for (0..len) |i| {
        d[i] = s[i];
    }

    return dest;
}

// lib/compiler_rt.zig
export fn memset(dest: ?[*]u8, c: u8, len: usize) ?[*]u8 {
    @setRuntimeSafety(false);
    if (len != 0) {
        // cast to a volatile pointer. this prevents the Zig compiler from going
        // "oh I recognise this pattern, you're just doing memset!" and optimising
        // this away into a memset call (...despite the fact that this _is_ memset)
        var d: [*]volatile u8 = @ptrCast(dest.?);
        var n = len;
        while (true) {
            d[0] = c;
            n -= 1;
            if (n == 0) break;
            d += 1;
        }
    }

    return dest;
}

// lib/compiler_rt/memmove.zig
export fn memmove(opt_dest: ?[*]u8, opt_src: ?[*]const u8, len: usize) ?[*]u8 {
    @setRuntimeSafety(false);
    const dest: [*]volatile u8 = @ptrCast(opt_dest.?);
    const src: [*]volatile u8 = @ptrCast(@constCast(opt_src.?));

    if (@intFromPtr(opt_dest.?) < @intFromPtr(opt_src.?)) {
        for (0..len) |i| {
            dest[i] = src[i];
        }
    } else {
        for (0..len) |i| {
            dest[len - 1 - i] = src[len - 1 - i];
        }
    }

    return opt_dest;
}

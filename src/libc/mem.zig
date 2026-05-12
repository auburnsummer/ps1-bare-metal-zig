// lib/compiler_rt/memcpy.zig
export fn memcpy(noalias dest: ?[*]u8, noalias src: ?[*]const u8, len: usize) ?[*]u8 {
    @setRuntimeSafety(false);

    for (0..len) |i| {
        dest.?[i] = src.?[i];
    }

    return dest;
}

// lib/compiler_rt.zig
export fn memset(dest: ?[*]u8, c: u8, len: usize) ?[*]u8 {
    if (len != 0) {
        var d = dest.?;
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
    const dest = opt_dest.?;
    const src = opt_src.?;

    if (@intFromPtr(dest) < @intFromPtr(src)) {
        for (0..len) |i| {
            dest[i] = src[i];
        }
    } else {
        for (0..len) |i| {
            dest[len - 1 - i] = src[len - 1 - i];
        }
    }

    return dest;
}

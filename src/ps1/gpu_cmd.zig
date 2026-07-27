const psx = @import("./registers.zig");

pub const VideoMode = enum(u1) {
    ntsc,
    pal,
};

pub const DmaRequestMode = enum(u2) {
    off,
    fifo,
    cpu_to_gp0,
    gpu_to_cpu,
};

/// Dma tag: https://psx-spx.consoledev.net/dmachannels/#linked-list-dma
pub const DmaTag = packed struct(u32) {
    next: u24,
    len: u8,
};

/// Horizontal Resolution as laid out in the GPUSTAT register,
/// bit 0: 1 if 368
/// bits 1-2: 256/320/512/640
pub const HorizontalResolution = enum(u3) {
    res_256 = 0b000,
    res_368 = 0b001,
    res_320 = 0b010,
    res_512 = 0b100,
    res_640 = 0b110,
};

pub const VerticalResolution = enum(u1) {
    /// 256 on PAL
    res_240,
    /// 512 on PAL
    res_480,
};

pub const ColorDepth = enum(u1) {
    bits_15,
    bits_24,
};

/// GP1(00h) - Reset GPU
pub fn gp1ResetGpu() u32 {
    const Cmd = packed struct(u32) {
        _padding: u24 = 0,
        _cmd: u8 = 0x00,
    };
    return @bitCast(Cmd{});
}

/// GP1(01h) - Reset Command Buffer
pub fn gp1ResetFifo() u32 {
    const Cmd = packed struct(u32) {
        _padding: u24 = 0,
        _cmd: u8 = 0x01,
    };
    return @bitCast(Cmd{});
}

/// GP1(02h) - Acknowledge GPU Interrupt (IRQ1)
pub fn gp1Acknowledge() u32 {
    const Cmd = packed struct(u32) {
        _padding: u24 = 0,
        _cmd: u8 = 0x02,
    };
    return @bitCast(Cmd{});
}

/// GP1(03h) - Display Enable
pub fn gp1Blank(blank: bool) u32 {
    const Cmd = packed struct(u32) {
        blank: bool,
        _padding: u23 = 0,
        _cmd: u8 = 0x03,
    };
    return @bitCast(Cmd{ .blank = blank });
}

/// GP1(04h) - DMA Direction / Data Request
pub fn gp1DmaRequestMode(mode: DmaRequestMode) u32 {
    const Cmd = packed struct(u32) {
        mode: DmaRequestMode,
        _padding: u22 = 0,
        _cmd: u8 = 0x04,
    };
    return @bitCast(Cmd{ .mode = mode });
}

/// GP1(05h) - Start of Display Area (in VRAM)
pub fn gp1FbOffset(x: u10, y: u9) u32 {
    const Cmd = packed struct(u32) {
        x: u10,
        y: u9,
        _padding: u5 = 0,
        _cmd: u8 = 0x05,
    };
    return @bitCast(Cmd{ .x = x, .y = y });
}

pub fn gp1FbRangeH(low: u12, high: u12) u32 {
    const Cmd = packed struct(u32) {
        low: u12,
        high: u12,
        _cmd: u8 = 0x06,
    };
    return @bitCast(Cmd{ .low = low, .high = high });
}

pub fn gp1FbRangeV(low: u10, high: u10) u32 {
    const Cmd = packed struct(u32) {
        low: u10,
        high: u10,
        _padding: u4 = 0,
        _cmd: u8 = 0x07,
    };
    return @bitCast(Cmd{ .low = low, .high = high });
}

pub fn gp1FbMode(h_res: HorizontalResolution, v_res: VerticalResolution, mode: VideoMode, interlace: bool, color_depth: ColorDepth) u32 {
    const Cmd = packed struct(u32) {
        h_res_1: u2,
        v_res: VerticalResolution,
        video_mode: VideoMode,
        color_depth: ColorDepth,
        interlace: bool,
        h_res_2: u1,
        flip_h: bool = false,
        _padding: u16 = 0,
        _cmd: u8 = 0x08,
    };
    const h = @intFromEnum(h_res);
    return @bitCast(Cmd{
        .h_res_1 = @truncate(h >> 1),
        .v_res = v_res,
        .video_mode = mode,
        .color_depth = color_depth,
        .interlace = interlace,
        .h_res_2 = @truncate(h & 0b001),
    });
}

pub fn getGpuClockMultiplerH(h_res: HorizontalResolution) u32 {
    return switch (h_res) {
        .res_256 => 10,
        .res_320 => 8,
        .res_368 => 7,
        .res_512 => 5,
        .res_640 => 4,
    };
}

pub fn getGpuClockMultipleV(v_res: VerticalResolution) u32 {
    return switch (v_res) {
        .res_240 => 1,
        .res_480 => 2,
    };
}

pub const BlendMode = enum(u2) {
    avg,
    add,
    subtract,
    add_quarter,
};

pub const TexpageColors = enum(u2) {
    bits_4,
    bits_8,
    bits_16,
    _reserved,
};

pub const TexpageAttribute = packed struct(u12) {
    x_base: u4 = 0,
    y_base_1: u1 = 0,
    blend_mode: BlendMode = .avg,
    colors: TexpageColors = .bits_4,
    _padding: u2 = 0,
    y_base_2: u1 = 0,
};

pub const ClutAttribute = packed struct(u16) {
    x: u6,
    y: u10,
};

pub fn gp0Texpage(
    x: u4,
    y: u2,
    blend_mode: BlendMode,
    colors: TexpageColors,
) TexpageAttribute {
    return .{
        .x_base = x,
        .y_base_1 = @truncate(y & 1),
        .blend_mode = blend_mode,
        .colors = colors,
        .y_base_2 = @truncate((y & 2) >> 1),
    };
}

/// GP0(E1h) - Draw Mode setting (aka "Texpage")
pub fn gp0SetPage(page: TexpageAttribute, dither: bool, unlock_fb: bool) u32 {
    // The idea here is to create two overlapping structs and then bitwise OR them
    const TexturePagePart = packed struct(u32) {
        page: TexpageAttribute,
        _padding: u20 = 0,
    };
    const Rest = packed struct(u32) {
        // covered by TexturePage
        _padding: u9 = 0,
        // bits 9 and 10, not covered
        dither: bool,
        unlock_fb: bool,
        // bits 11-23
        _padding_2: u13 = 0,
        // cmd
        _cmd: u8 = 0xe1,
    };
    const a: u32 = @bitCast(TexturePagePart{ .page = page });
    const b: u32 = @bitCast(Rest{ .dither = dither, .unlock_fb = unlock_fb });
    return a | b;
}

const FbOffsetCmd = packed struct(u32) {
    x: u10,
    y: u9,
    _padding: u5 = 0,
    cmd: u8,
};

/// GP0(E3h) - Set Drawing Area top left (X1,Y1)
pub fn gp0FbOffset1(x: u10, y: u9) u32 {
    return @bitCast(FbOffsetCmd{ .x = x, .y = y, .cmd = 0xe3 });
}

/// GP0(E4h) - Set Drawing Area bottom right (X2,Y2)
pub fn gp0FbOffset2(x: u10, y: u9) u32 {
    return @bitCast(FbOffsetCmd{ .x = x, .y = y, .cmd = 0xe4 });
}

/// GP0(E5h) - Set Drawing Offset (X,Y)
pub fn gp0FbOrigin(x: i11, y: i11) u32 {
    const Cmd = packed struct(u32) {
        x: i11,
        y: i11,
        _padding: u2 = 0,
        _cmd: u8 = 0xe5,
    };
    return @bitCast(Cmd{ .x = x, .y = y });
}

pub const RgbColor = packed struct(u24) {
    r: u8,
    g: u8,
    b: u8,
};

// 01h - Flush Cache
pub fn gp0FlushCache() u32 {
    const Cmd = packed struct(u32) {
        _padding: u24 = 0,
        _cmd: u8 = 0x01,
    };
    return @bitCast(Cmd{});
}

/// 02h - Quick Rectangle Fill
pub fn gp0VramFill(color: RgbColor) u32 {
    const Cmd = packed struct(u32) {
        color: RgbColor,
        _cmd: u8 = 0x02,
    };
    return @bitCast(Cmd{ .color = color });
}

/// Argument given to commands.
pub fn gp0XY(x: u16, y: u16) u32 {
    const Cmd = packed struct(u32) {
        x: u16,
        y: u16,
    };
    return @bitCast(Cmd{ .x = x, .y = y });
}

/// Argument version of RGB
pub fn gp0Rgb(color: RgbColor) u32 {
    const Cmd = packed struct(u32) {
        color: RgbColor,
        _cmd: u8 = 0,
    };
    return @bitCast(Cmd{ .color = color });
}

/// Bitwise the same as gp0XY, just for semantic reasons.
pub fn gp0WidthHeight(width: u16, height: u16) u32 {
    return gp0XY(width, height);
}

pub fn gp0UV(u: u8, v: u8) u32 {
    const Cmd = packed struct(u32) {
        u: u8,
        v: u8,
        _padding: u16 = 0, // TODO: CLUT or page instead of padding
    };
    return @bitCast(Cmd{ .u = u, .v = v });
}

pub fn gp0UvClut(u: u8, v: u8, clut: ClutAttribute) u32 {
    const Cmd = packed struct(u32) {
        u: u8,
        v: u8,
        clut: ClutAttribute,
    };
    return @bitCast(Cmd{ .u = u, .v = v, .clut = clut });
}

pub fn gp0Polygon(
    color: RgbColor,
    unshaded: bool,
    blend: bool,
    textured: bool,
    quad: bool,
    gourand: bool,
) u32 {
    const Cmd = packed struct(u32) {
        color: RgbColor,
        unshaded: bool,
        blend: bool,
        textured: bool,
        quad: bool,
        gourand: bool,
        _cmd: u3 = 0b001,
    };
    return @bitCast(Cmd{
        .color = color,
        .unshaded = unshaded,
        .blend = blend,
        .textured = textured,
        .quad = quad,
        .gourand = gourand,
    });
}

pub fn gp0ShadedTriangle(color: RgbColor, gourand: bool, textured: bool, blend: bool) u32 {
    return gp0Polygon(color, false, blend, textured, false, gourand);
}

pub const RectangleSize = enum(u2) {
    px_variable,
    px_1x1,
    px_8x8,
    px_16x16,
};

pub fn gp0Rectangle(color: RgbColor, unshaded: bool, blend: bool, textured: bool, size: RectangleSize) u32 {
    const Cmd = packed struct(u32) {
        color: RgbColor,
        unshaded: bool,
        blend: bool,
        textured: bool,
        size: RectangleSize,
        _cmd: u3 = 0b011,
    };
    return @bitCast(Cmd{
        .color = color,
        .unshaded = unshaded,
        .blend = blend,
        .textured = textured,
        .size = size,
    });
}

/// https://psx-spx.consoledev.net/graphicsprocessingunitgpu/#vram-to-vram-blitting-command-4-100
const MemoryTransferMode = enum(u3) {
    blit = 0b100,
    write = 0b101,
    read = 0b110,
};

pub fn gp0MemoryTransferMode(mode: MemoryTransferMode) u32 {
    const Cmd = packed struct(u32) {
        _padding: u29 = 0,
        cmd: MemoryTransferMode,
    };
    return @bitCast(Cmd{ .cmd = mode });
}

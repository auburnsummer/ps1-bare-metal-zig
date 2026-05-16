//! Definitions for hardware registers on the PSX.
//! REF: https://psx-spx.consoledev.net/

pub const F_CPU = 33868800;

/// This is the start of the KSEG1 region of memory, which is used for peripherals.
/// The documentation linked above gives memory locations as an offset from here.
const KSEG1: u32 = 0xA000_0000;

// // // // // //
// Serial I/O  //
// // // // // //

pub const SerialIoControl = packed struct(u16) {
    pub const RxInterruptMode = enum(u2) {
        bytes_1,
        bytes_2,
        bytes_4,
        bytes_8,
    };
    pub const Sio0PortSelect = enum(u1) { port_1, port_2 };
    tx_enable: bool = false,
    dtr_output_on: bool = false,
    rx_enable: bool = false,
    sio1_tx_inverted: bool = false,
    acknowledge: bool = false,
    sio1_rts_on: bool = false,
    reset: bool = false,
    _sio1_unknown: bool = false,
    rx_interrupt_mode: RxInterruptMode = .bytes_1,
    tx_interrupt_enable: bool = false,
    rx_interrupt_enable: bool = false,
    dsr_interrupt_enable: bool = false,
    sio0_port_select: Sio0PortSelect = .port_1,
    _padding: u2 = 0,
};

// Note on naming conventions: anything that is memory mapped to a hardware register is getting LOUD_YELLING_CASE to match
// the original C code. This is somewhat against Zig naming convention but I think it's nice to be able to tell at a glance
// when something is a peripheral.
/// 1F80104Ah+N*10h - SIO#_CTRL (R/W)
pub fn SIO_CTRL(comptime n: u1) *volatile SerialIoControl {
    return @ptrFromInt(KSEG1 + 0x1F80_104A + (0x10 * @as(u32, n)));
}

pub const SerialIoMode = packed struct(u16) {
    pub const BaudrateReloadFactor = enum(u2) {
        /// On SIO1 = STOP, on SIO0, equivalent to mul1.
        stop_mul1,
        mul1,
        mul16,
        mul64,
    };
    pub const CharacterLength = enum(u2) {
        bits_5,
        bits_6,
        bits_7,
        bits_8,
    };
    pub const StopBitLength = enum(u2) {
        reserved,
        bits_1,
        bits_1_half,
        bits_2,
    };
    pub const ParityType = enum(u1) {
        even,
        odd,
    };
    baud: BaudrateReloadFactor = .stop_mul1,
    char_length: CharacterLength = .bits_5,
    parity_enable: bool = false,
    parity_type: ParityType = .even,
    sio1_stop_bit_length: StopBitLength = .bits_1,
    sio0_clock_polarity: bool = false,
    _padding: u7 = 0,
};
/// 1F801048h+N*10h - SIO#_MODE (R/W)
pub fn SIO_MODE(comptime n: u1) *volatile SerialIoMode {
    return @ptrFromInt((KSEG1 + 0x1F80_1048) + (0x10 * @as(u32, n)));
}

/// 1F80104Eh+N*10h - SIO#_BAUD (R/W)
pub fn SIO_BAUD(comptime n: u1) *volatile u16 {
    return @ptrFromInt((KSEG1 + 0x1F80_104E) + (0x10 * @as(u32, n)));
}

pub const SerialIoStat = packed struct(u32) {
    tx_ready: bool = false,
    rx_data_available: bool = false,
    tx_idle: bool = false,
    rx_parity_error: bool = false,
    sio1_rx_fifo_overrun: bool = false,
    sio1_rx_bad_stop_bit: bool = false,
    sio1_rx_inverted: bool = false,
    dsr_on: bool = false,
    sio1_cts_on: bool = false,
    interrupt: bool = false,
    unknown: bool = false,
    baudrate_timer: u21 = 0,
};
/// 1F801044h+N*10h - SIO#_STAT (R)
pub fn SIO_STAT(comptime n: u1) *volatile SerialIoStat {
    return @ptrFromInt((KSEG1 + 0x1F80_1044) + (0x10 * @as(u32, n)));
}

/// 1F801040h+N*10h - SIO#_TX_DATA (W)
/// Same address as SIO#_RX_DATA (R)
pub fn SIO_TX_DATA(comptime n: u1) *volatile u8 {
    return @ptrFromInt((KSEG1 + 0x1F80_1040) + (0x10 * @as(u32, n)));
}
/// 1F801040h+N*10h - SIO#_RX_DATA (R)
/// Same address as SIO#_TX_DATA (W)
pub fn SIO_RX_DATA(comptime n: u1) *volatile u8 {
    return SIO_TX_DATA(n);
}

// // // // // //
//     GPU     //
// // // // // //

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
    res_240,
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

/// 1F801814h - GPU Display Control Commands (GP1)
/// https://psx-spx.consoledev.net/graphicsprocessingunitgpu/#gpu-display-control-commands-gp1
pub var GPU_GP1: *volatile u32 = @ptrFromInt(KSEG1 + 0x1f80_1814);

pub const GpuStat = packed struct(u32) {
    pub const SemiTransparency = enum(u2) {
        avg,
        add,
        subtract,
        add_quarter,
    };
    pub const TexturePageColors = enum(u2) {
        bits_4,
        bits_8,
        bits_15,
        _reserved,
    };
    pub const DrawPixels = enum(u1) {
        always,
        not_to_masked_areas,
    };
    pub const DmaDirection = enum(u2) {
        off,
        _unknown,
        cpu_to_gp0,
        gpu_to_cpu,
    };
    texpage_x_base: u4 = 0,
    texpage_y_base_1: u1 = 0,
    transparency: SemiTransparency = .avg,
    texpage_colors: TexturePageColors = .bits_4,
    dither: bool = false,
    draw_to_display_area_allowed: bool = false,
    set_mask_bit_when_drawing_pixels: bool = false,
    draw_pixels: DrawPixels = .always,
    interlace_field: bool = false,
    flip_h: bool = false,
    texture_page_y_base_2: u1 = 0,
    h_res: HorizontalResolution = .res_256,
    v_res: VerticalResolution = .res_240,
    video_mode: VideoMode = .ntsc,
    color_depth: ColorDepth = .bits_15,
    v_interlace: bool = false,
    blank: bool = false,
    interrupt: bool = false,
    dma: bool = false,
    ready_receive_cmd: bool = false,
    ready_send_vram: bool = false,
    ready_receive_dma_block: bool = false,
    dma_direction: DmaDirection = .off,
    draw_even_odd: u1 = 0,
};
/// 1F801814h - GPUSTAT - GPU Status Register (R)
pub var GPU_STAT: *volatile GpuStat = @ptrFromInt(KSEG1 + 0x1f80_1814);

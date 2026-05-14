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

/// 0 = on, 1 = off
pub const DisplayStatus = enum(u1) {
    on,
    off,
};

// GP1(00h) - Reset GPU
pub const ResetGpu = packed struct(u32) {
    _padding: u24 = 0,
    _cmd: u8 = 0x00,
};

// GP1(01h) - Reset Command Buffer
pub const ResetCommandBuffer = packed struct(u32) {
    _padding: u24 = 0,
    _cmd: u8 = 0x01,
};

// GP1(02h) - Acknowledge GPU Interrupt (IRQ1)
pub const AcknowledgeGpuInterrupt = packed struct(u32) {
    _padding: u24 = 0,
    _cmd: u8 = 0x02,
};

// GP1(03h) - Display Enable
pub const DisplayEnable = packed struct(u32) {
    /// NOTE: 0 = On, 1 = Off
    display: DisplayStatus = .on,
    _padding: u23 = 0,
    _cmd: u8 = 0x03,
};

pub const Gpu1Command = packed union(u32) {
    c_00: ResetGpu,
    c_01: ResetCommandBuffer,
    c_02: AcknowledgeGpuInterrupt,
    c_03: DisplayEnable,
};

/// 1F801814h - GPU Display Control Commands (GP1)
pub var GPU_GP1: *volatile Gpu1Command = @ptrFromInt(KSEG1 + 0x1f80_1814);

/// Write a command to the GPU_GP1 register.
/// The command must be defined in the `Gpu1Command` union.
pub fn writeGP1(cmd: anytype) void {
    const T = @TypeOf(cmd);
    // comptime nonsense to confirm the command is valid.
    const active_field_name = comptime block: {
        for (@typeInfo(Gpu1Command).@"union".fields) |field| {
            if (field.type == T) break :block field.name;
        }
        @compileError(@typeName(T) ++ " is not a valid GPU_GP1 command");
    };
    GPU_GP1.* = @unionInit(Gpu1Command, active_field_name, cmd);
}

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
    pub const HorizontalResolution = enum(u3) {
        res_256 = 0b000,
        res_368 = 0b001,
        res_320 = 0b010,
        res_512 = 0b100,
        res_640 = 0b110,
    };
    pub const VerticalResolution = enum(u1) {
        res_240 = 0,
        res_480 = 1,
    };
    pub const VideoMode = enum(u1) {
        ntsc,
        pal,
    };
    pub const ColorDepth = enum(u1) {
        bits_15,
        bits_24,
    };
    pub const DmaDirection = enum(u2) {
        off,
        _unknown,
        cpu_to_gp0,
        gpu_to_cpu,
    };
    texture_page_x_base: u4 = 0,
    texture_page_y_base_1: u1 = 0,
    semi_transparency: SemiTransparency = .avg,
    texture_page_colors: TexturePageColors = .bits_4,
    dither: bool = false,
    draw_to_display_area_allowed: bool = false,
    set_mask_bit_when_drawing_pixels: bool = false,
    draw_pixels: DrawPixels = .always,
    interlace_field: bool = false,
    flip_horizontal: bool = false,
    texture_page_y_base_2: u1 = 0,
    horizontal_resolution: HorizontalResolution = .res_256,
    vertical_resolution: VerticalResolution = .res_240,
    video_mode: VideoMode = .ntsc,
    display_area_color_depth: ColorDepth = .bits_15,
    vertical_interlace: bool = false,
    display: DisplayStatus = .on,
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

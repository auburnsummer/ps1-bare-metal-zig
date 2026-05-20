//! Definitions for hardware registers on the PSX.
//! REF: https://psx-spx.consoledev.net/

const gpu = @import("./gpu_cmd.zig");

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
    dtr: bool = false,
    rx_enable: bool = false,
    invert: bool = false,
    acknowledge: bool = false,
    rts: bool = false,
    reset: bool = false,
    _sio1_unknown: bool = false,
    rx_irq_mode: RxInterruptMode = .bytes_1,
    tx_irq_enable: bool = false,
    rx_irq_enable: bool = false,
    dsr_irq_enable: bool = false,
    port: Sio0PortSelect = .port_1,
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
    stop_bit_length: StopBitLength = .bits_1,
    clock_polarity: bool = false,
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
    rx_data: bool = false,
    tx_idle: bool = false,
    rx_parity_error: bool = false,
    rx_fifo_overrun: bool = false,
    rx_bad_stop_bit: bool = false,
    rx_inverted: bool = false,
    dsr_on: bool = false,
    cts: bool = false,
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

/// 1F801814h - GPU Display Control Commands (GP1)
/// https://psx-spx.consoledev.net/graphicsprocessingunitgpu/#gpu-display-control-commands-gp1
pub var GPU_GP1: *volatile u32 = @ptrFromInt(KSEG1 + 0x1f80_1814);

pub const GpuStat = packed struct(u32) {
    pub const DrawPixels = enum(u1) {
        always,
        not_to_masked_areas,
    };
    texpage_x_base: u4 = 0,
    texpage_y_base_1: u1 = 0,
    transparency: gpu.SemiTransparency = .avg,
    texpage_colors: gpu.TexpageColors = .bits_4,
    dither: bool = false,
    unlock_fb: bool = false,
    set_mask: bool = false,
    use_mask: DrawPixels = .always,
    interlace_field: bool = false,
    flip_h: bool = false,
    texture_page_y_base_2: u1 = 0,
    h_res: gpu.HorizontalResolution = .res_256,
    v_res: gpu.VerticalResolution = .res_240,
    video_mode: gpu.VideoMode = .ntsc,
    color_depth: gpu.ColorDepth = .bits_15,
    v_interlace: bool = false,
    blank: bool = false,
    irq: bool = false,
    data_req: bool = false,
    cmd_ready: bool = false,
    vram_send_ready: bool = false,
    dma_ready: bool = false,
    dma_direction: gpu.DmaRequestMode = .off,
    draw_even_odd: u1 = 0,
};
/// 1F801814h - GPUSTAT - GPU Status Register (R)
pub var GPU_STAT: *volatile GpuStat = @ptrFromInt(KSEG1 + 0x1f80_1814);

/// 1F801810h-Write GP0 -- Send GP0 Commands/Packets (Rendering and VRAM Access)
pub var GPU_GP0: *volatile u32 = @ptrFromInt(KSEG1 + 0x1F80_1810);

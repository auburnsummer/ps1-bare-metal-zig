//! Definitions for hardware registers on the PSX.
//! REF: https://psx-spx.consoledev.net/

const gpu = @import("./gpu_cmd.zig");

pub const F_CPU = 33868800;

/// This is the start of the KSEG1 region of memory, which is used for peripherals.
/// The documentation linked above gives memory locations as an offset from here.
const KSEG1: u32 = 0xA000_0000;

// // // // // //
// Interrupts  //
// // // // // //

pub const InterruptTable = packed struct(u32) {
    vblank: bool,
    gpu: bool,
    cdrom: bool,
    dma: bool,
    timer0: bool,
    timer1: bool,
    timer2: bool,
    sio0: bool,
    sio1: bool,
    spu: bool,
    lightgun: bool,
    _padding: u21 = 0,
};

/// 1F801070h I_STAT - Interrupt status register (R=Status, W=Acknowledge)
pub var IRQ_STAT: *volatile InterruptTable = @ptrFromInt(KSEG1 + 0x1f80_1070);

/// 1F801074h I_MASK - Interrupt mask register (R/W)
pub var IRQ_MASK: *volatile InterruptTable = @ptrFromInt(KSEG1 + 0x1f80_1074);

// // // // // //
//     DMA.    //
// // // // // //

pub const DmaControlSection = packed struct(u4) {
    priority: u3,
    enable: bool,
};

pub const DmaControl = packed struct(u32) {
    mdec_in: DmaControlSection,
    mdec_out: DmaControlSection,
    gpu: DmaControlSection,
    cdrom: DmaControlSection,
    spu: DmaControlSection,
    pio: DmaControlSection,
    otc: DmaControlSection,
    cpu: DmaControlSection,
};

/// 1F8010F0h - DPCR - DMA Control Register (R/W)
pub const DMA_DPCR: *volatile DmaControl = @ptrFromInt(KSEG1 + 0x1f80_10f0);

pub const DmaChannelName = enum(u3) { mdec_in, mdec_out, gpu, cdrom, spu, pio, otc };

pub const DmaTransferMode = enum(u2) {
    burst,
    slice,
    linked_list,
    _reserved,
};

pub const DmaChannelControl = packed struct(u32) {
    write: bool = false,
    reverse: bool = false,
    _padding1: u6 = 0,
    chopping: bool = false,
    mode: DmaTransferMode = .burst,
    _padding2: u5 = 0,
    chopping_dma_window: u3 = 0b000,
    _padding3: u1 = 0,
    chopping_cpu_window: u3 = 0b000,
    _padding4: u1 = 0,
    enable: bool = false,
    _padding5: u3 = 0,
    trigger: bool = false,
    /// burst mode only
    pause: bool = false,
    snoop: bool = false,
    _padding6: u1 = 0,
};

/// 1F801088h+N*10h - D#_CHCR - DMA Channel Control (Channel 0..6) (R/W)
pub fn DMA_CHCR(comptime n: DmaChannelName) *volatile DmaChannelControl {
    return @ptrFromInt(KSEG1 + 0x1F80_1088 + (0x10 * @as(u32, @intFromEnum(n))));
}

pub const DmaBaseAddress = packed struct(u32) {
    addr: u24,
    _padding: u8 = 0,
};

/// 1F801080h+N*10h - D#_MADR - DMA base address (Channel 0..6) (R/W)
pub fn DMA_MADR(comptime n: DmaChannelName) *volatile DmaBaseAddress {
    return @ptrFromInt(KSEG1 + 0x1F80_1080 + (0x10 * @as(u32, @intFromEnum(n))));
}

pub const DmaBlockControlMode0 = packed struct(u32) {
    num_words: u16,
    _padding: u16 = 0,
};
pub const DmaBlockControlMode1 = packed struct(u32) {
    chunk_size: u16,
    num_chunks: u16,
};
/// 1F801084h+N*10h - D#_BCR - DMA Block Control (Channel 0..6) (R/W)
pub fn DMA_BCR(comptime n: DmaChannelName) *volatile u32 {
    return @ptrFromInt(KSEG1 + 0x1f80_1084 + (0x10 * @as(u32, @intFromEnum(n))));
}

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
    transparency: gpu.BlendMode = .avg,
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

// // // // // //
// MEMORY CTRL //
// // // // // //
// From the docs:
// "The Memory Control registers are initialized by the BIOS, and, normally software doesn't need to change that settings.
// Some registers are useful for expansion hardware (allowing to increase the memory size and bus width)."
//
// I've only defined the one register we touch.

pub const Expansion2Control = packed struct(u32) {
    // There are interesting bits in the padding, I just haven't bothered defining them.
    _padding: u16,
    addr_bits: u5,
    _padding2: u11,
};

/// 1F80101Ch - Expansion 2 Delay/Size (usually 00070777h) (128 bytes, 8bit bus)
pub const SBUS_DEV8_CTRL: *volatile Expansion2Control = @ptrFromInt(KSEG1 + 0x1f80_101c);

// // // // // //
// PCSX-REDUX  //
// // // // // //
// These are fake registers that exist within the PCSX-Redux emulator.

/// 1F802080h 4 Redux-Expansion ID "PCSX" (R)
pub const PCSX_REDUX_ID: *volatile u32 = @ptrFromInt(KSEG1 + 0x1F80_2080);

/// 1F802080h 1 Redux-Expansion Console putchar (W)
pub var PCSX_CONSOLE_PUTCHAR: *volatile u8 = @ptrFromInt(KSEG1 + 0x1F80_2080);

/// 1F802081h 1 Redux-Expansion Debug break (W)
pub var PCSX_DEBUG_BREAK: *volatile u8 = @ptrFromInt(KSEG1 + 0x1f80_2081);

/// 1F802082h 1 Redux-Expansion Exit code (W)
pub var PCSX_EXIT: *volatile u8 = @ptrFromInt(KSEG1 + 0x1f80_2082);

/// 1F802084h 4 Redux-Expansion Notification message pointer (W)
pub var PCSX_MESSAGE: *align(4) volatile [*:0]const u8 = @ptrFromInt(KSEG1 + 0x1f80_2084);

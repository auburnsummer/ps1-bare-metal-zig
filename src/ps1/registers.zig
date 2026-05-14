//! Definitions for hardware registers on the PSX.
//! REF: https://psx-spx.consoledev.net/

pub const F_CPU = 33868800;

/// This is the start of the KSEG1 region of memory, which is used for peripherals.
/// The documentation linked above gives memory locations as an offset from here.
const KSEG1: u32 = 0xA000_0000;

// // // // // //
// Serial I/O  //
// // // // // //

/// 1F80104Ah+N*10h - SIO#_CTRL (R/W)
pub const SerialIoControl = packed struct(u16) {
    pub const RxInterruptMode = enum(u2) {
        bytes_1,
        bytes_2,
        bytes_4,
        bytes_8,
    };
    tx_enable: bool = false,
    dtr_output_level: u1 = 0,
    rx_enable: bool = false,
    sio1_tx_output_level: u1 = 0,
    acknowledge: bool = false,
    sio1_rts_output_level: u1 = 0,
    reset: bool = false,
    sio1_unknown: bool = false,
    rx_interrupt_mode: RxInterruptMode = .bytes_1,
    tx_interrupt_enable: bool = false,
    rx_interrupt_enable: bool = false,
    dsr_interrupt_enable: bool = false,
    sio0_port_select: bool = false,
    _padding: u2 = 0,
};

// Note on naming conventions: anything that is memory mapped to a hardware register is getting LOUD_YELLING_CASE to match
// the original C code. This is somewhat against Zig naming convention but I think it's nice to be able to tell at a glance
// when something is a peripheral.
pub fn SIO_CTRL(comptime n: u1) *volatile SerialIoControl {
    return @ptrFromInt(KSEG1 + 0x1F80_104A + (0x10 * @as(u32, n)));
}

/// 1F801048h+N*10h - SIO#_MODE (R/W)
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
pub fn SIO_MODE(comptime n: u1) *volatile SerialIoMode {
    return @ptrFromInt((KSEG1 + 0x1F80_1048) + (0x10 * @as(u32, n)));
}

/// 1F80104Eh+N*10h - SIO#_BAUD (R/W)
pub fn SIO_BAUD(comptime n: u1) *volatile u16 {
    return @ptrFromInt((KSEG1 + 0x1F80_104E) + (0x10 * @as(u32, n)));
}

/// 1F801044h+N*10h - SIO#_STAT (R)
pub const SerialIoStat = packed struct(u32) {
    tx_not_full: bool = false,
    rx_not_empty: bool = false,
    tx_idle: bool = false,
    rx_parity_error: bool = false,
    sio1_rx_fifo_overrun: bool = false,
    sio1_rx_bad_stop_bit: bool = false,
    sio1_rx_input_level: bool = false,
    dsr_input_level: bool = false,
    sio1_cts_input_level: bool = false,
    interrupt_request: bool = false,
    unknown: bool = false,
    baudrate_timer: u21 = 0,
};

pub fn SIO_STAT(comptime n: u1) *volatile SerialIoStat {
    return @ptrFromInt((KSEG1 + 0x1F80_1044) + (0x10 * @as(u32, n)));
}

/// 1F801040h+N*10h - SIO#_TX_DATA (W)
/// 1F801040h+N*10h - SIO#_RX_DATA (R)
/// This is the same register.
pub fn SIO_TX_DATA(comptime n: u1) *volatile u8 {
    return @ptrFromInt((KSEG1 + 0x1F80_1040) + (0x10 * @as(u32, n)));
}
pub fn SIO_RX_DATA(comptime n: u1) *volatile u8 {
    return SIO_TX_DATA(n);
}

// // // // // //
//     GPU     //
// // // // // //

// 1F801814h - GPU Display Control Commands (GP1)
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
    display_on_off: u1 = 0,
    _padding: u23 = 0,
    _cmd: u8 = 0x03,
};

pub const Gpu1Command = packed union(u32) {
    c_00: ResetGpu,
    c_01: ResetCommandBuffer,
    c_02: AcknowledgeGpuInterrupt,
    c_03: DisplayEnable,
};

pub var GPU_GP1: *volatile Gpu1Command = @ptrFromInt(KSEG1 + 0x1f80_1814);

pub fn writeGP1(cmd: anytype) void {
    const T = @TypeOf(cmd);
    const active_field_name = comptime block: {
        for (@typeInfo(Gpu1Command).@"union".fields) |field| {
            if (field.type == T) break :block field.name;
        }
        @compileError(@typeName(T) ++ " is not a valid GPU_GP1 command");
    };
    GPU_GP1.* = @unionInit(Gpu1Command, active_field_name, cmd);
}

// 1F801814h - GPUSTAT - GPU Status Register (R)
// Similar to SIO_TX_DATA / SIO_RX_DATA, this is the read version of the same register as GPU_GP1.
//   24    Interrupt Request (IRQ1)    (0=Off, 1=IRQ)       ;GP0(1Fh)/GP1(02h)
//   25    DMA / Data Request, meaning depends on GP1(04h) DMA Direction:
//           When GP1(04h)=0 ---> Always zero (0)
//           When GP1(04h)=1 ---> FIFO State  (0=Full, 1=Not Full)
//           When GP1(04h)=2 ---> Same as GPUSTAT.28
//           When GP1(04h)=3 ---> Same as GPUSTAT.27
//   26    Ready to receive Cmd Word   (0=No, 1=Ready)  ;GP0(...) ;via GP0
//   27    Ready to send VRAM to CPU   (0=No, 1=Ready)  ;GP0(C0h) ;via GPUREAD
//   28    Ready to receive DMA Block  (0=No, 1=Ready)  ;GP0(...) ;via GP0
//   29-30 DMA Direction (0=Off, 1=?, 2=CPUtoGP0, 3=GPUREADtoCPU)    ;GP1(04h).0-1
//   31    Drawing even/odd lines in interlace mode (0=Even or Vblank, 1=Odd)
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
    pub const DrawPixels = enum(u2) {
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
    texture_page_x_base: u3 = 0,
    texture_page_y_base_1: u1 = 0,
    semi_transparency: SemiTransparency = .avg,
    texture_page_colors: TexturePageColors = .bits_4,
    dither: bool = false,
    drawing_to_display_area_ok: bool = false,
    set_mask_bit_when_drawing_pixels: bool = false,
    draw_pixels: DrawPixels = .always,
    interlace: bool = false,
    flip_horizontal: bool = false,
    texture_page_y_base_2: u1 = 0,
    horizontal_resolution: HorizontalResolution = .res_256,
    vertical_resolution: VerticalResolution = .res_240,
    video_mode: VideoMode = .ntsc,
    display_area_color_depth: ColorDepth = .bits_15,
    vertical_interlace: bool = false,
    display_on_off: bool = false,
    interrupt_request: bool = false,
    dma: u2 = 0b00,
    ready_receive_cmd: bool = false,
    ready_send_vram: bool = false,
    ready_receive_dma_block: bool = false,
    dma_direction: DmaDirection = .off,
    draw_even_odd: u0 = 0,
};

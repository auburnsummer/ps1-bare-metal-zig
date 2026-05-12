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
        one_byte,
        two_bytes,
        four_bytes,
        eight_bytes,
    };
    tx_enable: bool = false,
    dtr_output_level: bool = false,
    rx_enable: bool = false,
    sio1_tx_output_level: bool = false,
    acknowledge: bool = false,
    sio1_rts_output_level: bool = false,
    reset: bool = false,
    sio1_unknown: bool = false,
    rx_interrupt_mode: RxInterruptMode = .one_byte,
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
    baudrate_reload_factor: BaudrateReloadFactor = .stop_mul1,
    character_length: u2 = 0b00,
    parity_enable: bool = false,
    parity_type: bool = false,
    sio1_stop_bit_length: u2 = 0b00,
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
    cmd: u8 = 0x00,
};

// GP1(01h) - Reset Command Buffer
pub const ResetCommandBuffer = packed struct(u32) {
    _padding: u24 = 0,
    cmd: u8 = 0x01,
};

// GP1(02h) - Acknowledge GPU Interrupt (IRQ1)
pub const AcknowledgeGpuInterrupt = packed struct(u32) {
    _padding: u24 = 0,
    cmd: u8 = 0x02,
};

// GP1(03h) - Display Enable
pub const DisplayEnable = packed struct(u32) {
    /// NOTE: 0 = On, 1 = Off
    display_on_off: u1 = 0,
    _padding: u23 = 0,
    cmd: u8 = 0x03,
};

pub const Gpu1Command = packed union(u32) {
    reset_gpu: ResetGpu,
    reset_command_buffer: ResetCommandBuffer,
    acknowledge_gpu_interrupt: AcknowledgeGpuInterrupt,
    display_enable: DisplayEnable,
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

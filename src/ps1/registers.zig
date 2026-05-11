//! Definitions for hardware registers on the PSX.
//! REF: https://psx-spx.consoledev.net/

pub const F_CPU = 33868800;

/// This is the start of the KSEG1 region of memory, which is used for peripherals.
/// The documentation linked above gives memory locations as an offset from here.
const KSEG1: u32 = 0xA000_0000;

/// 1F80104Ah+N*10h - SIO#_CTRL (R/W)
pub const SerialIoControl = packed struct(u16) {
    txEnable: bool = false,
    dtrOutputLevel: bool = false,
    rxEnable: bool = false,
    sio1TxOutputLevel: bool = false,
    acknowledge: bool = false,
    sio1RtsOutputLevel: bool = false,
    reset: bool = false,
    sio1Unknown: bool = false,
    rxInterruptMode: u2 = 0b00,
    txInterruptEnable: bool = false,
    rxInterruptEnable: bool = false,
    dsrInterruptEnable: bool = false,
    sio0PortSelect: bool = false,
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
    baudrateReloadFactor: u2 = 0b00,
    characterLength: u2 = 0b00,
    parityEnable: bool = false,
    parityType: bool = false,
    sio1StopBitLength: u2 = 0b00,
    sio0ClockPolarity: bool = false,
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
    txNotFull: bool = false,
    rxNotEmpty: bool = false,
    txIdle: bool = false,
    rxParityError: bool = false,
    sio1RxFifoOverrun: bool = false,
    sio1RxBadStopBit: bool = false,
    sio1RxInputLevel: bool = false,
    dsrInputLevel: bool = false,
    sio1CtsInputLevel: bool = false,
    interruptRequest: bool = false,
    unknown: bool = false,
    baudrateTimer: u21 = 0,
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

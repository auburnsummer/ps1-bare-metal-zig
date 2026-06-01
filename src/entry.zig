//! The entry point for our program.
//! In C-land this is called "crt0" and is responsible for initializing and then calling main().

const std = @import("std");
const logging = @import("runtime").logging;
const psx = @import("ps1").registers;

// Add memcpy/memset/memmove symbols to the binary which
// are used by std.fmt.bufPrint.
// Comptime in this case tells the compiler the import is required
// for its side effects (i.e. adding the symbols).
// Theoretically we could also get these by including Zig's compiler-rt
// library, but it doesn't currently support MIPS-I.
comptime {
    _ = @import("runtime").mem;
}

// TODO: panic function

// This sets the log function used by, e.g. std.log to our custom log
// function which writes to SIO1. The implementation is in runtime/logging.zig and
// is similar to what we did in 00_helloWorld. `logging.initSerialIo()` must
// be called before any logging will work.
//
// The default log function will attempt to write to stderr, which
// doesn't exist.
//
// TIP: if you are using PCSX-Redux, you can swap this out for a version in
// the runtime/pcsx module that prints to the PCSX-Redux console instead!
// const pcsx = @import("runtime").pcsx;
pub const std_options: std.Options = .{
    .logFn = logging.logFn,
};

/// This will be the name of the module to load, which depends on the -Mmain flag passed to zig build-exe.
const main_module = @import("main");

const bss_start = @extern([*]u8, .{ .name = "_bssStart" });
const bss_end = @extern([*]u8, .{ .name = "_bssEnd" });

// This is the name of the symbol Zig's linker will look for as the entry point
// on MIPS architectures. Note the two underscores.
export fn __start() noreturn {
    // Zero out the .bss section. Zero-initialised global variables go here.
    const len = bss_end - bss_start;
    @memset(bss_start[0..len], 0);

    // Set interrupt masks to disable all by default.
    // Note that IRQ_STAT still gets set; this is just to stop service routines from running.
    psx.IRQ_MASK.* = @bitCast(@as(u32, 0));

    // Expand the addressable memory of Expansion Region 2 to 256 bytes.
    // The PCSX-Redux emulator places debug registers outside the default 128 bytes set.
    if (psx.SBUS_DEV8_CTRL.addr_bits < 8) {
        psx.SBUS_DEV8_CTRL.addr_bits = 8;
    }

    // TODO: handle global constructors

    main_module.main();

    // TODO: handle global destructors
}

//! The entry point for our program.
//! In C-land this is called "crt0" and is responsible for initializing and then calling main().

const logging = @import("./libc/logging.zig");
const std = @import("std");

// Add the necessary memcpy/memset/memmove symbols to the binary which
// are used by std.fmt.bufPrint.
// Comptime in this case tells the compiler the import is required
// for its side effects (i.e. adding the symbols)
comptime {
    _ = @import("./libc/mem.zig");
}

// This sets the log function used by, e.g. std.log to our custom log
// function which writes to SIO1. The implementation is in libc/logging.zig and
// is similar to what we did the previous example. `logging.initSerialIO()` must
// be called before any logging will work.
//
// The default log function will attempt to write to stderr, which
// doesn't exist.
pub const std_options: std.Options = .{
    .logFn = logging.logFn,
};

/// This will be the name of the module to load, which depends on the -Mmain flag passed to zig build-exe.
const main_module = @import("main");

// This is the name of the symbol Zig's linker will look for as the entry point
// on MIPS architectures. Note the two underscores.
export fn __start() noreturn {
    main_module.main();
}

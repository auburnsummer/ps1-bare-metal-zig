# Playstation 1 bare-metal Zig examples

This is an EXPERIMENTAL attempt at doing some homebrew development for the
original PlayStation 1 using the Zig programming language.

The approach is to try and port spicyjpeg's excellent [ps1-bare-metal][1] but
using Zig instead.

This is mostly an educational project for myself, however, I hope that it
might be a little bit useful if anyone else ends up searching for something similar.

So far I have managed to get SERIAL WORKING and ONE TRIANGLE ON SCREEN woohoo!

## BIG DISCLAIMER

When you try to compile Zig for MIPS-I, it has a warning `MIPS-I support is experimental`.

I have decided to naively ignore this. This is almost certainly going to
bite me once I work further through the ps1-bare-metal examples and run
into something that isn't supported properly yet (...maybe the GTE stuff but we'll see)


[1]: https://github.com/spicyjpeg/ps1-bare-metal

### Zig with MIPS-I notes

 - pass `no-compiler-rt` flag when compiling. otherwise it tries to emit a SYNC
   instruction which doesn't exist in MIPS-I when compiling atomics.zig in compiler-rt
 - pass `-OReleaseFast` when compiling, the division safety check Zig emits uses
   `teq` instruction which doesn't exist in MIPS-I
 - `zig objdump` doesn't work for ELF files yet, but you can use `mipsel-none-elf-objdump` instead, e.g.
   `mipsel-none-elf-objdump -d -S -M no-aliases <elf file>`
 - The aforementioned `MIPS-I support is experimental` warning is treated as an error
   in zig.build so we're using a Makefile for now
 - Zig toolchain doesn't respect the `ENTRY(...)` directive in the linker, you have to
   pass it it in the `zig build-exe` command
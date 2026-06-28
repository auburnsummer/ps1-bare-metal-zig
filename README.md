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
   pass it it in the `zig build-exe` command instead
 - When writing to a PSX register represented via a volatile packed struct,
   do not directly assign an anonymous struct literal:

No:

```zig
psx.DMA_CHCR(.gpu).* = .{
    .write = true,
    .mode = .linked_list,
    .enable = true,
};
``` 

Instead do:

```zig
psx.DMA_CHCR(.gpu).* = psx.DmaChannelControl{
    .write = true,
    .mode = .linked_list,
    .enable = true,
};
``` 

These are actually different! The first one, Zig will directly instantiate the literal
on top of the volatile register, which results in multiple stores (one for each
field of the struct). The intermediate states between stores can cause unexpected behaviour -- e.g. with
DMA_CHCR, Zig will write to `enable` multiple times, firing off the DMA multiple times.

The second one does a single write as expected because the entire struct is instantiated
before its written.

It's related to Zig's "result location semantics", which should go away with Zig 0.18 see codeberg.org/ziglang/zig/issues/32009 

### ...so should I use Zig to make PS1 games?

I wouldn't recommend it at the moment, setting up Zig to compile to MIPS-I is very hacky,
and I'm uncertain how stable
LLVM's support for MIPS-I is. I've already ran into one LLVM MIPS-I bug (it can emit
`teq`) and there may be more that I haven't ran into yet.

It's also possible (although I haven't looked into it yet), that the generated MIPS machine
code from Zig/LLVM is slower / missing optimisations compared to a C toolchain.

I'm also a beginner at both Zig programming and PS1 programming, and as a result, my
code is probably both non-idiomatic and non-optimal.

For actually being productive in making a game, the best options are [psyqo](https://github.com/grumpycoders/pcsx-redux/blob/main/src/mips/psyqo/GETTING_STARTED.md) (a C++ SDK)

or just go with C using [ps1-bare-metal][1] as a guide.
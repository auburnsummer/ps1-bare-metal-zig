# Playstation 1 bare-metal Zig examples

This is an EXPERIMENTAL attempt at doing some homebrew development for the
original PlayStation 1 using the Zig programming language.

The approach is to try and port spicyjpeg's excellent [ps1-bare-metal][1] but
using Zig instead.

This is mostly an educational project for myself, however, I hope that it
might be a little bit useful if anyone else ends up searching for something similar.

So far I have managed to get SERIAL WORKING woohoo! nothing on the screen yet
though.

## BIG DISCLAIMER

When you try to compile Zig for MIPS-I, it has a warning `MIPS-I support is experimental`.

I have decided to naively ignore this. This is almost certainly going to
bite me once I work further through the ps1-bare-metal examples and run
into something that isn't supported properly yet (...likely the GTE stuff but we'll see)


[1]: https://github.com/spicyjpeg/ps1-bare-metal


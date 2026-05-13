# you might be wondering, why is this a makefile instead of zig build system?
# because Zig's build throws a warning "MIPS-I support is experimental"
# but this warning cannot be ignored and is treated as an error by the build system.

# you might be wondering, why not cmake?
# i am scared of cmake
.PHONY: all
all: build/00_helloWorld.psexe build/01_basicGraphics.psexe

.DEFAULT_GOAL := all

build/00_helloWorld.elf: $(shell find -L src/00_helloWorld/* -type f)
	zig build-exe \
		-target mipsel-freestanding \
		-mcpu mips1 \
		-fno-compiler-rt \
		-fno-ubsan-rt \
		-fentry=main \
		--script ./build_helpers/executable.ld \
		./src/00_helloWorld/main.zig \
		-femit-bin=build/00_helloWorld.elf

build/00_helloWorld.psexe: build/00_helloWorld.elf
	python3 ./build_helpers/convertExecutable.py build/00_helloWorld.elf build/00_helloWorld.psexe

build/01_basicGraphics.elf: $(shell find -L src/01_basicGraphics/* -type f)
	zig build-exe \
		-target mipsel-freestanding \
		-mcpu mips1 \
		-fno-compiler-rt \
		-fno-ubsan-rt \
		-fentry=main \
		--script ./build_helpers/executable.ld \
		./src/01_basicGraphics/main.zig \
		-femit-bin=build/01_basicGraphics.elf

build/01_basicGraphics.psexe: build/01_basicGraphics.elf
	python3 ./build_helpers/convertExecutable.py build/01_basicGraphics.elf build/01_basicGraphics.psexe
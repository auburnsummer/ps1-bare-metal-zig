# you might be wondering, why is this a makefile instead of zig build system?
# because Zig's build throws a warning "MIPS-I support is experimental"
# but this warning cannot be ignored and is treated as an error by the build system.

# you might be wondering, why not cmake?
# i am scared of cmake

ZIG_FLAGS = \
	-target mipsel-freestanding \
	-mcpu mips1 \
	-OReleaseFast \
	-fno-compiler-rt \
	-fno-ubsan-rt

ENTRY_MODULE = \
	--dep main --dep runtime \
	-Mroot=./src/entry.zig \

# Shared module declarations. 
# `libc` depends on `ps1`.
SHARED_MODULES = \
	-Mps1=./src/ps1/ps1.zig \
	--dep ps1 \
	-Mruntime=./src/runtime/runtime.zig

.PHONY: all
all: build/00_helloWorld.psexe build/01_basicGraphics.psexe build/02_doubleBuffer.psexe

.DEFAULT_GOAL := all

build/00_helloWorld.elf: $(shell find -L src/00_helloWorld src/ps1 src/runtime src/entry.zig -type f)
	zig build-exe \
		$(ZIG_FLAGS) \
		$(ENTRY_MODULE) \
		--dep ps1 \
		-Mmain=./src/00_helloWorld/main.zig \
		$(SHARED_MODULES) \
		--script ./build_helpers/executable.ld \
		-femit-bin=build/00_helloWorld.elf

build/00_helloWorld.psexe: build/00_helloWorld.elf
	python3 ./build_helpers/convertExecutable.py build/00_helloWorld.elf build/00_helloWorld.psexe

build/01_basicGraphics.elf: $(shell find -L src/01_basicGraphics src/ps1 src/runtime src/entry.zig -type f)
	zig build-exe \
		$(ZIG_FLAGS) \
		$(ENTRY_MODULE) \
		--dep ps1 --dep runtime \
		-Mmain=./src/01_basicGraphics/main.zig \
		$(SHARED_MODULES) \
		--script ./build_helpers/executable.ld \
		-femit-bin=build/01_basicGraphics.elf

build/01_basicGraphics.psexe: build/01_basicGraphics.elf
	python3 ./build_helpers/convertExecutable.py build/01_basicGraphics.elf build/01_basicGraphics.psexe

build/02_doubleBuffer.elf: $(shell find -L src/02_doubleBuffer src/ps1 src/runtime src/entry.zig -type f)
	zig build-exe \
		$(ZIG_FLAGS) \
		$(ENTRY_MODULE) \
		--dep ps1 --dep runtime \
		-Mmain=./src/02_doubleBuffer/main.zig \
		$(SHARED_MODULES) \
		--script ./build_helpers/executable.ld \
		-femit-bin=build/02_doubleBuffer.elf

build/02_doubleBuffer.psexe: build/02_doubleBuffer.elf
	python3 ./build_helpers/convertExecutable.py build/02_doubleBuffer.elf build/02_doubleBuffer.psexe

# you might be wondering, why is this a makefile instead of zig build system?
# because Zig's build throws a warning "MIPS-I support is experimental"
# but this warning cannot be ignored and is treated as an error by the build system.

ZIG_FLAGS = \
	-target mipsel-freestanding \
	-mcpu mips1 \
	-OReleaseFast \
	-fno-compiler-rt \
	-fno-ubsan-rt \
	-fsingle-threaded

ENTRY_MODULE = \
	--dep main --dep runtime --dep ps1 \
	-Mroot=./src/entry.zig \

# Shared module declarations. 
# `runtime` depends on `ps1`.
SHARED_MODULES = \
	-Mps1=./src/ps1/ps1.zig \
	--dep ps1 \
	-Mruntime=./src/runtime/runtime.zig

.PHONY: all
all: build/00_helloWorld.psexe\
	build/01_basicGraphics.psexe\
	build/02_doubleBuffer.psexe\
	build/03_dmaChain.psexe\
	build/04_textures.psexe \
	build/05_palettes.psexe

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
	uv run ./tools/convertExecutable.py build/00_helloWorld.elf build/00_helloWorld.psexe

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
	uv run ./tools/convertExecutable.py build/01_basicGraphics.elf build/01_basicGraphics.psexe

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
	uv run ./tools/convertExecutable.py build/02_doubleBuffer.elf build/02_doubleBuffer.psexe

build/03_dmaChain.elf: $(shell find -L src/03_dmaChain src/ps1 src/runtime src/entry.zig -type f)
	zig build-exe \
		$(ZIG_FLAGS) \
		$(ENTRY_MODULE) \
		--dep ps1 --dep runtime \
		-Mmain=./src/03_dmaChain/main.zig \
		$(SHARED_MODULES) \
		--script ./build_helpers/executable.ld \
		-femit-bin=build/03_dmaChain.elf

build/03_dmaChain.psexe: build/03_dmaChain.elf
	uv run ./tools/convertExecutable.py build/03_dmaChain.elf build/03_dmaChain.psexe

src/04_textures/generated/texture.bin: src/04_textures/texture.png
	uv run ./tools/convertImage.py src/04_textures/texture.png src/04_textures/generated/texture.bin

build/04_textures.elf: $(shell find -L src/04_textures src/ps1 src/runtime src/entry.zig -type f) src/04_textures/generated/texture.bin
	zig build-exe \
		$(ZIG_FLAGS) \
		$(ENTRY_MODULE) \
		--dep ps1 --dep runtime \
		-Mmain=./src/04_textures/main.zig \
		$(SHARED_MODULES) \
		--script ./build_helpers/executable.ld \
		-femit-bin=build/04_textures.elf

build/04_textures.psexe: build/04_textures.elf
	uv run ./tools/convertExecutable.py build/04_textures.elf build/04_textures.psexe

src/05_palettes/generated/palette.bin: src/05_palettes/texture.png
	uv run ./tools/convertImage.py --bpp=4 src/05_palettes/texture.png src/05_palettes/generated/texture.bin src/05_palettes/generated/palette.bin

build/05_palettes.elf: $(shell find -L src/05_palettes src/ps1 src/runtime src/entry.zig -type f) src/05_palettes/generated/texture.bin src/05_palettes/generated/palette.bin
	zig build-exe \
		$(ZIG_FLAGS) \
		$(ENTRY_MODULE) \
		--dep ps1 --dep runtime \
		-Mmain=./src/05_palettes/main.zig \
		$(SHARED_MODULES) \
		--script ./build_helpers/executable.ld \
		-femit-bin=build/05_palettes.elf

build/05_palettes.psexe: build/05_palettes.elf
	uv run ./tools/convertExecutable.py build/05_palettes.elf build/05_palettes.psexe

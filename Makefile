# you might be wondering, why is this a makefile instead of zig build system?
# because Zig's build throws a warning "MIPS-I support is experimental"
# but this warning cannot be ignored and is treated as an error by the build system.

# you might be wondering, why not cmake?
# i am scared of cmake

.DEFAULT_GOAL := build/helloWorld.psexe

build/helloWorld.o: src/00_helloWorld/*
	zig build-obj \
		-target mipsel-freestanding \
		-mcpu mips1 \
		-fno-compiler-rt \
		./src/00_helloWorld/main.zig \
		-femit-bin=build/helloWorld.o

build/helloWorld.elf: build/helloWorld.o
	zig ld.lld \
		-T ./build_helpers/executable.ld \
		-o build/helloWorld.elf build/helloWorld.o

build/helloWorld.psexe: build/helloWorld.elf
	python3 ./build_helpers/convertExecutable.py build/helloWorld.elf build/helloWorld.psexe
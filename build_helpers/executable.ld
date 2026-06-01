/*
 * ps1-bare-metal - (C) 2023-2025 spicyjpeg
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
 * REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
 * INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
 * LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
 * OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 */

/*
 * ENTRY(..) is omitted here, as it is overridden by the Zig
 * compiler to whatever is passed in in `-fentry`, or otherwise `__entry`.
 *
 * (see lib/std/start.zig and src/link/Lld.zig in the Zig source)
 */

MEMORY {
	/*
	 * Only 2 MB of main RAM are available on a regular console, but some
	 * development kits are fitted with 8 MB and most emulators have an option
	 * to extend RAM to 8 MB as well. You may change the length below from
	 * 0x1f0000 to 0x7f0000 allow the linker to use the additional memory. Note
	 * that the first 64 KB at 0x80000000-0x8000ffff are always reserved for use
	 * by the kernel.
	 */
	APP_RAM (rwx) : ORIGIN = 0x80010000, LENGTH = 0x1f0000
}

SECTIONS {
	/* Code sections */

	.text : ALIGN(4) {
		_textStart = .;

		*(.text .text.* .gnu.linkonce.t.*)
		*(.plt .MIPS.stubs)
	} > APP_RAM

	.rodata : {
		*(.rodata .rodata.* .gnu.linkonce.r.*)

		_textEnd = .;
	} > APP_RAM

	/* Global constructor/destructor arrays */

	.preinit_array : ALIGN(4) {
		_preinitArrayStart = .;

		KEEP(*(.preinit_array))

		_preinitArrayEnd = .;
	} > APP_RAM

	.init_array : ALIGN(4) {
		_initArrayStart = .;

		KEEP(*(SORT(.init_array.*) SORT(.ctors.*)))
		KEEP(*(.init_array .ctors))

		_initArrayEnd = .;
	} > APP_RAM

	.fini_array : ALIGN(4) {
		_finiArrayStart = .;

		KEEP(*(.fini_array .dtors))
		KEEP(*(SORT(.fini_array.*) SORT(.dtors.*)))

		_finiArrayEnd = .;
	} > APP_RAM

	/* Data sections */

	.data : {
		_dataStart = .;

		*(.data .data.* .gnu.linkonce.d.*)

		_dataEnd = .;
	} > APP_RAM

	.sdata : {
		*(.sdata .sdata.* .gnu.linkonce.s.*)
	} > APP_RAM
	/*
	 * We don't support $gp as a global pointer (i.e. -mno-abicalls)
	 */
	ASSERT(SIZEOF(.sdata) == 0, "ERROR: .sdata is non-empty.")

	/*
	 * Ensure the entire BSS region is aligned at both ends in order to allow
	 * for fast clearing.
	 */
	.bss (NOLOAD) : ALIGN(4) {
		_bssStart = .;

		*(.bss .bss.* .gnu.linkonce.b.*)
		*(COMMON)

		.       = ALIGN(4);
		_bssEnd = .;
	} > APP_RAM

	.sbss (NOLOAD) : {
		*(.sbss .sbss.* .gnu.linkonce.sb.*)
		*(.scommon)
	} > APP_RAM
	ASSERT(SIZEOF(.sbss) == 0, "ERROR: .sbss is non-empty.")

	/* Dummy sections */

	.dummy (NOLOAD) : {
		KEEP(*(.dummy))
	} > APP_RAM

	/DISCARD/ : {
		*(.note.* .gnu_debuglink .gnu.lto_*)
		*(.MIPS.abiflags)
	}
}

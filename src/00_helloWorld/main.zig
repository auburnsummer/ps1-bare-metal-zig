// MIT License

// Copyright (c) 2023 spicyjpeg
// Copyright (c) 2026 auburnsummer

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Let's start with the absolute basics, the obligatory hello world program. We
// are going to just print "Hello world!" in an infinite loop; since we don't
// have the luxury of a terminal or even anything resembling a "text mode" on
// the GPU, we'll use the PS1's serial port instead.
//
// The serial port can be found on the back of the console on all models except
// the PSone, and can be connected to a PC with an appropriately modified link
// cable. Internally it is connected to the secondary serial interface, known as
// SIO1 (as opposed to SIO0 which is wired to the controller and memory card
// ports). SIO1 is controlled through I/O registers, which we're going to
// manipulate to get it to output our message.
//
// On the PCSX-Redux emulator, the output of the SIO1 interface can be viewed
// by setting Configuration -> Emulation -> Enable SIO1 Server. Then, in a separate
// terminal window run:
//  `nc localhost 6699` (or whatever port you configured it to) to see the output.

const psx = @import("./ps1/registers.zig");

fn printCharacter(char: u8) void {
    // Wait until the serial interface is ready to send a new byte, then write
    // it to the data register.
    // NOTE: the serial interface checks for an external signal (CTS) and will
    // *not* send any data until it is asserted. To avoid blocking forever if
    // CTS is not asserted, we check for it manually and exit this function
    // without doing anything.
    while (psx.SIO_STAT(1).sio1_cts_on and !psx.SIO_STAT(1).tx_ready) {}

    if (psx.SIO_STAT(1).sio1_cts_on) {
        psx.SIO_TX_DATA(1).* = char;
    }
}

pub fn main() noreturn {
    // Reset the serial interface...
    psx.SIO_CTRL(1).reset = true;

    // ...and initialize it to output data with
    // 8 data bits, 1 stop bit and no parity...
    psx.SIO_MODE(1).* = .{
        .baud = .mul1,
        .char_length = .bits_8,
        .sio1_stop_bit_length = .bits_1,
    };

    // ...at 115200bps.
    psx.SIO_BAUD(1).* = psx.F_CPU / 115200;

    // Turn SIO1 on.
    // By the way, if you're confused about what these registers are,
    // each register is commented with its address in the PS1. You can
    // look them up at https://psx-spx.consoledev.net/ which gives a
    // description of each bit.
    psx.SIO_CTRL(1).* = .{
        .tx_enable = true,
        .rx_enable = true,
        .sio1_rts_on = true,
    };

    // Output "Hello world!" in a loop, one character at a time.
    const string = "Hello world!\n";

    while (true) {
        for (string) |char| {
            printCharacter(char);
        }
    }

    // We're not actually going to return. Unless a loader was used to launch
    // the program, returning from __start() would crash the console as there would
    // be nothing to return to.
}

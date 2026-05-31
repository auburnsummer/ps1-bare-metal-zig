// ps1-bare-metal - (C) 2023-2025 spicyjpeg
// ps1-bare-metal-zig - (C) 2026 auburnsummer

// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.

// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// THER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

// /*
//  * In the previous two examples we saw how to control the GPU and draw graphics
//  * by writing commands directly to the GP0 and GP1 registers. While this
//  * approach is simple and easy to understand, it also limits performance: the
//  * CPU always has to wait for the GPU to go idle before being able to send it a
//  * new command, otherwise the GPU may miss it; similarly, the GPU can only
//  * process commands while the CPU is actively feeding it.
//  *
//  * To get around these limitations the GPU (along with most of the PS1's other
//  * peripherals) can instead be given access to RAM and read GP0 commands from it
//  * automatically, without needing the CPU to feed it. This is accomplished
//  * through a middleman peripheral known as the direct memory access (DMA)
//  * controller, and is the key to high-performance graphics on the PS1. We'll see
//  * how to allocate a buffer in RAM, fill it with commands and then set up the
//  * GPU's DMA channel to read from it in the background while we're preparing the
//  * next frame's command buffer.
//  */

const std = @import("std");
const logging = @import("runtime").logging;
const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;
const gpu = @import("runtime").gpu;

const screen_width: u10 = 320;
const screen_height = 240;

fn waitForVSync() void {
    // The GPU won't tell us directly whenever it is done sending a frame to the
    // display, but it will send a signal to another peripheral known as the
    // interrupt controller (which will be covered in a future tutorial). We can
    // thus wait until the interrupt controller's vertical blank flag gets set,
    // then reset (acknowledge) it so that it can be set again by the GPU.
    while (!psx.IRQ_STAT.vblank) {}

    // acknowledge
    psx.IRQ_STAT.vblank = false;
}

pub fn setupGpu(
    mode: gpuc.VideoMode,
    width: u32,
    height: u32,
) void {
    const x: u32 = 0x760;
    const y: u32 = if (mode == .pal) 0xa3 else 0x88;

    const h_res: gpuc.HorizontalResolution = .res_320;
    const v_res: gpuc.VerticalResolution = .res_240;

    const offset_x = (width * gpuc.getGpuClockMultiplerH(h_res)) / 2;
    const offset_y = (height / gpuc.getGpuClockMultipleV(v_res)) / 2;

    psx.GPU_GP1.* = gpuc.gp1ResetGpu();
    psx.GPU_GP1.* = gpuc.gp1FbRangeH(
        @truncate(x - offset_x),
        @truncate(x + offset_x),
    );
    psx.GPU_GP1.* = gpuc.gp1FbRangeV(
        @truncate(y - offset_y),
        @truncate(y + offset_y),
    );
    psx.GPU_GP1.* = gpuc.gp1FbMode(
        h_res,
        v_res,
        mode,
        false,
        .bits_15,
    );
    psx.GPU_GP1.* = gpuc.gp1Blank(false);

    // Enable and reset the GPU's DMA channel, then tell the GPU to fetch GP0
    // commands from DMA whenever available.
    psx.DMA_DPCR.gpu.enable = true;
    psx.DMA_CHCR(.gpu).* = @bitCast(@as(u32, 0));

    psx.GPU_GP1.* = gpuc.gp1DmaRequestMode(.cpu_to_gp0);
}

fn clip(x: i16) u16 {
    return @max(0, x);
}

/// Holds a pointer to the header and data sections of a packet.
/// It's important that the header and the data are adjacent in memory, so
/// use allocateGp0Packet to make one of these.
const DmaPacket = struct { header: *gpuc.DmaTag, data: []u32 };

const dma_max_chunk_size = 16;
const gpa_chain_buffer_size = 1024;

// for this example, I'll just allocate two buffers to store commands in,
// one for each framebuffer.
var chain_1: [gpa_chain_buffer_size]u8 = undefined;
var chain_2: [gpa_chain_buffer_size]u8 = undefined;

fn allocateGp0Packet(al: std.mem.Allocator, num_commands: u4) DmaPacket {
    // allocate memory. we need enough to store the header of the packet + commands.
    // the DMA must read from 4-byte aligned boundaries.
    const buffer = al.alignedAlloc(u32, .@"4", num_commands + 1) catch unreachable;
    // first word is the header.
    const header_ptr: *gpuc.DmaTag = @ptrCast(buffer.ptr);
    // we'll set the length as well while we're here.
    header_ptr.len = num_commands;
    // the remainder of the buffer is the data.
    return .{
        .header = header_ptr,
        .data = buffer[1..],
    };
}

fn sendGpuLinkedList(ptr: *u32) void {
    // Wait until the GPU's DMA unit has finished sending data and is ready.
    while (psx.DMA_CHCR(.gpu).enable) {}

    // Give DMA a pointer to the beginning of the data and tell it to send it in
    // linked list mode. The DMA unit will start parsing a chain of "packets"
    // from RAM, with each packet being made up of a 32-bit header followed by
    // zero or more 32-bit commands to be sent to the GP0 register.
    psx.DMA_MADR(.gpu).addr = @truncate(@intFromPtr(ptr));
    // Explicitly name the type to avoid Zig inlining this into multiple stores.
    psx.DMA_CHCR(.gpu).* = psx.DmaChannelControl{
        .write = true,
        .mode = .linked_list,
        .enable = true,
    };
}

pub fn main() noreturn {
    logging.initSerialIo();

    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        setupGpu(.pal, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        setupGpu(.ntsc, screen_width, screen_height);
    }

    var x: i16 = 0;
    var dx: i16 = 1;
    var y: i16 = 0;
    var dy: i16 = 1;

    var using_second_frame: bool = false;

    while (true) {
        // Determine the VRAM location of the current frame. We're going to
        // place the two frames next to each other in VRAM, at (0, 0) and
        // (320, 0) respectively.
        const frame_x: u10 = if (using_second_frame) screen_width else 0;
        const frame_y = 0;

        using_second_frame = !using_second_frame;

        // Display the frame that was just drawn by the GPU (if any). We are
        // going to overwrite its respective DMA chain afterwards, as the GPU no
        // longer needs it.
        psx.GPU_GP1.* = gpuc.gp1FbOffset(frame_x, frame_y);

        // Reassign the allocator back to the start of the chain.
        var fba: std.heap.FixedBufferAllocator = if (using_second_frame) .init(&chain_1) else .init(&chain_2);
        const allocator = fba.allocator();

        // Create a new DMA packet for each GP0 command we're sending. Splitting
        // up each command like this will make sure the DMA channel won't try to
        // send them too quickly and end up overflowing the GPU's internal
        // command processor.
        const packet_1 = allocateGp0Packet(allocator, 4);
        packet_1.data[0] = gpuc.gp0SetPage(.{}, true, false);
        packet_1.data[1] = gpuc.gp0FbOffset1(frame_x, frame_y);
        packet_1.data[2] = gpuc.gp0FbOffset2(
            frame_x + screen_width - 1,
            frame_y + screen_height - 1,
        );
        packet_1.data[3] = gpuc.gp0FbOrigin(frame_x, frame_y);

        // Next packet (grey background). Allocate it...
        const packet_2 = allocateGp0Packet(allocator, 3);
        // Now we can point the header of the previous packet to this one.
        packet_1.header.next = @truncate(@intFromPtr(packet_2.header));
        packet_2.data[0] = gpuc.gp0VramFill(.{ .r = 64, .g = 64, .b = 64 });
        packet_2.data[1] = gpuc.gp0XY(frame_x, frame_y);
        packet_2.data[2] = gpuc.gp0WidthHeight(screen_width, screen_height);

        // Next packet (yellow bouncing square.)
        const packet_3 = allocateGp0Packet(allocator, 3);
        packet_2.header.next = @truncate(@intFromPtr(packet_3.header));
        packet_3.data[0] = gpuc.gp0Rectangle(
            .{ .r = 255, .g = 255, .b = 0 },
            false,
            false,
            false,
            .px_variable,
        );
        packet_3.data[1] = gpuc.gp0XY(clip(x), clip(y));
        packet_3.data[2] = gpuc.gp0WidthHeight(32, 32);

        // Terminate the linked list by pointing the last packet to a terminator header:
        // a header with 0 length and next address 0xFFFFFF.
        const packet_4 = allocateGp0Packet(allocator, 0);
        packet_3.header.next = @truncate(@intFromPtr(packet_4.header));

        packet_4.header.next = 0xFFFFFF;

        // Update the position of the square.
        x = x +| dx;
        y = y +| dy;

        if (x <= 0 or x >= (screen_width - 32)) {
            dx = -dx;
        }
        if (y <= 0 or y >= (screen_height - 32)) {
            dy = -dy;
        }

        // Wait for the previous frame to be displayed, then start sending the
        // newly built DMA chain in the background while the next iteration of
        // the main loop is going to run.
        gpu.waitForGp0Ready();
        waitForVSync();

        sendGpuLinkedList(@ptrCast(packet_1.header));
    }
}

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

//
// In the previous two examples we saw how to control the GPU and draw graphics
// by writing commands directly to the GP0 and GP1 registers. While this
// approach is simple and easy to understand, it also limits performance: the
// CPU always has to wait for the GPU to go idle before being able to send it a
// new command, otherwise the GPU may miss it; similarly, the GPU can only
// process commands while the CPU is actively feeding it.
//
// To get around these limitations the GPU (along with most of the PS1's other
// peripherals) can instead be given access to RAM and read GP0 commands from it
// automatically, without needing the CPU to feed it. This is accomplished
// through a middleman peripheral known as the direct memory access (DMA)
// controller, and is the key to high-performance graphics on the PS1. We'll see
// how to allocate a buffer in RAM, fill it with commands and then set up the
// GPU's DMA channel to read from it in the background while we're preparing the
// next frame's command buffer.
//

const std = @import("std");
const logging = @import("runtime").logging;
const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;
const gpu = @import("runtime").gpu;
const pcsx = @import("runtime").pcsx;
const debug = @import("runtime").debug;

const screen_width: u10 = 320;
const screen_height = 240;

// We're going to convert our texture into raw binary data using a Python script
// and embed it into this array using @embedFile.
// The data needs to be aligned to 4-byte intervals, which we can do by adding
// an align(4) annotation to the dereferenced data.
const texture_data align(4) = @embedFile("./generated/texture.bin").*;

fn waitForGpuDmaDone() void {
    while (psx.DMA_CHCR(.gpu).enable) {}
}

fn sendVramData(
    data: [*]const u8,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
) void {
    waitForGpuDmaDone();
    debug.assert(@intFromPtr(data) % 4 == 0, "dma vram align");
    // Calculate how many 32-bit words will be sent from the width and height of
    // the texture. If more than 16 words have to be sent, configure DMA to
    // split the transfer into 16-word chunks in order to make sure the GPU will
    // not miss any data.
    const length = std.math.divCeil(u16, width * height, 2) catch unreachable;
    std.log.info("length {x}", .{length});
    var chunk_size: u16 = 0;
    var num_chunks: u16 = 0;
    if (length < dma_max_chunk_size) {
        chunk_size = length;
        num_chunks = 1;
    } else {
        // Make sure the length is an exact multiple of 16 words, as otherwise
        // the last chunk would be dropped (the DMA unit does not support
        // "incomplete" chunks). Note that this will impose limitations on the
        // size of VRAM uploads.
        debug.assert(length % dma_max_chunk_size == 0, "dma length");
        chunk_size = dma_max_chunk_size;
        num_chunks = length / dma_max_chunk_size;
        std.log.info("Chunk size {x} num_chunks {x}", .{ chunk_size, num_chunks });
    }

    // Put the GPU into VRAM upload mode by sending the appropriate GP0 command
    // and our coordinates.
    gpu.waitForGp0Ready();
    psx.GPU_GP0.* = gpuc.gp0MemoryTransferMode(.write);
    psx.GPU_GP0.* = gpuc.gp0XY(x, y);
    psx.GPU_GP0.* = gpuc.gp0WidthHeight(width, height);

    // Give DMA a pointer to the beginning of the data and tell it to send it in
    // slice (chunked) mode.
    psx.DMA_MADR(.gpu).addr = @truncate(@intFromPtr(data));
    psx.DMA_BCR(.gpu).* = @bitCast(psx.DmaBlockControlMode1{
        .chunk_size = chunk_size,
        .num_chunks = num_chunks,
    });
    psx.DMA_CHCR(.gpu).* = psx.DmaChannelControl{
        .write = true,
        .mode = .slice,
        .enable = true,
    };
}

const TextureInfo = struct {
    u: u8 = 0,
    v: u8 = 0,
    width: u16 = 0,
    height: u16 = 0,
    page: gpuc.TexpageAttribute = .{},
};

fn uploadTexture(
    data: [*]const u8,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
) TextureInfo {
    // Make sure the texture's size is valid. The GPU does not support textures
    // larger than 256x256 pixels.
    debug.assert((width <= 256) and (height <= 256), "texture size");

    // Upload the texture to VRAM, wait for the process to complete and flush
    // any previously used texture from the GPU's internal cache.
    sendVramData(data, x, y, width, height);
    waitForGpuDmaDone();
    psx.GPU_GP0.* = gpuc.gp0FlushCache();

    return .{
        // The "Texture page" attribute is a 16-bit field telling the GPU details about the texture:
        // which 64x256 page it can be found in; its color depth, and how semitransparent pixels shall be blended.
        .page = gpuc.gp0Texpage(@truncate(x / 64), @truncate(y / 256), .avg, .bits_16),
        // The UV coordinates of the texture are its X/Y coordinates relative to
        // the top left corner of the texture page.
        .u = @truncate(x % 64),
        .v = @truncate(y % 256),
        .width = width,
        .height = height,
    };
}

fn waitForVSync() void {
    while (!psx.IRQ_STAT.vblank) {}

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

    psx.DMA_DPCR.gpu.enable = true;
    psx.DMA_CHCR(.gpu).* = @bitCast(@as(u32, 0));

    psx.GPU_GP1.* = gpuc.gp1DmaRequestMode(.cpu_to_gp0);
}

fn clip(x: i16) u16 {
    return @max(0, x);
}

const DmaPacket = struct { header: *gpuc.DmaTag, data: []u32 };

const dma_max_chunk_size = 16;
const gpa_chain_buffer_size = 1024 * 4;

var chain_1: [gpa_chain_buffer_size]u8 align(4) = undefined;
var chain_2: [gpa_chain_buffer_size]u8 align(4) = undefined;

fn allocateGp0Packet(al: std.mem.Allocator, num_commands: u8) DmaPacket {
    debug.assert(num_commands <= dma_max_chunk_size, "packet > 16 words");
    const buffer = al.alignedAlloc(u32, .@"4", num_commands + 1) catch {
        std.debug.panic("OOM on packet alloc", .{});
    };
    const header_ptr: *gpuc.DmaTag = @ptrCast(buffer.ptr);
    header_ptr.len = num_commands;
    return .{
        .header = header_ptr,
        .data = buffer[1..],
    };
}

fn sendGpuLinkedList(ptr: *u32) void {
    waitForGpuDmaDone();
    psx.DMA_MADR(.gpu).addr = @truncate(@intFromPtr(ptr));
    psx.DMA_CHCR(.gpu).* = psx.DmaChannelControl{
        .write = true,
        .mode = .linked_list,
        .enable = true,
    };
}

const texture_width = 32;
const texture_height = 32;

pub fn main() noreturn {
    logging.initSerialIo();

    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        setupGpu(.pal, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        setupGpu(.ntsc, screen_width, screen_height);
    }

    const texture = uploadTexture(
        &texture_data,
        @truncate(screen_width * 2),
        0,
        texture_width,
        texture_height,
    );

    var x: i16 = 0;
    var dx: i16 = 1;
    var y: i16 = 0;
    var dy: i16 = 1;

    var using_second_frame: bool = false;

    while (true) {
        const frame_x: u10 = if (using_second_frame) screen_width else 0;
        const frame_y = 0;

        using_second_frame = !using_second_frame;

        psx.GPU_GP1.* = gpuc.gp1FbOffset(frame_x, frame_y);

        var fba: std.heap.FixedBufferAllocator = if (using_second_frame) .init(&chain_1) else .init(&chain_2);
        const allocator = fba.allocator();

        const packet_1 = allocateGp0Packet(allocator, 4);
        packet_1.data[0] = gpuc.gp0SetPage(.{}, true, false);
        packet_1.data[1] = gpuc.gp0FbOffset1(frame_x, frame_y);
        packet_1.data[2] = gpuc.gp0FbOffset2(
            frame_x + screen_width - 1,
            frame_y + screen_height - 1,
        );
        packet_1.data[3] = gpuc.gp0FbOrigin(frame_x, frame_y);

        const packet_2 = allocateGp0Packet(allocator, 3);
        packet_1.header.next = @truncate(@intFromPtr(packet_2.header));
        packet_2.data[0] = gpuc.gp0VramFill(.{ .r = 64, .g = 64, .b = 64 });
        packet_2.data[1] = gpuc.gp0XY(frame_x, frame_y);
        packet_2.data[2] = gpuc.gp0WidthHeight(screen_width, screen_height);

        // Use the texture we uploaded to draw a sprite (textured rectangle).
        // Two separate commands have to be sent: a texture page command to
        // apply our page attribute and disable dithering, followed by the
        // actual rectangle drawing command. Any subsequent rectangle commands
        // will reuse the last page set, so it's not strictly necessary to send
        // a page command for each rectangle drawn.
        // NOTE: while not covered here, triangle and quad commands have an
        // inline page attribute and do not require a separate page setting
        // command (if not to toggle dithering, which the inline page field does
        // not affect).
        const packet_3 = allocateGp0Packet(allocator, 5);
        packet_2.header.next = @truncate(@intFromPtr(packet_3.header));
        packet_3.data[0] = gpuc.gp0SetPage(texture.page, true, false);
        packet_3.data[1] = gpuc.gp0Rectangle(
            .{ .r = 255, .g = 255, .b = 0 },
            true,
            false,
            true,
            .px_variable,
        );
        packet_3.data[2] = gpuc.gp0XY(clip(x), clip(y));
        packet_3.data[3] = gpuc.gp0UV(texture.u, texture.v);
        packet_3.data[4] = gpuc.gp0WidthHeight(32, 32);

        const packet_4 = allocateGp0Packet(allocator, 0);
        packet_3.header.next = @truncate(@intFromPtr(packet_4.header));

        packet_4.header.next = 0xFFFFFF;

        x = x +| dx;
        y = y +| dy;

        if (x <= 0 or x >= (screen_width - 32)) {
            dx = -dx;
        }
        if (y <= 0 or y >= (screen_height - 32)) {
            dy = -dy;
        }

        gpu.waitForGp0Ready();
        waitForVSync();

        sendGpuLinkedList(@ptrCast(packet_1.header));
    }
}

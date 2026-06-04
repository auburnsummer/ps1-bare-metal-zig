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
//  * This is a version of the previous example modified to use an indexed color
//  * texture instead of a raw one. The idea behind indexed color images is
//  * remarkably simple: by limiting the maximum number of unique colors in an
//  * image and storing their values separately, it is possible to reduce the size
//  * of the image data by replacing each pixel with an index to its color into the
//  * so-called CLUT (color lookup table) or palette.
//  *
//  * The PS1's GPU supports two indexed color formats: 4 bits per pixel (up to 16
//  * colors) and 8 bits per pixel (up to 256 colors). 4bpp and 8bpp textures are
//  * stored in VRAM "squished" horizontally, taking up half or a quarter of the
//  * size of an equivalent 16bpp texture respectively. Palettes are simply 16x1 or
//  * 256x1 16bpp images that can be placed anywhere in VRAM, with some minimal
//  * restrictions on alignment (their X coordinate must be a multiple of 16). This
//  * example shows how to upload a palette to VRAM alongside the image and set the
//  * appropriate GP0 attributes in order to let the GPU find and use it.
//  */

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
const texture_data align(4) = @embedFile("./generated/texture.bin").*;
const palette_data align(4) = @embedFile("./generated/palette.bin").*;

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

// We need to add a new entry to this structure to store the CLUT attribute,
// another 16-bit field which will contain the coordinates of our texture's
// palette within VRAM.
const TextureInfo = struct {
    u: u8 = 0,
    v: u8 = 0,
    width: u16 = 0,
    height: u16 = 0,
    page: gpuc.TexpageAttribute = .{},
    clut: gpuc.ClutAttribute,
};

fn uploadIndexedTexture(
    image: [*]const u8,
    palette: [*]const u8,
    image_x: u16,
    image_y: u16,
    palette_x: u16,
    palette_y: u16,
    width: u16,
    height: u16,
    color_depth: gpuc.TexpageColors,
) TextureInfo {
    debug.assert((width <= 256) and (height <= 256), "texture size");
    debug.assert(color_depth != .bits_16, "indexed cannot be 16bpp"); // use uploadTexture instead

    // Determine how large the palette is and by which factor the image is
    // squished horizontally in VRAM from the color depth.
    const num_colors: u16 = if (color_depth == .bits_8) 256 else 16;
    const width_divisor: u16 = if (color_depth == .bits_8) 2 else 4;

    // Make sure the palette is aligned correctly within VRAM and does not
    // exceed its bounds.
    debug.assert(palette_x % 16 == 0, "palette align");
    debug.assert(palette_x + num_colors <= 1024, "palette oob");

    // Upload the image and palette data separately, then flush any previously
    // used texture from the GPU's internal cache.

    // Upload the texture to VRAM, wait for the process to complete and flush
    // any previously used texture from the GPU's internal cache.
    std.log.info("image, {x}", .{@intFromPtr(image)});
    std.log.info("palette, {x}", .{@intFromPtr(palette)});
    sendVramData(image, image_x, image_y, width / width_divisor, height);
    waitForGpuDmaDone();
    sendVramData(palette, palette_x, palette_y, num_colors, 1);
    waitForGpuDmaDone();
    psx.GPU_GP0.* = gpuc.gp0FlushCache();

    return .{
        // Set the texture page and CLUT attributes to match the VRAM locations
        // of the image and palette respectively.
        .page = gpuc.gp0Texpage(@truncate(image_x / 64), @truncate(image_y / 256), .avg, color_depth),
        .clut = .{ .x = @truncate(palette_x / 16), .y = @truncate(palette_y) },
        // UV coordinate calculation is slightly more complex than before. The GPU
        // expects coordinates to be in texture pixels rather than VRAM pixels, so
        // the U coordinate has to be multiplied by the previously computed divider.
        .u = @truncate((image_x % 64) * width_divisor),
        .v = @truncate(image_y % 256),
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

    const texture = uploadIndexedTexture(
        &texture_data,
        &palette_data,
        @truncate(screen_width * 2),
        0,
        screen_width * 2,
        texture_height,
        texture_width,
        texture_height,
        .bits_4,
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

        // Draw the sprite, almost identically to how we did it in the previous
        // example. Notice how the CLUT attribute is being passed to the GPU.
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
        packet_3.data[3] = gpuc.gp0UvClut(texture.u, texture.v, texture.clut);
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

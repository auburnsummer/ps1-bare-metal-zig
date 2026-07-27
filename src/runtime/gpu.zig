const std = @import("std");
const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;
const debug = @import("./debug.zig");

const pcsx = @import("./pcsx.zig");

pub const dma_max_chunk_size = 16;
pub const gpa_chain_buffer_size = 1024 * 4;

pub fn waitForGp0Ready() void {
    while (!psx.GPU_STAT.cmd_ready) {}
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
    psx.DMA_DPCR.otc.enable = true;
    psx.DMA_CHCR(.gpu).* = @bitCast(@as(u32, 0));
    psx.DMA_CHCR(.otc).* = @bitCast(@as(u32, 0));

    psx.GPU_GP1.* = gpuc.gp1DmaRequestMode(.cpu_to_gp0);
}

pub const TextureInfo = struct {
    u: u8 = 0,
    v: u8 = 0,
    width: u16 = 0,
    height: u16 = 0,
    page: gpuc.TexpageAttribute = .{},
    clut: gpuc.ClutAttribute,
};

pub fn allocateGp0Packet(al: std.mem.Allocator, num_commands: u8) DmaPacket {
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

pub fn waitForGpuDmaDone() void {
    while (psx.DMA_CHCR(.gpu).enable) {}
}

pub fn waitForVSync() void {
    while (!psx.IRQ_STAT.vblank) {}

    psx.IRQ_STAT.vblank = false;
}

pub fn sendVramData(
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
    waitForGp0Ready();
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

pub fn uploadIndexedTexture(
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

pub fn sendGpuLinkedList(ptr: *u32) void {
    waitForGpuDmaDone();
    psx.DMA_MADR(.gpu).addr = @truncate(@intFromPtr(ptr));
    psx.DMA_CHCR(.gpu).* = psx.DmaChannelControl{
        .write = true,
        .mode = .linked_list,
        .enable = true,
    };
}

pub const DmaPacket = struct {
    header: *gpuc.DmaTag,
    data: []u32,
    pub fn init(arena: std.mem.Allocator, num_commands: u8) DmaPacket {
        debug.assert(num_commands <= dma_max_chunk_size, "packet > 16 words");
        const buffer = arena.alignedAlloc(u32, .@"4", num_commands + 1) catch {
            std.debug.panic("OOM on packet alloc", .{});
        };
        // First word in the buffer the header, and we'll set the length while we're here.
        const header_ptr: *gpuc.DmaTag = @ptrCast(buffer.ptr);
        header_ptr.len = num_commands;
        // The remainder of the buffer is the data.
        return .{
            .header = header_ptr,
            .data = buffer[1..],
        };
    }
    /// Create a terminator packet, which tells the DMA to finish.
    pub fn terminator(arena: std.mem.Allocator) DmaPacket {
        const pkt: DmaPacket = .init(arena, 0);
        pkt.header.next = 0xFFFFFF;
        return pkt;
    }
    pub fn setNext(self: *const DmaPacket, next_packet: *const DmaPacket) void {
        self.header.next = @truncate(@intFromPtr(next_packet.header));
    }
};

pub const DmaChain = struct {
    start: DmaPacket,
    curr: DmaPacket,
    arena: std.mem.Allocator,
    pub fn init(arena: std.mem.Allocator) DmaChain {
        const start: DmaPacket = .init(arena, 0);
        return .{
            .start = start,
            .curr = start,
            .arena = arena,
        };
    }
    pub fn newPacket(self: *DmaChain, num_commands: u8) DmaPacket {
        const new_packet: DmaPacket = .init(self.arena, num_commands);
        self.curr.setNext(&new_packet);
        self.curr = new_packet;
        return new_packet;
    }
    pub fn terminate(self: *DmaChain) void {
        const terminator: DmaPacket = .terminator(self.arena);
        self.curr.setNext(&terminator);
    }
};

/// A DmaTable is similar to a DmaChain, but it has an initial structure of empty
/// DMA tags that are linked to each other. New packets are spliced into the structure,
/// so these allows for 'layers' to place different packets in.
pub const DmaTable = struct {
    arena: std.mem.Allocator,
    anchors: []gpuc.DmaTag,
    pub fn init(arena: std.mem.Allocator, num_layers: u32) DmaTable {
        debug.assert(num_layers > 0, "empty ordering table");
        // assign memory to store the initial ordering table structure.
        const anchors = arena.alignedAlloc(gpuc.DmaTag, .@"4", num_layers) catch unreachable;
        var table: DmaTable = .{
            .arena = arena,
            .anchors = anchors,
        };
        std.log.info("ok {*}", .{anchors.ptr});
        // Ask DMA to write the initial ordering table to the memory we just allocated.
        table.clearOrderingTable();
        return table;
    }
    pub fn clearOrderingTable(self: *DmaTable) void {
        // // this is what it would be like manually:
        // var i = self.anchors.len - 1;
        // while (i > 0) {
        //     self.anchors[i].len = 0;
        //     self.anchors[i].next = @truncate(@intFromPtr(&self.anchors[i - 1]));
        //     i = i - 1;
        // }
        // // the terminator.
        // self.anchors[0].len = 0;
        // self.anchors[0].next = 0xFFFFFF;

        // Set up the OTC DMA channel to transfer a new empty ordering table to RAM.
        // The table is always reversed and generated "backwards" (the last item in
        // the table is the first one that will be written), so we must give DMA a
        // pointer to the end of the table rather than its beginning.
        psx.DMA_MADR(.otc).addr = @truncate(@intFromPtr(&self.anchors[self.anchors.len - 1]));
        psx.DMA_BCR(.otc).* = self.anchors.len;
        psx.DMA_CHCR(.otc).* = psx.DmaChannelControl{
            .enable = true,
            .reverse = true,
            .write = false,
            .mode = .burst,
            .trigger = true,
        };

        // Wait for DMA to finish generating the table.
        while (psx.DMA_CHCR(.otc).enable) {}
    }
    pub fn newPacket(self: *DmaTable, num_commands: u8, layer: u32) DmaPacket {
        // make a new packet pointing to wherever the old packet pointed to.
        const new_packet: DmaPacket = .init(self.arena, num_commands);
        new_packet.header.next = self.anchors[layer].next;
        // old packet points to the new packet.
        self.anchors[layer].next = @truncate(@intFromPtr(new_packet.header));
        return new_packet;
    }
    // NB: there's no more terminate() function. The ordering table already inserted
    // a terminator packet.
};

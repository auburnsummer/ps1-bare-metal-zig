const std = @import("std");
const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;
const debug = @import("./debug.zig");

const dma_max_chunk_size = 16;
const gpa_chain_buffer_size = 1024 * 4;

pub fn waitForGp0Ready() void {
    while (!psx.GPU_STAT.cmd_ready) {}
}

pub const TextureInfo = struct {
    u: u8 = 0,
    v: u8 = 0,
    width: u16 = 0,
    height: u16 = 0,
    page: gpuc.TexpageAttribute = .{},
    clut: gpuc.ClutAttribute,
};

pub const DmaPacket = struct { header: *gpuc.DmaTag, data: []u32 };

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

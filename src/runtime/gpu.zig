const std = @import("std");
const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;
const debug = @import("./debug.zig");

const dma_max_chunk_size = 16;
const gpa_chain_buffer_size = 1024 * 4;

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
    psx.DMA_CHCR(.gpu).* = @bitCast(@as(u32, 0));

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

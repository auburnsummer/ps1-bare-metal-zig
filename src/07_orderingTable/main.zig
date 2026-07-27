const std = @import("std");
const gpu = @import("runtime").gpu;
const logging = @import("runtime").logging;
const gpuc = @import("ps1").gpu_cmd;
const psx = @import("ps1").registers;
const pcsx = @import("runtime").pcsx;

const screen_width = 320;
const screen_height = 240;
const gpa_chain_buffer_size = 1024 * 4;

var chain_1: [gpa_chain_buffer_size]u8 align(4) = undefined;
var chain_2: [gpa_chain_buffer_size]u8 align(4) = undefined;

pub fn main() noreturn {
    logging.initSerialIo();

    if (psx.GPU_STAT.video_mode == .pal) {
        std.log.info("Using PAL mode", .{});
        gpu.setupGpu(.pal, screen_width, screen_height);
    } else {
        std.log.info("Using NTSC mode", .{});
        gpu.setupGpu(.ntsc, screen_width, screen_height);
    }

    var using_second_frame: bool = false;

    var c: u8 = 0;

    var frame_count: usize = 0;
    while (true) {
        const frame_x: u10 = if (using_second_frame) screen_width else 0;
        const frame_y = 0;

        psx.GPU_GP1.* = gpuc.gp1FbOffset(frame_x, frame_y);

        var fba: std.heap.FixedBufferAllocator = if (using_second_frame) .init(&chain_1) else .init(&chain_2);
        const allocator = fba.allocator();
        using_second_frame = !using_second_frame;

        var table: gpu.DmaTable = .init(allocator, 32);

        // Draw 16 stacked squares, animating their Z indices. The packets are
        // always allocated in the same order (top left to bottom right square),
        // but the table will reorder them as they are sent to the GPU.
        frame_count = frame_count + 1;
        var x: u16 = 16;
        var y: u16 = 24;

        const front_square_index = (frame_count / 10) % 16;
        for (0..15) |_i| {
            const i: u8 = @intCast(_i);
            const color: gpuc.RgbColor = .{ .r = i * 15, .g = i * 15, .b = 0 };
            const z_index = if (i < front_square_index) front_square_index - 1 else i - front_square_index;
            const packet = table.newPacket(3, z_index);
            packet.data[0] = gpuc.gp0Rectangle(color, false, false, false, .px_variable);
            packet.data[1] = gpuc.gp0XY(x, y);
            packet.data[2] = gpuc.gp0WidthHeight(32, 32);

            x += 16;
            y += 10;
        }

        // Place the framebuffer offset and screen clearing commands last, as
        // the "furthest away" items in the table. Since the ordering table is
        // reversed (see the allocateGP0Packet() note), this ensures they'll be
        // executed first.
        var packet = table.newPacket(4, 31);
        packet.data[0] = gpuc.gp0SetPage(.{}, true, false);
        packet.data[1] = gpuc.gp0FbOffset1(frame_x, frame_y);
        packet.data[2] = gpuc.gp0FbOffset2(
            frame_x + screen_width - 1,
            frame_y + screen_height - 1,
        );
        packet.data[3] = gpuc.gp0FbOrigin(frame_x, frame_y);

        packet = table.newPacket(3, 30);
        packet.data[0] = gpuc.gp0VramFill(.{ .r = 64, .g = 64, .b = 64 });
        packet.data[1] = gpuc.gp0XY(frame_x, frame_y);
        packet.data[2] = gpuc.gp0WidthHeight(screen_width, screen_height);

        // big ol triangle in the background too
        packet = table.newPacket(6, 29);
        packet.data[0] = gpuc.gp0ShadedTriangle(.{ .r = 255, .g = 0, .b = 0 }, true, false, false);
        packet.data[1] = gpuc.gp0XY(screen_width / 2, 32);
        packet.data[2] = gpuc.gp0Rgb(.{ .r = c, .g = 255, .b = 255 - c });
        packet.data[3] = gpuc.gp0XY(32, screen_height - 32);
        packet.data[4] = gpuc.gp0Rgb(.{ .r = 255 - c, .g = 0, .b = c });
        packet.data[5] = gpuc.gp0XY(screen_width - 32, screen_height - 32);

        gpu.waitForGp0Ready();
        gpu.waitForVSync();

        gpu.sendGpuLinkedList(@ptrCast(&table.anchors[table.anchors.len - 1]));

        if (c == 255) {
            c = 0;
        }
        c = c + 1;
    }
}

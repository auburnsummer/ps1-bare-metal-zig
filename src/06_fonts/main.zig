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
// We saw how to load a single texture and display it in the last two examples.
// Textures, however, are not always simple images displayed in their entirety:
// sometimes they hold more than one image (e.g. all frames of a character's
// animation in a 2D game) but are "cropped out" on the fly during rendering to
// only draw a single frame at a time. These textures are known as spritesheets
// and the PS1's GPU fully supports them, as it allows for arbitrary UV
// coordinates to be used.
//
// This example is going to show how to implement a simple font system for text
// rendering, since that's one of the most common use cases for spritesheets. We
// are going to load a single texture containing all our font's characters, as
// having hundreds of tiny textures for each character would be extremely
// inefficient, and then use a lookup table to obtain the UV coordinates, width
// and height of each character in a string.
//
// NOTE: in order to make the code easier to read, GPU-related functions from
// previous examples are now from the runtime/gpu.zig module.
//
const std = @import("std");
const gpu = @import("runtime").gpu;
const logging = @import("runtime").logging;
const gpuc = @import("ps1").gpu_cmd;
const psx = @import("ps1").registers;

// In order to pick sprites (characters) out of our spritesheet, we need a table
// listing all of them (in ASCII order in this case) with their UV coordinates
// within the sheet as well as their dimensions. In this example we're going to
// hardcode the table, however in an actual game you may want to store this data
// in the same file as the image and palette data.
pub const SpriteInfo = struct {
    x: u8,
    y: u8,
    width: u8,
    height: u8,
};

const font_sprites: [95]SpriteInfo = .{
    .{ .x = 6, .y = 0, .width = 2, .height = 9 }, // !
    .{ .x = 12, .y = 0, .width = 4, .height = 9 }, // "
    .{ .x = 18, .y = 0, .width = 6, .height = 9 }, // #
    .{ .x = 24, .y = 0, .width = 6, .height = 9 }, // $
    .{ .x = 30, .y = 0, .width = 6, .height = 9 }, // %
    .{ .x = 36, .y = 0, .width = 6, .height = 9 }, // &
    .{ .x = 42, .y = 0, .width = 2, .height = 9 }, // '
    .{ .x = 48, .y = 0, .width = 3, .height = 9 }, // (
    .{ .x = 54, .y = 0, .width = 3, .height = 9 }, // )
    .{ .x = 60, .y = 0, .width = 4, .height = 9 }, // *
    .{ .x = 66, .y = 0, .width = 6, .height = 9 }, // +
    .{ .x = 72, .y = 0, .width = 3, .height = 9 }, // ,
    .{ .x = 78, .y = 0, .width = 6, .height = 9 }, // -
    .{ .x = 84, .y = 0, .width = 2, .height = 9 }, // .
    .{ .x = 90, .y = 0, .width = 6, .height = 9 }, // /
    .{ .x = 0, .y = 9, .width = 6, .height = 9 }, // 0
    .{ .x = 6, .y = 9, .width = 6, .height = 9 }, // 1
    .{ .x = 12, .y = 9, .width = 6, .height = 9 }, // 2
    .{ .x = 18, .y = 9, .width = 6, .height = 9 }, // 3
    .{ .x = 24, .y = 9, .width = 6, .height = 9 }, // 4
    .{ .x = 30, .y = 9, .width = 6, .height = 9 }, // 5
    .{ .x = 36, .y = 9, .width = 6, .height = 9 }, // 6
    .{ .x = 42, .y = 9, .width = 6, .height = 9 }, // 7
    .{ .x = 48, .y = 9, .width = 6, .height = 9 }, // 8
    .{ .x = 54, .y = 9, .width = 6, .height = 9 }, // 9
    .{ .x = 60, .y = 9, .width = 2, .height = 9 }, // :
    .{ .x = 66, .y = 9, .width = 3, .height = 9 }, // ;
    .{ .x = 72, .y = 9, .width = 6, .height = 9 }, // <
    .{ .x = 78, .y = 9, .width = 6, .height = 9 }, // =
    .{ .x = 84, .y = 9, .width = 6, .height = 9 }, // >
    .{ .x = 90, .y = 9, .width = 6, .height = 9 }, // ?
    .{ .x = 0, .y = 18, .width = 6, .height = 9 }, // @
    .{ .x = 6, .y = 18, .width = 6, .height = 9 }, // A
    .{ .x = 12, .y = 18, .width = 6, .height = 9 }, // B
    .{ .x = 18, .y = 18, .width = 6, .height = 9 }, // C
    .{ .x = 24, .y = 18, .width = 6, .height = 9 }, // D
    .{ .x = 30, .y = 18, .width = 6, .height = 9 }, // E
    .{ .x = 36, .y = 18, .width = 6, .height = 9 }, // F
    .{ .x = 42, .y = 18, .width = 6, .height = 9 }, // G
    .{ .x = 48, .y = 18, .width = 6, .height = 9 }, // H
    .{ .x = 54, .y = 18, .width = 4, .height = 9 }, // I
    .{ .x = 60, .y = 18, .width = 5, .height = 9 }, // J
    .{ .x = 66, .y = 18, .width = 6, .height = 9 }, // K
    .{ .x = 72, .y = 18, .width = 6, .height = 9 }, // L
    .{ .x = 78, .y = 18, .width = 6, .height = 9 }, // M
    .{ .x = 84, .y = 18, .width = 6, .height = 9 }, // N
    .{ .x = 90, .y = 18, .width = 6, .height = 9 }, // O
    .{ .x = 0, .y = 27, .width = 6, .height = 9 }, // P
    .{ .x = 6, .y = 27, .width = 6, .height = 9 }, // Q
    .{ .x = 12, .y = 27, .width = 6, .height = 9 }, // R
    .{ .x = 18, .y = 27, .width = 6, .height = 9 }, // S
    .{ .x = 24, .y = 27, .width = 6, .height = 9 }, // T
    .{ .x = 30, .y = 27, .width = 6, .height = 9 }, // U
    .{ .x = 36, .y = 27, .width = 6, .height = 9 }, // V
    .{ .x = 42, .y = 27, .width = 6, .height = 9 }, // W
    .{ .x = 48, .y = 27, .width = 6, .height = 9 }, // X
    .{ .x = 54, .y = 27, .width = 6, .height = 9 }, // Y
    .{ .x = 60, .y = 27, .width = 6, .height = 9 }, // Z
    .{ .x = 66, .y = 27, .width = 3, .height = 9 }, // [
    .{ .x = 72, .y = 27, .width = 6, .height = 9 }, // Backslash
    .{ .x = 78, .y = 27, .width = 3, .height = 9 }, // ]
    .{ .x = 84, .y = 27, .width = 4, .height = 9 }, // ^
    .{ .x = 90, .y = 27, .width = 6, .height = 9 }, // _
    .{ .x = 0, .y = 36, .width = 3, .height = 9 }, // `
    .{ .x = 6, .y = 36, .width = 6, .height = 9 }, // a
    .{ .x = 12, .y = 36, .width = 6, .height = 9 }, // b
    .{ .x = 18, .y = 36, .width = 6, .height = 9 }, // c
    .{ .x = 24, .y = 36, .width = 6, .height = 9 }, // d
    .{ .x = 30, .y = 36, .width = 6, .height = 9 }, // e
    .{ .x = 36, .y = 36, .width = 5, .height = 9 }, // f
    .{ .x = 42, .y = 36, .width = 6, .height = 9 }, // g
    .{ .x = 48, .y = 36, .width = 5, .height = 9 }, // h
    .{ .x = 54, .y = 36, .width = 2, .height = 9 }, // i
    .{ .x = 60, .y = 36, .width = 4, .height = 9 }, // j
    .{ .x = 66, .y = 36, .width = 5, .height = 9 }, // k
    .{ .x = 72, .y = 36, .width = 2, .height = 9 }, // l
    .{ .x = 78, .y = 36, .width = 6, .height = 9 }, // m
    .{ .x = 84, .y = 36, .width = 5, .height = 9 }, // n
    .{ .x = 90, .y = 36, .width = 6, .height = 9 }, // o
    .{ .x = 0, .y = 45, .width = 6, .height = 9 }, // p
    .{ .x = 6, .y = 45, .width = 6, .height = 9 }, // q
    .{ .x = 12, .y = 45, .width = 6, .height = 9 }, // r
    .{ .x = 18, .y = 45, .width = 6, .height = 9 }, // s
    .{ .x = 24, .y = 45, .width = 5, .height = 9 }, // t
    .{ .x = 30, .y = 45, .width = 5, .height = 9 }, // u
    .{ .x = 36, .y = 45, .width = 6, .height = 9 }, // v
    .{ .x = 42, .y = 45, .width = 6, .height = 9 }, // w
    .{ .x = 48, .y = 45, .width = 6, .height = 9 }, // x
    .{ .x = 54, .y = 45, .width = 6, .height = 9 }, // y
    .{ .x = 60, .y = 45, .width = 5, .height = 9 }, // z
    .{ .x = 66, .y = 45, .width = 4, .height = 9 }, // {
    .{ .x = 72, .y = 45, .width = 2, .height = 9 }, // |
    .{ .x = 78, .y = 45, .width = 4, .height = 9 }, // }
    .{ .x = 84, .y = 45, .width = 6, .height = 9 }, // ~
    .{ .x = 90, .y = 45, .width = 6, .height = 9 }, // Invalid character
};

const font_first_table_char: u8 = '!';
const font_space_width = 4;
const font_tab_width = 32;
const font_line_height = 10;

const screen_width = 320;
const screen_height = 240;
const font_width = 96;
const font_height = 56;
const font_color_depth: gpuc.TexpageColors = .bits_4;

const texture_data align(4) = @embedFile("./generated/texture.bin").*;
const palette_data align(4) = @embedFile("./generated/palette.bin").*;

pub fn printString(
    chain: *gpu.DmaChain,
    font: gpu.TextureInfo,
    x: u16,
    y: u16,
    s: []const u8,
) void {
    var current_x = x;
    var current_y = y;

    // Start by sending a texture page command to tell the GPU to use the font's
    // spritesheet. The page setting persists when drawing rectangles, so
    // sending it here just once is enough.
    var packet = chain.newPacket(1);
    packet.data[0] = gpuc.gp0SetPage(font.page, false, false);

    for (s) |ch| {
        std.log.info("{c}", .{ch});
        // Check if the character is "special" and shall be handled without
        // drawing any sprite, or if it's invalid and should be rendered as a
        // box with a question mark (character code 127).
        var char = ch;
        switch (ch) {
            '\t' => {
                current_x += font_tab_width - 1;
                current_x -= current_x % font_tab_width;
                continue;
            },
            '\n' => {
                current_x = x;
                current_y += font_line_height;
                continue;
            },
            ' ' => {
                current_x += font_space_width;
                continue;
            },
            '\x80'...'\xff' => {
                char = '\x7f';
                continue;
            },
            else => {},
        }
        // If the character was not a tab, newline or space, fetch its
        // respective entry from the sprite coordinate table.
        const sprite = font_sprites[char - font_first_table_char];

        // Draw the character, summing the UV coordinates of the spritesheet in
        // VRAM to those of the sprite itself within the sheet. Enable blending
        // to make sure any semitransparent pixels in the font get rendered
        // correctly.
        packet = chain.newPacket(4);
        packet.data[0] = gpuc.gp0Rectangle(.{ .r = 0, .g = 0, .b = 0 }, true, true, true, .px_variable);
        packet.data[1] = gpuc.gp0XY(current_x, current_y);
        packet.data[2] = gpuc.gp0UvClut(font.u + sprite.x, font.v + sprite.y, font.clut);
        packet.data[3] = gpuc.gp0XY(sprite.width, sprite.height);

        current_x += sprite.width;
    }
}

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

    const texture = gpu.uploadIndexedTexture(
        &texture_data,
        &palette_data,
        @truncate(screen_width * 2),
        0,
        screen_width * 2,
        font_height,
        font_width,
        font_height,
        .bits_4,
    );

    var using_second_frame: bool = false;

    var counter: usize = 0;

    while (true) {
        const frame_x: u10 = if (using_second_frame) screen_width else 0;
        const frame_y = 0;

        using_second_frame = !using_second_frame;

        psx.GPU_GP1.* = gpuc.gp1FbOffset(frame_x, frame_y);

        var fba: std.heap.FixedBufferAllocator = if (using_second_frame) .init(&chain_1) else .init(&chain_2);
        const allocator = fba.allocator();

        var chain: gpu.DmaChain = .init(allocator);

        var packet: gpu.DmaPacket = chain.newPacket(4);
        packet.data[0] = gpuc.gp0SetPage(.{}, true, false);
        packet.data[1] = gpuc.gp0FbOffset1(frame_x, frame_y);
        packet.data[2] = gpuc.gp0FbOffset2(
            frame_x + screen_width - 1,
            frame_y + screen_height - 1,
        );
        packet.data[3] = gpuc.gp0FbOrigin(frame_x, frame_y);

        packet = chain.newPacket(3);
        packet.data[0] = gpuc.gp0VramFill(.{ .r = 64, .g = 64, .b = 64 });
        packet.data[1] = gpuc.gp0XY(frame_x, frame_y);
        packet.data[2] = gpuc.gp0WidthHeight(screen_width, screen_height);

        packet = chain.newPacket(6);
        packet.data[0] = gpuc.gp0ShadedTriangle(.{ .r = 255, .g = 0, .b = 0 }, true, false, false);
        packet.data[1] = gpuc.gp0XY(screen_width / 2, 32);
        packet.data[2] = gpuc.gp0Rgb(.{ .r = 0, .g = 255, .b = 0 });
        packet.data[3] = gpuc.gp0XY(32, screen_height - 32);
        packet.data[4] = gpuc.gp0Rgb(.{ .r = 0, .g = 0, .b = 255 });
        packet.data[5] = gpuc.gp0XY(screen_width - 32, screen_height - 32);

        printString(&chain, texture, 5, 5, "Hello World!");

        var buffer: [50]u8 = undefined;
        const message = std.fmt.bufPrint(buffer[0..], "Current frame: {d}", .{counter}) catch unreachable;

        printString(&chain, texture, 5, 15, message);

        chain.terminate();

        gpu.waitForGp0Ready();
        gpu.waitForVSync();

        gpu.sendGpuLinkedList(@ptrCast(chain.start.header));

        counter = counter + 1;
    }
}

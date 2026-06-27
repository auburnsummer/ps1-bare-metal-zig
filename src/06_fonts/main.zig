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

const DmaChain = struct { first: gpu.DmaPacket, curr: gpu.DmaPacket };

pub fn printString(
    arena: std.mem.Allocator,
    chain: *DmaChain,
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
    var prev = gpu.allocateGp0Packet(arena, 1);
    prev.data[0] = gpuc.gp0SetPage(font.page, false, false);

    chain.curr.header.next = @truncate(@intFromPtr(prev.header));

    chain.curr = prev;

    for (s) |ch| {
        // Check if the character is "special" and shall be handled without
        // drawing any sprite, or if it's invalid and should be rendered as a
        // box with a question mark (character code 127).
        var char = ch;
        switch (ch) {
            '\t' => {
                current_x += font_tab_width - 1;
                current_x -= current_x % font_tab_width;
            },
            '\n' => {
                current_x = x;
                current_y += font_line_height;
            },
            ' ' => {
                current_x += font_space_width;
            },
            '\x80'...'\xff' => {
                char = '\x7f';
            },
            else => {
                continue;
            },
        }
        // If the character was not a tab, newline or space, fetch its
        // respective entry from the sprite coordinate table.
        const sprite = font_sprites[char - font_first_table_char];

        // Draw the character, summing the UV coordinates of the spritesheet in
        // VRAM to those of the sprite itself within the sheet. Enable blending
        // to make sure any semitransparent pixels in the font get rendered
        // correctly.
        const packet = gpu.allocateGp0Packet(arena, 4);
        chain.curr.header.next = @truncate(@intFromPtr(packet.header));
        packet.data[0] = gpuc.gp0Rectangle(.{ .r = 0, .g = 0, .b = 0 }, true, true, true, .px_variable);
        packet.data[1] = gpuc.gp0XY(current_x, current_y);
        packet.data[2] = gpuc.gp0UvClut(font.u + sprite.x, font.v + sprite.y, font.clut);
        packet.data[3] = gpuc.gp0XY(sprite.width, sprite.height);

        current_x += sprite.width;

        chain.curr = packet;
    }
}

var buf: [gpu.gpa_chain_buffer_size]u8 align(4) = undefined;

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

    while (true) {
        var fba: std.heap.FixedBufferAllocator = .init(&buf);
        const first_packet = gpu.allocateGp0Packet(fba.allocator(), 0);
        var chain = DmaChain{ .first = first_packet, .curr = first_packet };
        printString(fba.allocator(), &chain, texture, 20, 20, "Hello World!");

        gpu.sendGpuLinkedList(@ptrCast(chain.first.header));
    }
}

const std = @import("std");

pub const DumbFont16 = struct {
    glyphs: []const Glyph,

    pub const signature = [_]u8{ 0xff, 0x55, 0x6e, 0x69, 0x73, 0x69, 0x67, 0x00, 0x0a, 0x0d, 0x0a, 0x13, 0x69, 0x6f, 0x2e, 0x6c, 0x61, 0x73, 0x73, 0x69, 0x2e, 0x64, 0x75, 0x6d, 0x62, 0x66, 0x6f, 0x6e, 0x74, 0x31, 0x36, 0x00 };

    pub const Glyph = packed struct {
        pixels: [16]u16, // 32 bits, 2 bytes per row
    };

    comptime {
        if (@sizeOf(Glyph) != 32) {
            @compileError("DumbFont16 Glyph should be 32 bytes in size");
        }
    }

    pub fn fromConstMem(mem: []const u8) !DumbFont16 {
        if (std.mem.eql(u8, mem[0..signature.len], signature[0..])) {
            var glyphMem = mem.len - signature.len;

            var numGlyphs = glyphMem / @sizeOf(Glyph);
            var glyphs = @ptrCast([*]const Glyph, @alignCast(@alignOf(Glyph), mem[signature.len..(numGlyphs * @sizeOf(Glyph))]));

            return DumbFont16{ .glyphs = glyphs[0..numGlyphs] };
        }

        return error.WrongSignature;
    }
};

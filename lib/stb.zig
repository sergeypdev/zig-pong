const std = @import("std");

pub const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub const Font = struct {
    allocator: *std.mem.Allocator,
    buffer: []const u8,
    fontInfo: c.stbtt_fontinfo,

    pub const Point = struct {
        x: i32,
        y: i32,
    };

    pub const Bitmap = struct {
        allocator: *std.mem.Allocator,
        width: usize,
        height: usize,
        data: []u8,
        charData: c.stbtt_packedchar,

        pub fn deinit(self: *Bitmap) void {
            self.allocator.free(self.data);
        }

        pub fn getCharQuad(index: i32, x: *f32, y: *f32) c.stbtt_aligned_quad {
            var quad: c.stbtt_aligned_quad = undefined;
            c.stbtt_GetPackedQuad(self.charData, @intToFloat(f32, self.width), @intToFloat(f32, self.height), index, x, y, &quad, 1);

            return quad;
        }
    };

    pub const BoundingBox = struct {
        topLeft: Point,
        bottomRight: Point,

        pub fn width(self: *const BoundingBox) i32 {
            return self.topRight.x - self.topLeft.x;
        }

        pub fn height(self: *const BoundingBox) i32 {
            return self.bottomRight.y - self.topLeft.y;
        }
    };

    pub fn fromBuffer(allocator: *std.mem.Allocator, src_buffer: []const u8) !Font {
        var buffer = try allocator.alloc(u8, src_buffer.len);
        errdefer allocator.free(buffer);

        std.mem.copy(u8, buffer, src_buffer);

        var c_buffer = @ptrCast([*c]const u8, buffer);
        var offset = c.stbtt_GetFontOffsetForIndex(c_buffer, 0);

        if (offset < 0) {
            return error.InvalidFontIndex;
        }

        var info: c.stbtt_fontinfo = undefined;
        if (c.stbtt_InitFont(&info, c_buffer, offset) == 0) {
            return error.FailedToInitFont;
        }

        return Font{ .allocator = allocator, .buffer = buffer, .fontInfo = info };
    }

    pub fn deinit(self: *Font) void {
        self.allocator.free(self.buffer);
        self.fontInfo = undefined;
        self.allocator = undefined;
        self.buffer = undefined;
    }

    pub fn scaleForPixelHeight(self: *const Font, height: f32) f32 {
        return c.stbtt_ScaleForPixelHeight(self.fontInfo, height);
    }

    pub fn getGlyphIndex(self: *const Font, codepoint: u16) !u16 {
        var result = c.stbtt_FindGlyphIndex(self.fontInfo, @intCast(c_int, codepoint));

        if (result == 0) {
            return error.GlyphNotFound;
        }

        return @intCast(u16, result);
    }

    pub fn getGlyphBoundingBox(self: *const Font, glyphIndex: u16, pxSize: f32) BoundingBox {
        var result: BoundingBox = undefined;
        c.stbtt_GetGlyphBitmapBox(
            self.fontInfo,
            glyphIndex,
            0,
            self.scaleForPixelHeight(pxSize),
            &result.topLeft.x,
            &result.topLeft.y,
            &result.bottomRight.x,
            &result.bottomRight.y,
        );

        return result;
    }

    pub fn packFontBitmap(self: *const Font, size: f32, firstChar: i32, numChars: i32) !Bitmap {
        const width = 1024;
        const height = 1024;

        var pixels = try self.allocator.alloc(u8, width * height);
        std.debug.warn("Pixels pointer {}\n", .{@ptrToInt(pixels.ptr)});
        errdefer self.allocator.free(pixels);

        var c_pixels = @ptrCast([*c]u8, pixels);

        var packCtx: c.stbtt_pack_context = undefined;
        if (c.stbtt_PackBegin(&packCtx, c_pixels, width, height, width, 1, null) == 0) {
            return error.PackBegin;
        }
        @breakpoint();

        var charData: c.stbtt_packedchar = undefined;

        if (c.stbtt_PackFontRange(&packCtx, self.fontInfo.data, 0, size, firstChar, numChars, &charData) == 0) {
            return error.PackFontRange;
        }

        c.stbtt_PackEnd(&packCtx);

        return Bitmap{
            .allocator = self.allocator,
            .data = pixels,
            .width = width,
            .height = height,
            .charData = charData,
        };
    }
};

const std = @import("std");
const builtin = std.builtin;

// Format reference: http://grub.gibibit.com/New_font_format

pub const PF2Font = struct {
    name: []const u8,
    family: []const u8,
    weight: Weight,
    slant: Slant,
    pointSize: u16,
    maxWidth: u16,
    maxHeight: u16,
    ascent: u16,
    descent: u16,
    chix: []const u8,
    dataOffset: u32,
    data: []const u8,

    pub const Weight = enum {
        bold,
        normal,
    };

    pub const Slant = enum {
        italic,
        normal,
    };

    pub const signature = "PFF2";

    pub const CharIndexEntry = packed struct {
        codepoint: u32,
        flags: u8,
        offset: u32,
    };

    pub const RawDataEntry = packed struct {
        width: u16,
        height: u16,
        xOffset: i16,
        yOffset: i16,
        deviceWidth: i16,
    };

    pub const CharEntry = struct {
        width: u16,
        height: u16,
        xOffset: i16,
        yOffset: i16,
        deviceWidth: i16,
        pixels: []const u8,
    };

    const Section = enum {
        file,
        name,
        family,
        weight,
        slant,
        pointSize,
        maxWidth,
        maxHeight,
        ascent,
        descent,
        chix,
        data,
    };

    fn parseSection(str: []const u8) !Section {
        std.debug.assert(str.len == 4);

        if (std.mem.eql(u8, str, "FILE")) {
            return .file;
        } else if (std.mem.eql(u8, str, "NAME")) {
            return .name;
        } else if (std.mem.eql(u8, str, "FAMI")) {
            return .family;
        } else if (std.mem.eql(u8, str, "WEIG")) {
            return .weight;
        } else if (std.mem.eql(u8, str, "SLAN")) {
            return .slant;
        } else if (std.mem.eql(u8, str, "PTSZ")) {
            return .pointSize;
        } else if (std.mem.eql(u8, str, "MAXW")) {
            return .maxWidth;
        } else if (std.mem.eql(u8, str, "MAXH")) {
            return .maxHeight;
        } else if (std.mem.eql(u8, str, "ASCE")) {
            return .ascent;
        } else if (std.mem.eql(u8, str, "DESC")) {
            return .descent;
        } else if (std.mem.eql(u8, str, "CHIX")) {
            return .chix;
        } else if (std.mem.eql(u8, str, "DATA")) {
            return .data;
        }

        return error.InvalidSection;
    }

    pub fn fromConstMem(mem: []const u8) !PF2Font {
        var offset: usize = 0;

        var font: PF2Font = undefined;

        while (offset < mem.len) {
            var sectionType = try parseSection(mem[offset .. offset + 4]);
            offset += 4;
            var sectionLen = std.mem.readIntSlice(u32, mem[offset..], .Big);
            offset += 4;

            var section: []const u8 = undefined;

            var sectionStartOffset = offset;

            if (sectionType == .data) {
                section = mem[offset..mem.len];
                offset = mem.len;
            } else {
                section = mem[offset .. offset + sectionLen];
                offset += sectionLen;
            }

            switch (sectionType) {
                .file => {
                    if (!std.mem.eql(u8, section, signature)) {
                        return error.WrongSignature;
                    }
                },
                .name => font.name = section,
                .family => font.family = section,
                .weight => switch (section[0]) {
                    'b' => font.weight = .bold,
                    'n' => font.weight = .normal,
                    else => return error.WrongWeight,
                },
                .slant => switch (section[0]) {
                    'i' => font.slant = .italic,
                    'n' => font.slant = .normal,
                    else => return error.WrongSlant,
                },
                .pointSize => font.pointSize = std.mem.readIntSlice(u16, section, .Big),
                .maxWidth => font.maxWidth = std.mem.readIntSlice(u16, section, .Big),
                .maxHeight => font.maxHeight = std.mem.readIntSlice(u16, section, .Big),
                .ascent => font.ascent = std.mem.readIntSlice(u16, section, .Big),
                .descent => font.descent = std.mem.readIntSlice(u16, section, .Big),
                .chix => font.chix = section,
                .data => {
                    font.data = section;
                    font.dataOffset = @intCast(u32, sectionStartOffset);
                },
            }
        }

        return font;
    }

    pub fn findCharIndex(self: *const PF2Font, needle: u32) ?CharIndexEntry {
        var i: usize = 0;
        while (i < self.chix.len) : (i += 9) {
            var codepoint = std.mem.readIntSlice(u32, self.chix[i..], .Big);
            var result: CharIndexEntry = undefined;
            result.codepoint = codepoint;
            result.flags = self.chix[i + 4];
            result.offset = std.mem.readIntSlice(u32, self.chix[i + 5 ..], .Big) - self.dataOffset;

            if (needle == codepoint) {
                return result;
            }
        }

        return null;
    }

    pub fn getChar(self: *const PF2Font, needle: u32) ?CharEntry {
        var chix = self.findCharIndex(needle) orelse return null;

        var data = self.data[chix.offset..];

        var width = std.mem.readIntSlice(u16, data, .Big);
        var height = std.mem.readIntSlice(u16, data[2..], .Big);

        var entry = CharEntry{
            .width = width,
            .height = height,
            .xOffset = std.mem.readIntSlice(i16, data[4..], .Big),
            .yOffset = std.mem.readIntSlice(i16, data[6..], .Big),
            .deviceWidth = std.mem.readIntSlice(i16, data[8..], .Big),
            .pixels = @ptrCast([*]const u8, self.data[chix.offset + @sizeOf(RawDataEntry) ..])[0 .. (width * height + 7) / 8],
        };

        return entry;
    }
};

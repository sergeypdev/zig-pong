const std = @import("std");
const sdl = @import("sdl.zig");

pub const Audio = struct {
    device: ?sdl.AudioDevice,

    pub fn init() Audio {
        return Audio{ .device = null };
    }

    pub fn open(self: *Audio) !void {
        self.device = try sdl.AudioDevice.init(
            null,
            false,
            std.mem.zeroInit(sdl.SDL_AudioSpec, .{
                .freq = 48000,
                .format = sdl.AUDIO_S16SYS,
                .channels = 2,
                .samples = 4096, // A little more than one sec
                .callback = struct {
                    export fn callback(userdata: ?*c_void, data: [*c]u8, len: i32) void {
                        var audio = @ptrCast(*Audio, @alignCast(@alignOf(*Audio), userdata));
                        var buffer = data[0..@intCast(u32, len)];

                        audio.callback(buffer);
                    }
                }.callback,
                .userdata = @ptrCast(?*c_void, self),
            }),
            0,
        );
    }

    pub fn deinit(self: *Audio) void {
        if (self.device) |device| {
            device.deinit();
        }
    }

    pub fn play(self: *Audio) void {
        if (self.device) |device| {
            device.play();
        }
    }

    pub fn pause(self: *Audio) void {
        if (self.device) |device| {
            device.pause();
        }
    }

    fn callback(self: *Audio, buffer: []u8) void {
        std.debug.assert(self.device != null);
        std.debug.warn("Audio Callback {}\n", .{buffer.len});
        std.mem.set(u8, buffer, 0);
    }
};

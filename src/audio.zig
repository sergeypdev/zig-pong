const std = @import("std");
const sdl = @import("sdl.zig");

pub const Audio = struct {
    device: ?sdl.AudioDevice,
    lastCallbackTime: u64,
    // We'll allow up to 16 sounds to be played simultaneously
    sounds: [16]?Sound,
    next_sound_index: u8,
    cursor: u64, // current play cursor in the "global" timeline
    buffer_copy: [2 * 512]i16 = [_]i16{0} ** (2 * 512),

    pub const Sound = struct {
        offset: u64,
        data: []const i16,
        volume: u7,
    };

    pub fn init() Audio {
        return Audio{
            .device = null,
            .lastCallbackTime = sdl.getPerformanceCounter(),
            .sounds = [_]?Sound{undefined} ** 16,
            .cursor = 0,
            .next_sound_index = 0,
        };
    }

    pub fn open(self: *Audio) !void {
        self.device = try sdl.AudioDevice.init(
            null,
            false,
            std.mem.zeroInit(sdl.SDL_AudioSpec, .{
                .freq = 48000,
                .format = sdl.AUDIO_S16LSB,
                .channels = 2,
                .samples = 512,
                .callback = struct {
                    export fn callback(userdata: ?*c_void, data: [*c]u8, len: i32) void {
                        var audio = @ptrCast(*Audio, @alignCast(@alignOf(*Audio), userdata));
                        var buffer = @ptrCast([*c]i16, @alignCast(@alignOf(i16), data))[0 .. @intCast(usize, len) / 2];

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

    pub fn start(self: *Audio) void {
        if (self.device) |device| {
            device.play();
        }
    }

    pub fn stop(self: *Audio) void {
        if (self.device) |device| {
            device.pause();
        }
    }

    pub fn play(self: *Audio, sound: Sound) void {
        self.sounds[self.next_sound_index] = Sound{
            .offset = sound.offset + self.cursor,
            .data = sound.data,
            .volume = sound.volume,
        };

        self.next_sound_index = (self.next_sound_index + 1) % 16;
    }

    fn callback(self: *Audio, buffer: []i16) void {
        std.debug.assert(self.device != null);
        var newTime = sdl.getPerformanceCounter();
        self.lastCallbackTime = newTime;
        std.mem.set(i16, buffer, 0);

        for (self.sounds) |maybe_sound, i| {
            if (maybe_sound) |sound| {
                if (self.cursor < sound.offset) {
                    continue;
                }
                // Figure out how much we need to copy
                var soundBeginCursor = self.cursor - sound.offset;

                // Sound is finished
                if (soundBeginCursor >= sound.data.len) {
                    self.sounds[i] = undefined;
                    continue;
                }

                var soundEndCursor = soundBeginCursor + std.math.min(sound.data.len - soundBeginCursor, buffer.len);

                sdl.mixAudio(i16, buffer, sound.data[soundBeginCursor..soundEndCursor], sdl.AUDIO_S16LSB, sound.volume);
            }
        }
        self.cursor += buffer.len;
        std.mem.copy(i16, self.buffer_copy[0..self.buffer_copy.len], buffer);
    }
};

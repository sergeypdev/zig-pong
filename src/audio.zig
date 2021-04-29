const std = @import("std");
const sdl = @import("sdl.zig");

pub const Audio = struct {
    device: ?sdl.AudioDevice,
    lastCallbackTime: u64,
    // We'll allow up to 16 sounds to be played simultaneously
    sounds: [16]?Sound,
    next_sound_index: u8,
    cursor: u64, // current play cursor in the "global" timeline
    buffer_copy: [2 * 2048]i16 = [_]i16{0} ** (2 * 2048),

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
                .samples = 2048,
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
                if (self.cursor + buffer.len <= sound.offset) {
                    continue;
                }
                // Figure out where in the sound we should start copying
                var soundBeginCursor = self.cursor - std.math.min(sound.offset, self.cursor);

                // Sound is finished
                if (soundBeginCursor >= sound.data.len) {
                    self.sounds[i] = undefined;
                    continue;
                }

                var bufferStartOffset: usize = 0;

                // Sound should begin in the middle of current buffer
                if (sound.offset > self.cursor) {
                    bufferStartOffset = sound.offset - self.cursor;
                }

                var copyLen = buffer.len - bufferStartOffset;

                var soundEndCursor = soundBeginCursor + std.math.min(sound.data.len - soundBeginCursor, copyLen);

                // sdl mixing
                // sdl.mixAudio(i16, buffer[bufferStartOffset..], sound.data[soundBeginCursor..soundEndCursor], sdl.AUDIO_S16LSB, sound.volume);
                //
                // no mixing
                // std.mem.copy(i16, buffer[bufferStartOffset..], sound.data[soundBeginCursor..soundEndCursor]);

                // Custom mixing (just adding with clipping)
                var bufferSlice = buffer[bufferStartOffset..];
                var soundSlice = sound.data[soundBeginCursor..soundEndCursor];

                var j: usize = 0;
                while (j < soundSlice.len) : (j += 1) {
                    var result: i16 = undefined;
                    if (@addWithOverflow(i16, bufferSlice[j], soundSlice[j], &result)) {
                        if (result > 0) {
                            // Underflow
                            bufferSlice[j] = std.math.maxInt(i16);
                        } else {
                            // Overflow
                            bufferSlice[j] = std.math.minInt(i16);
                        }
                    } else {
                        bufferSlice[j] = result;
                    }
                }
            }
        }
        self.cursor += buffer.len;
        std.mem.copy(i16, self.buffer_copy[0..self.buffer_copy.len], buffer);
    }
};

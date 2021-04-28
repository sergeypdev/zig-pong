const std = @import("std");
pub usingnamespace @cImport({
    @cInclude("SDL.h");
});

pub fn init(flags: c_uint) !void {
    var errCode = SDL_Init(flags);

    if (errCode != 0) {
        std.debug.warn("SDL: Failed to init: {s}\n", .{SDL_GetError()});
        SDL_ClearError();
        return error.InitError;
    }
}

pub fn deinit() void {
    SDL_Quit();
}

pub const Color = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
};

pub const Window = struct {
    window: *SDL_Window,

    pub fn init(title: [*:0]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: c_uint) anyerror!Window {
        var raw_window = SDL_CreateWindow(title, x, y, w, h, flags);

        if (raw_window) |window| {
            return Window{ .window = window };
        }

        std.debug.warn("SDL: Failed to create window: {s}\n", .{SDL_GetError()});
        return error.CreateWindow;
    }

    pub fn deinit(self: Window) void {
        SDL_DestroyWindow(self.window);
    }

    pub fn getSurface(self: Window) !*SDL_Surface {
        if (SDL_GetWindowSurface(self.window)) |surface| {
            return surface;
        }

        std.debug.warn("SDL: Failed to get window surface: {s}\n", .{SDL_GetError()});
        return error.GetWindowSurface;
    }
};

pub const Renderer = struct {
    renderer: *SDL_Renderer,

    pub const Texture = struct {
        texture: *SDL_Texture,

        pub fn deinit(self: *Texture) void {
            SDL_DestroyTexture(self.texture);
        }
    };

    pub fn init(window: *Window, ind: i32, flags: u32) !Renderer {
        if (SDL_CreateRenderer(window.window, ind, flags)) |renderer| {
            return Renderer{ .renderer = renderer };
        }

        std.debug.warn("SDL: Failed to create renderer: {s}\n", .{SDL_GetError()});
        return error.InitRenderer;
    }

    pub fn deinit(self: Renderer) void {
        SDL_DestroyRenderer(self.renderer);
    }

    pub fn info(self: Renderer) !SDL_RendererInfo {
        var raw_info: SDL_RendererInfo = undefined;

        if (SDL_GetRendererInfo(self.renderer, &raw_info) != 0) {
            std.debug.warn("SDL: Failed to get renderer info: {s}\n", .{SDL_GetError()});
            return error.GetRendererInfo;
        }

        return raw_info;
    }

    pub fn clear(self: Renderer) !void {
        if (SDL_RenderClear(self.renderer) != 0) {
            std.debug.warn("SDL: Failed to render clear: {s}\n", .{SDL_GetError()});
            return error.RenderClear;
        }
    }

    pub fn setDrawColor(self: Renderer, c: Color) !void {
        if (SDL_SetRenderDrawColor(self.renderer, c.r, c.g, c.b, c.a) != 0) {
            std.debug.warn("SDL: Failed to set draw color: {s}\n", .{SDL_GetError()});
            return error.SetDrawColor;
        }
    }

    pub fn fillRect(self: Renderer, rect: ?*const SDL_Rect) !void {
        if (SDL_RenderFillRect(self.renderer, rect) != 0) {
            std.debug.warn("SDL: Failed to fill rect: {s}\n", .{SDL_GetError()});
            return error.FillRect;
        }
    }

    pub fn createTextureFromSurface(self: *Renderer, surface: *Surface) !Texture {
        var maybe_texture = SDL_CreateTextureFromSurface(self.renderer, surface.surface);

        if (maybe_texture) |texture| {
            return Texture{ .texture = texture };
        }

        std.debug.warn("SDL: Failed to create texture from surface: {s}\n", .{SDL_GetError()});
        return error.CreateTextureFromSurface;
    }

    pub fn present(self: Renderer) void {
        SDL_RenderPresent(self.renderer);
    }
};

pub const AudioDevice = struct {
    deviceId: SDL_AudioDeviceID,
    spec: SDL_AudioSpec,

    pub fn init(device: ?[*:0]const u8, isCapture: bool, desired: SDL_AudioSpec, allowedChanges: i32) !AudioDevice {
        var obtained: SDL_AudioSpec = undefined;
        var deviceId = SDL_OpenAudioDevice(device, @boolToInt(isCapture), &desired, &obtained, allowedChanges);

        if (deviceId > 0) {
            return AudioDevice{ .deviceId = deviceId, .spec = obtained };
        } else {
            std.debug.warn("SDL: Failed to open audio device: {s}\n", .{SDL_GetError()});
            return error.OpenAudioDevice;
        }
    }

    pub fn deinit(self: AudioDevice) void {
        SDL_CloseAudioDevice(self.deviceId);
    }

    pub fn play(self: AudioDevice) void {
        SDL_PauseAudioDevice(self.deviceId, 0);
    }

    pub fn pause(self: AudioDevice) void {
        SDL_PauseAudioDevice(self.deviceId, 1);
    }
};

pub fn mixAudio(comptime T: type, dst: []T, src: []const T, format: SDL_AudioFormat, volume: u7) void {
    std.debug.assert(src.len <= dst.len);
    std.debug.assert(src.len <= std.math.maxInt(u32));
    SDL_MixAudioFormat(
        @ptrCast([*c]u8, @ptrCast([*c]T, dst)),
        @ptrCast([*c]const u8, @ptrCast([*c]const T, src)),
        format,
        @intCast(u32, src.len),
        @intCast(c_int, volume),
    );
}

///
/// Returns the number of ms since start of the game
///
pub fn ticks() u32 {
    return SDL_GetTicks();
}

pub fn getPerformanceCounter() u64 {
    return SDL_GetPerformanceCounter();
}

pub fn getPerformanceFrequency() u64 {
    return SDL_GetPerformanceFrequency();
}

pub const RWops = struct {
    rwops: *SDL_RWops,

    pub fn fromConstMem(mem: [*:0]const u8, len: usize) !RWops {
        if (SDL_RWFromConstMem(@ptrCast(*const c_void, mem), @intCast(c_int, len))) |rwops| {
            return RWops{ .rwops = rwops };
        }

        std.debug.warn("SDL: Failed to create RWops from const mem: {s}\n", .{SDL_GetError()});
        return error.RWopsCreateFail;
    }

    pub fn close(self: *RWops) !void {
        if (SDL_RWclose(self.rwops) != 0) {
            std.debug.warn("SDL: Failed to close RWops: {s}\n", .{SDL_GetError()});
            return error.RWopsCloseFail;
        }
    }
};

pub const Surface = struct {
    surface: *SDL_Surface,

    pub fn createRGBFrom(
        pixels: ?*c_void,
        width: c_int,
        height: c_int,
        depth: c_int,
        pitch: c_int,
        rMask: u32,
        gMask: u32,
        bMask: u32,
        aMask: u32,
    ) !Surface {
        var maybe_surface = SDL_CreateRGBSurfaceFrom(pixels, width, height, depth, pitch, rMask, gMask, bMask, aMask);

        if (maybe_surface) |surface| {
            return Surface{ .surface = surface };
        }

        std.debug.warn("SDL: Failed to create surface from pixels: {s}\n", .{SDL_GetError()});
        return error.CreateSurfaceFrom;
    }

    pub fn deinit(self: *Surface) void {
        SDL_FreeSurface(self.surface);
    }
};

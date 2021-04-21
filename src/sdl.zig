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

    pub fn present(self: Renderer) void {
        SDL_RenderPresent(self.renderer);
    }
};

///
/// Returns the number of ms since start of the game
///
pub fn ticks() u32 {
    return SDL_GetTicks();
}

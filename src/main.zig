const std = @import("std");
const sdl = @import("sdl.zig");
const Audio = @import("audio.zig").Audio;
const DumbFont16 = @import("dumbfont.zig").DumbFont16;
const bounce_bytes = @embedFile("../assets/bounce.wav");
const main_font_bytes = @embedFile("../assets/04b_30.dumbfont16");

const Player = enum {
    left,
    right,
};

const Phase = union(enum) {
    starting,
    playing,
    finished: Player,
};

const PlayerState = struct {
    me: Player,
    y: i32,
    up: bool = false,
    down: bool = false,

    pub fn paddle_top(self: PlayerState) i32 {
        return self.y - (PADDLE_HEIGHT / 2);
    }
    pub fn paddle_bottom(self: PlayerState) i32 {
        return self.y + (PADDLE_HEIGHT / 2);
    }
    pub fn paddle_left(self: PlayerState) i32 {
        switch (self.me) {
            .left => return 0,
            .right => return WIDTH - PADDLE_WIDTH,
        }
    }
    pub fn paddle_right(self: PlayerState) i32 {
        switch (self.me) {
            .left => return PADDLE_WIDTH,
            .right => return WIDTH,
        }
    }
};

const Ball = struct {
    radius: i32,
    x: i32,
    y: i32,
    vx: i32,
    vy: i32,

    pub fn bottom(self: Ball) i32 {
        return self.y + (BALL_RADIUS / 2);
    }
    pub fn top(self: Ball) i32 {
        return self.y - (BALL_RADIUS / 2);
    }
    pub fn left(self: Ball) i32 {
        return self.x - (BALL_RADIUS / 2);
    }
    pub fn right(self: Ball) i32 {
        return self.x + (BALL_RADIUS / 2);
    }
};

const GameAssets = struct {
    bounce_pcm: []const i16,
    main_font: *DumbFont16,
};

const GameState = struct {
    phase: Phase,
    left: PlayerState,
    right: PlayerState,
    ball: Ball,

    pub fn init() GameState {
        return GameState{
            .phase = .starting,
            .left = .{
                .me = .left,
                .y = HEIGHT / 2,
            },
            .right = .{
                .me = .right,
                .y = HEIGHT / 2,
            },
            .ball = .{
                .radius = BALL_RADIUS,
                .x = WIDTH / 2,
                .y = HEIGHT / 2,
                .vx = 0,
                .vy = 0,
            },
        };
    }

    pub fn restart(self: *GameState) void {
        switch (self.phase) {
            .finished => |winner| {
                self.phase = .playing;
                self.left.y = HEIGHT / 2;
                self.right.y = HEIGHT / 2;
                self.ball.x = WIDTH / 2;
                self.ball.y = HEIGHT / 2;
                switch (winner) {
                    .left => {
                        self.ball.vx = BALL_SPEED;
                    },
                    .right => {
                        self.ball.vx = -BALL_SPEED;
                    },
                }
                self.ball.vy = BALL_SPEED;
                self.ball.radius = BALL_RADIUS;
            },
            else => {},
        }
    }
};

const BALL_SPEED = 5;
const BALL_RADIUS = 20;
const WIDTH = 800;
const HEIGHT = 600;
const PADDLE_HEIGHT = 100;
const PADDLE_WIDTH = 30;

const MEM_SIZE = 1024 * 1024 * 128; // 128 megs

pub fn main() anyerror!void {
    var game_mem = try std.heap.c_allocator.alloc(u8, MEM_SIZE);

    var allocator = std.heap.FixedBufferAllocator.init(game_mem);

    try sdl.init(sdl.SDL_INIT_EVERYTHING);

    var window = try sdl.Window.init(
        "Pong",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_ALLOW_HIGHDPI,
    );

    var render = try sdl.Renderer.init(&window, -1, sdl.SDL_RENDERER_PRESENTVSYNC | sdl.SDL_RENDERER_ACCELERATED);

    const maybe_info = render.info() catch null;
    if (maybe_info) |info| {
        std.debug.warn("Render name: {s}\nRender info: {}\n", .{ info.name, info });
    }

    var bounce_rwops = try sdl.RWops.fromConstMem(bounce_bytes, bounce_bytes.len);

    var bounce_spec: sdl.SDL_AudioSpec = undefined;
    var bounce_pcm: [*c]u8 = undefined;
    var bounce_pcm_len: u32 = undefined;

    if (sdl.SDL_LoadWAV_RW(bounce_rwops.rwops, 0, &bounce_spec, &bounce_pcm, &bounce_pcm_len) == null) {
        return error.WAVLoadError;
    }
    std.debug.warn("Bounce Audio Spec: {}\n", .{bounce_spec});

    var main_font = try DumbFont16.fromConstMem(main_font_bytes[0..]);

    var assets = GameAssets{
        .bounce_pcm = @ptrCast([*c]i16, @alignCast(@alignOf(i16), bounce_pcm))[0 .. bounce_pcm_len / 2],
        .main_font = &main_font,
    };

    var audio = Audio.init();

    try audio.open();
    audio.start();

    var state = GameState.init();

    mainloop: while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :mainloop,
                sdl.SDL_KEYUP => processInput(&state, event.key),
                sdl.SDL_KEYDOWN => processInput(&state, event.key),
                else => {},
            }
        }

        try gameUpdateAndRender(&assets, &state, &render, &audio);
    }
}

fn processInput(game_state: *GameState, event: sdl.SDL_KeyboardEvent) void {
    switch (game_state.phase) {
        .starting => {
            game_state.phase = .playing;
            game_state.ball.vx = BALL_SPEED;
            game_state.ball.vy = BALL_SPEED;
        },
        .playing => {
            switch (event.keysym.scancode) {
                sdl.SDL_Scancode.SDL_SCANCODE_W => {
                    game_state.left.up = event.state == sdl.SDL_PRESSED;
                },
                sdl.SDL_Scancode.SDL_SCANCODE_S => {
                    game_state.left.down = event.state == sdl.SDL_PRESSED;
                },
                sdl.SDL_Scancode.SDL_SCANCODE_UP => {
                    game_state.right.up = event.state == sdl.SDL_PRESSED;
                },
                sdl.SDL_Scancode.SDL_SCANCODE_DOWN => {
                    game_state.right.down = event.state == sdl.SDL_PRESSED;
                },
                else => {},
            }
        },
        .finished => {
            game_state.restart();
        },
    }
}

fn gameUpdateAndRender(assets: *GameAssets, state: *GameState, render: *sdl.Renderer, audio: *Audio) !void {
    try render.setDrawColor(sdl.Color.black);
    try render.clear();

    try render.setDrawColor(sdl.Color.white);

    // try render.fillRect(&.{ .x = 500, .y = 500, .w = 100, .h = 100 });

    switch (state.phase) {
        .playing => {
            if (state.left.up) {
                state.left.y -= 10;
            }
            if (state.left.down) {
                state.left.y += 10;
            }
            if (state.right.up) {
                state.right.y -= 10;
            }
            if (state.right.down) {
                state.right.y += 10;
            }

            state.left.y = std.math.clamp(state.left.y, PADDLE_HEIGHT / 2, HEIGHT - (PADDLE_HEIGHT / 2));
            state.right.y = std.math.clamp(state.right.y, PADDLE_HEIGHT / 2, HEIGHT - (PADDLE_HEIGHT / 2));

            state.ball.x += state.ball.vx;
            state.ball.y += state.ball.vy;

            if (state.ball.bottom() >= HEIGHT) {
                state.ball.vy = -state.ball.vy;
            }
            if (state.ball.top() < 0) {
                state.ball.vy = -state.ball.vy;
            }

            if (state.ball.left() <= state.left.paddle_right() and state.ball.vx < 0) {
                var top = state.left.paddle_top() - state.ball.radius;
                var bottom = state.left.paddle_bottom() + state.ball.radius;
                if (state.ball.y >= top and state.ball.y <= bottom) {
                    state.ball.vx = -state.ball.vx;
                    audio.play(.{
                        .offset = @as(u64, 0),
                        .data = assets.bounce_pcm,
                        .volume = 127,
                    });
                }
            }
            if (state.ball.right() >= state.right.paddle_left() and state.ball.vx > 0) {
                var top = state.right.paddle_top() - state.ball.radius;
                var bottom = state.right.paddle_bottom() + state.ball.radius;
                if (state.ball.y >= top and state.ball.y <= bottom) {
                    state.ball.vx = -state.ball.vx;
                    audio.play(.{
                        .offset = 1,
                        .data = assets.bounce_pcm,
                        .volume = 127,
                    });
                }
            }

            if (state.ball.left() < 0) {
                state.phase = Phase{ .finished = .right };
                state.ball.radius = BALL_RADIUS * 2;
            } else if (state.ball.right() >= WIDTH) {
                state.phase = Phase{ .finished = .left };
                state.ball.radius = BALL_RADIUS * 2;
            }
        },
        else => {},
    }

    // Left paddle
    try render.fillRect(&.{
        .x = 0,
        .y = state.left.y - (PADDLE_HEIGHT / 2),
        .w = PADDLE_WIDTH,
        .h = PADDLE_HEIGHT,
    });

    // Left paddle
    try render.fillRect(&.{
        .x = WIDTH - PADDLE_WIDTH,
        .y = state.right.y - (PADDLE_HEIGHT / 2),
        .w = PADDLE_WIDTH,
        .h = PADDLE_HEIGHT,
    });

    // Ball
    var char: usize = '0';

    while (char <= '9') : (char += 1) {
        var offset = (char - '0') * 16 * 4;
        var glyph = &assets.main_font.glyphs[char];

        var y: usize = 0;
        while (y < 16) : (y += 1) {
            var row = glyph.pixels[y];
            var x: usize = 0;
            while (x < 16) : (x += 1) {
                if ((row & @as(u16, 1) << @intCast(u4, x)) > 0) {
                    try render.fillRect(&.{
                        .x = state.ball.x + @intCast(i32, x) * 4 + @intCast(i32, offset),
                        .y = state.ball.y + @intCast(i32, y) * 4,
                        .w = 4,
                        .h = 4,
                    });
                }
            }
        }
    }

    // try render.fillRect(&.{
    //     .x = state.ball.x - (@divTrunc(state.ball.radius, 2)),
    //     .y = state.ball.y - (@divTrunc(state.ball.radius, 2)),
    //     .w = state.ball.radius,
    //     .h = state.ball.radius,
    // });

    const soundRatioX = WIDTH / @intToFloat(f32, audio.buffer_copy.len / 2);
    const soundRatio = HEIGHT / @intToFloat(f32, std.math.maxInt(i16));
    const graphSize = (soundRatio) * HEIGHT;

    var i: usize = 0;
    while (i < audio.buffer_copy.len / 2) : (i += 1) {
        try render.fillRect(&.{
            .x = @floatToInt(c_int, @intToFloat(f32, i) * soundRatioX),
            .y = HEIGHT - @floatToInt(c_int, (graphSize)),
            .w = 1,
            .h = @floatToInt(c_int, @intToFloat(f32, audio.buffer_copy[i]) * soundRatio),
        });
    }

    render.present();
}

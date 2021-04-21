const std = @import("std");
const sdl = @import("sdl.zig");
const Audio = @import("audio.zig").Audio;

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

pub fn main() anyerror!void {
    try sdl.init(sdl.SDL_INIT_EVERYTHING);
    defer sdl.deinit();

    var window = try sdl.Window.init(
        "Pong",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_ALLOW_HIGHDPI,
    );
    defer window.deinit();

    var render = try sdl.Renderer.init(&window, -1, sdl.SDL_RENDERER_PRESENTVSYNC | sdl.SDL_RENDERER_ACCELERATED);
    defer render.deinit();

    const maybe_info = render.info() catch null;
    if (maybe_info) |info| {
        std.debug.warn("Render name: {s}\nRender info: {}\n", .{ info.name, info });
    }

    var audio = Audio.init();
    defer audio.deinit();

    try audio.open();
    audio.play();

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

        try gameUpdateAndRender(&state, &render);
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

fn gameUpdateAndRender(state: *GameState, render: *sdl.Renderer) !void {
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
                }
            }
            if (state.ball.right() >= state.right.paddle_left() and state.ball.vx > 0) {
                var top = state.right.paddle_top() - state.ball.radius;
                var bottom = state.right.paddle_bottom() + state.ball.radius;
                if (state.ball.y >= top and state.ball.y <= bottom) {
                    state.ball.vx = -state.ball.vx;
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
    try render.fillRect(&.{
        .x = state.ball.x - (@divTrunc(state.ball.radius, 2)),
        .y = state.ball.y - (@divTrunc(state.ball.radius, 2)),
        .w = state.ball.radius,
        .h = state.ball.radius,
    });

    render.present();
}

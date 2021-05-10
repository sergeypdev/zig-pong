const std = @import("std");
const unicode = std.unicode;
const sdl = @import("sdl.zig");
const Audio = @import("audio.zig").Audio;
const DumbFont16 = @import("dumbfont.zig").DumbFont16;
const PF2Font = @import("pf2.zig").PF2Font;
const bounce_bytes = @embedFile("../assets/bounce.wav");
const main_font_bytes = @embedFile("../assets/04b_30.dumbfont16");
const pf2_bytes = @embedFile("../assets/ka1.pf2");

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
    score: u8 = 0,

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
    other_font: *PF2Font,
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

const MainMenuButtons = enum {
    Play,
    Exit,
};

const MainMenuState = struct {
    selectedItem: MainMenuButtons,
};

const GlobalGameState = union(enum) {
    MainMenu: MainMenuState,
    Game: GameState,
};

const BALL_SPEED = 5;
const BALL_RADIUS = 20;
const WIDTH = 800;
const HEIGHT = 600;
const PADDLE_HEIGHT = 100;
const PADDLE_WIDTH = 30;

const MEM_SIZE = 1024 * 1024 * 128; // 128 megs

pub fn main() anyerror!void {
    var other_font = try PF2Font.fromConstMem(pf2_bytes);

    std.debug.warn("Font: {}\n", .{other_font});

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
        .other_font = &other_font,
    };

    var audio = Audio.init();

    try audio.open();
    audio.start();

    var shouldExit: bool = false;
    var state = GlobalGameState{ .MainMenu = MainMenuState{ .selectedItem = .Play } };

    mainloop: while (!shouldExit) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :mainloop,
                sdl.SDL_KEYUP => processInput(&audio, &state, &shouldExit, &assets, event.key),
                sdl.SDL_KEYDOWN => processInput(&audio, &state, &shouldExit, &assets, event.key),
                else => {},
            }
        }

        try gameUpdateAndRender(&assets, &state, &shouldExit, &render, &audio);
    }
}

fn processInput(audio: *Audio, global_game_state: *GlobalGameState, shouldExit: *bool, assets: *const GameAssets, event: sdl.SDL_KeyboardEvent) void {
    switch (global_game_state.*) {
        .MainMenu => |*state| {
            if (event.state == sdl.SDL_PRESSED) {
                switch (event.keysym.scancode) {
                    sdl.SDL_Scancode.SDL_SCANCODE_W, sdl.SDL_Scancode.SDL_SCANCODE_S => {
                        audio.play(.{ .data = assets.bounce_pcm, .offset = 0, .volume = 127 });
                        switch (state.selectedItem) {
                            .Play => state.selectedItem = .Exit,
                            .Exit => state.selectedItem = .Play,
                        }
                    },
                    sdl.SDL_Scancode.SDL_SCANCODE_RETURN => {
                        switch (state.selectedItem) {
                            .Play => global_game_state.* = GlobalGameState{ .Game = GameState.init() },
                            .Exit => shouldExit.* = true,
                        }
                    },
                    else => {},
                }
            }
        },
        .Game => |*game_state| {
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
        },
    }
}

const TOP_OFFSET = 64;

fn gameUpdateAndRender(assets: *GameAssets, global_state: *GlobalGameState, shouldExit: *bool, render: *sdl.Renderer, audio: *Audio) !void {
    try render.setDrawColor(sdl.Color.black);
    try render.clear();

    switch (global_state.*) {
        .MainMenu => |*state| {
            try render.setDrawColor(sdl.Color.white);

            try drawAlignedText(render, "ZIG PONG", .center, assets.other_font, 0, 800, 100, 4, 1);

            const buttonPadding = 20;
            const buttonFontScale = 3;

            switch (state.selectedItem) {
                .Play => {
                    var textWidth = try measureText("PLAY", assets.other_font, buttonFontScale, 1);
                    var halfWidth = @divTrunc(textWidth, 2);
                    try render.fillRect(&.{
                        .x = 400 - halfWidth - buttonPadding,
                        .y = 400 + assets.other_font.descent * buttonFontScale - assets.other_font.maxHeight * buttonFontScale - buttonPadding,
                        .w = textWidth + buttonPadding * 2,
                        .h = assets.other_font.maxHeight * buttonFontScale + buttonPadding * 2,
                    });
                    try render.setDrawColor(sdl.Color.black);
                    try drawAlignedText(render, "PLAY", .center, assets.other_font, 0, 800, 400, buttonFontScale, 1);
                    try render.setDrawColor(sdl.Color.white);

                    try drawAlignedText(render, "EXIT", .center, assets.other_font, 0, 800, 500, buttonFontScale, 1);
                },
                .Exit => {
                    try drawAlignedText(render, "PLAY", .center, assets.other_font, 0, 800, 400, buttonFontScale, 1);

                    var textWidth = try measureText("EXIT", assets.other_font, buttonFontScale, 1);
                    var halfWidth = @divTrunc(textWidth, 2);
                    try render.fillRect(&.{
                        .x = 400 - halfWidth - buttonPadding,
                        .y = 500 + assets.other_font.descent * buttonFontScale - assets.other_font.maxHeight * buttonFontScale - buttonPadding,
                        .w = textWidth + buttonPadding * 2,
                        .h = assets.other_font.maxHeight * buttonFontScale + buttonPadding * 2,
                    });
                    try render.setDrawColor(sdl.Color.black);
                    try drawAlignedText(render, "EXIT", .center, assets.other_font, 0, 800, 500, buttonFontScale, 1);
                    try render.setDrawColor(sdl.Color.white);
                },
            }
        },
        .Game => |*state| {
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

                    state.left.y = std.math.clamp(state.left.y, PADDLE_HEIGHT / 2 + TOP_OFFSET, HEIGHT - (PADDLE_HEIGHT / 2));
                    state.right.y = std.math.clamp(state.right.y, PADDLE_HEIGHT / 2 + TOP_OFFSET, HEIGHT - (PADDLE_HEIGHT / 2));

                    state.ball.x += state.ball.vx;
                    state.ball.y += state.ball.vy;

                    if (state.ball.bottom() >= HEIGHT) {
                        state.ball.vy = -state.ball.vy;
                    }
                    if (state.ball.top() < TOP_OFFSET) {
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
                        _ = @addWithOverflow(u8, state.right.score, 1, &state.right.score);
                    } else if (state.ball.right() >= WIDTH) {
                        state.phase = Phase{ .finished = .left };
                        _ = @addWithOverflow(u8, state.left.score, 1, &state.left.score);
                    }

                    try render.fillRect(&.{
                        .x = state.ball.x - (@divTrunc(state.ball.radius, 2)),
                        .y = state.ball.y - (@divTrunc(state.ball.radius, 2)),
                        .w = state.ball.radius,
                        .h = state.ball.radius,
                    });
                },
                .finished => |winner| {
                    var text = blk: {
                        switch (winner) {
                            .left => break :blk "Left Player Won!",
                            .right => break :blk "Right Player Won!",
                        }
                    };

                    try drawAlignedText(render, text, .center, assets.other_font, 0, 800, 300, 3, 1);
                    try drawAlignedText(render, "Press any button to continue", .center, assets.other_font, 0, 800, 400, 2, 1);
                },
                else => {},
            }

            const SEP_WIDTH = 4;

            try render.fillRect(&.{
                .x = WIDTH / 2 - SEP_WIDTH / 2,
                .y = TOP_OFFSET,
                .w = SEP_WIDTH,
                .h = HEIGHT,
            });

            // Score drawing
            var score = [_]u8{0} ** 3;

            var leftScoreLen = std.fmt.formatIntBuf(score[0..], state.left.score, 10, false, .{});
            try drawAlignedText(render, score[0..leftScoreLen], .right, assets.other_font, 0, WIDTH / 2 - SEP_WIDTH / 2 - 16, TOP_OFFSET - 16, 3, 0);

            var rightScoreLen = std.fmt.formatIntBuf(score[0..], state.right.score, 10, false, .{});
            try drawAlignedText(render, score[0..rightScoreLen], .left, assets.other_font, WIDTH / 2 + SEP_WIDTH / 2 + 16, WIDTH, TOP_OFFSET - 16, 3, 0);

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

            // try drawTextPf2(render, "Test, I'm a ball", state.ball.x, state.ball.y, assets.other_font, 2, 1);

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
        },
    }

    render.present();
}

pub const TextAlign = enum {
    left,
    center,
    right,
};

fn drawAlignedText(render: *sdl.Renderer, text: []const u8, alignment: TextAlign, font: *PF2Font, minX: i32, maxX: i32, y: i32, scale: i32, letterSpacing: i32) !void {
    std.debug.assert(minX <= maxX);
    var x: i32 = undefined;
    switch (alignment) {
        .left => x = minX,
        .center => {
            var width = try measureText(text, font, scale, letterSpacing);
            var boundsMiddle = @divTrunc(maxX - minX, 2);
            x = boundsMiddle - @divTrunc(width, 2);
        },
        .right => {
            var width = try measureText(text, font, scale, letterSpacing);
            x = maxX - width;
        },
    }

    try drawTextPf2(render, text, x, y, font, scale, letterSpacing);
}

fn measureText(text: []const u8, font: *PF2Font, scale: i32, letterSpacing: i32) !i32 {
    var width: i32 = 0;

    var view = try unicode.Utf8View.init(text);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |codepoint| {
        var glyph = font.getChar(codepoint) orelse continue;

        width += glyph.deviceWidth * scale + letterSpacing;
    }

    if (width > 0) {
        width -= letterSpacing;
    }

    return width;
}

fn drawTextPf2(render: *sdl.Renderer, text: []const u8, screenX: i32, screenY: i32, font: *PF2Font, scale: i32, letterSpacing: i32) !void {
    var offset: i32 = 0;

    var view = try unicode.Utf8View.init(text);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |codepoint| {
        var glyph = font.getChar(codepoint) orelse continue;

        var y: usize = 0;
        while (y < glyph.height) : (y += 1) {
            var x: usize = 0;
            while (x < glyph.width) : (x += 1) {
                var bitIndex = y * glyph.width + x;
                var currentByte = glyph.pixels[bitIndex / 8];
                var currentByteBitIndex = bitIndex % 8;
                if (currentByte & (@as(u8, 0b10000000) >> @intCast(u3, currentByteBitIndex)) > 0) {
                    try render.fillRect(&.{
                        .x = glyph.xOffset * scale + screenX + @intCast(i32, x) * scale + @intCast(i32, offset),
                        .y = screenY + @intCast(i32, y) * scale - glyph.yOffset * scale - glyph.height * scale,
                        .w = scale,
                        .h = scale,
                    });
                }
            }
        }

        offset += glyph.deviceWidth * scale + letterSpacing;
    }
}

fn drawText(render: *sdl.Renderer, text: []const u8, x: i32, y: i32, font: *DumbFont16, scale: i32, letterSpacing: i32) !void {
    var offset: i32 = 0;
    for (text) |char, i| {
        var glyph = &font.glyphs[char];

        var glyphY: usize = 0;
        while (glyphY < 16) : (glyphY += 1) {
            var row = glyph.pixels[glyphY];
            var glyphX: usize = 0;
            while (glyphX < 16) : (glyphX += 1) {
                if ((row & @as(u16, 1) << @intCast(u4, glyphX)) > 0) {
                    try render.fillRect(&.{
                        .x = x + @intCast(i32, glyphX) * scale + @intCast(i32, offset),
                        .y = y + @intCast(i32, glyphY) * scale,
                        .w = scale,
                        .h = scale,
                    });
                }
            }
        }

        switch (char) {
            '1', 'i', 'I' => {
                offset += 10 * scale + letterSpacing;
            },
            ' ' => {
                offset += 4 * scale;
            },
            '\'' => {
                offset += 8 * scale;
            },
            else => {
                offset += 16 * scale + letterSpacing;
            },
        }
    }
}

-- Central de constantes do jogo; a origem do mundo fica no centro da quadra.
local config = {}

config.fixed_dt = 1 / 60
config.max_dt_acc = 0.1
config.max_physics_steps = 5
config.entityScale = 1.0
config.viewport = {
    width = 1280, height = 720, world_padding = 18,
    world_left_reserved = 24, world_right_reserved = 90,
    world_top_reserved = 70, world_bottom_reserved = 50,
}

config.default_mode = "2v2"
config.mode_names = { "1v1", "2v2", "3v3", "4v4", "5v5" }
config.formations = {
    ["1v1"] = { capacity = 1, red = { { x = -650, y = 0 } }, blue = { { x = 650, y = 0 } } },
    ["2v2"] = { capacity = 2, red = { { x = -900, y = 0 }, { x = -450, y = -180 } }, blue = { { x = 900, y = 0 }, { x = 450, y = 180 } } },
    ["3v3"] = { capacity = 3, red = { { x = -1050, y = 0 }, { x = -600, y = -260 }, { x = -600, y = 260 } }, blue = { { x = 1050, y = 0 }, { x = 600, y = 260 }, { x = 600, y = -260 } } },
    ["4v4"] = { capacity = 4, red = { { x = -1150, y = 0 }, { x = -750, y = -360 }, { x = -750, y = -120 }, { x = -750, y = 240 } }, blue = { { x = 1150, y = 0 }, { x = 750, y = 360 }, { x = 750, y = 120 }, { x = 750, y = -240 } } },
    ["5v5"] = { capacity = 5, red = { { x = -1200, y = 0 }, { x = -850, y = -420 }, { x = -850, y = -140 }, { x = -850, y = 140 }, { x = -850, y = 420 } }, blue = { { x = 1200, y = 0 }, { x = 850, y = 420 }, { x = 850, y = 140 }, { x = 850, y = -140 }, { x = 850, y = -420 } } },
}

config.field = {
    play_width = 3000,
    play_height = 1500,
    containment_margin = 150,
    center_circle_radius = 180,
    penalty_area_depth = 450,
    penalty_area_width = 900,
    goal_area_depth = 150,
    goal_area_width = 450,
    penalty_spot_distance = 300,
    corner_arc_radius = 60,
    goal_mouth_width = 320,
    goal_depth = 120,
    post_radius = 12,
    pitch_line_width = 3,
    goal_line_width = 2,
    corner_arc_segments = 16,
    net_grid_spacing = 30,
    debug_collider_line_width = 2,
    debug_post_line_width = 2,
}

config.player = {
    radius = 15 * config.entityScale,
    mass = 2.0,
    acceleration = 450,
    damping = 0.96,
    max_speed = 300,
    restitution = 0.5,
    kick_margin = 4,
    kick_strength = 540,
    kick_player_speed_ratio = 0.0,
}

config.ball = {
    radius = 10 * config.entityScale,
    mass = 1.0,
    damping = 0.99,
    wall_restitution = 0.5,
    post_restitution = 0.8,
    player_restitution = 0.5,
    max_speed = 850,
}

config.spin = {
    max_turn_rate_per_tick = 0.020,
    decay = 0.985,
    max_power_penalty = 0.15,
    wall_damping = 0.5,
    top_spin_factor = 0.006,
    back_spin_factor = 0.018,
}

config.spin_selector = {
    enabled = true,
    radius = 40,
    cue_radius = 8,
    move_speed = 2.0,
    reset_key = "c",
    local_keyboard_enabled = false,
}

config.trajectory = { max_ticks = 120, max_bounces = 2, step_stride = 2 }
config.game = { goal_reset_delay = 2.0 }

-- Quatro jogadores locais da versão-base; as formações suportam as futuras salas 3v3-5v5.
config.players = {
    { id = "p1", name = "P1", team = "red", number = 1,
      color = {0.88, 0.22, 0.22}, inner_color = {0.65, 0.15, 0.15},
      keys = { up = "w", down = "s", left = "a", right = "d", kick = "space" },
      spin_keys = { up = "t", down = "g", left = "f", right = "h", reset = "c" } },
    { id = "p2", name = "P2", team = "blue", number = 1,
      color = {0.22, 0.48, 0.88}, inner_color = {0.15, 0.32, 0.65},
      keys = { up = "up", down = "down", left = "left", right = "right", kick = "rshift" },
      spin_keys = { up = "up", down = "down", left = "left", right = "right", reset = "delete" } },
    { id = "p3", name = "P3", team = "red", number = 2,
      color = {0.95, 0.40, 0.20}, inner_color = {0.75, 0.22, 0.10},
      keys = { up = "i", down = "k", left = "j", right = "l", kick = "u" },
      spin_keys = { up = "home", down = "end", left = "delete", right = "pagedown", reset = "insert" } },
    { id = "p4", name = "P4", team = "blue", number = 2,
      color = {0.18, 0.70, 0.85}, inner_color = {0.10, 0.48, 0.60},
      keys = { up = "kp8", down = "kp5", left = "kp4", right = "kp6", kick = "kp0",
          up_alt = "8", down_alt = "5", left_alt = "4", right_alt = "6", kick_alt = "0" },
      spin_keys = { up = "kp9", down = "kp3", left = "kp7", right = "kp1", reset = "kp." } },
}

config.keys = {
    reset = "r",
    quit = "escape",
    debug = "f3",
    debug_colliders = "f4",
    fullscreen = "f11",
    cycle_mode = "f2",
}

config.colors = {
    clear = {0.08, 0.10, 0.12},
    pitch = {0.31, 0.50, 0.31},
    pitch_border = {0.24, 0.40, 0.24},
    lines = {1.0, 1.0, 1.0, 0.82},
    goal_box = {0.25, 0.38, 0.25, 0.7},
    posts = {0.90, 0.90, 0.90},
    collider_boundary = {1.0, 0.18, 0.18, 0.95},
    collider_post = {1.0, 0.90, 0.10, 0.95},
    collider_net = {0.10, 0.95, 1.0, 0.95},
    ball = {1.0, 1.0, 1.0},
    ball_outline = {0.15, 0.15, 0.15},
    kicking_glow = {1.0, 1.0, 1.0, 0.95},
    score_p1 = {0.95, 0.35, 0.35},
    score_p2 = {0.35, 0.65, 0.95},
    hud_text = {0.90, 0.90, 0.90},
    debug_bg = {0.0, 0.0, 0.0, 0.65},
    debug_text = {0.2, 1.0, 0.4},
    trajectory_dot = {1.0, 1.0, 0.3},
    spin_widget_bg = {0.12, 0.14, 0.17, 0.85},
    spin_widget_circle = {0.92, 0.92, 0.92},
    spin_widget_dot = {0.90, 0.25, 0.25},
    spin_widget_cross = {0.40, 0.45, 0.50, 0.6},
    spin_widget_btn = {0.22, 0.26, 0.32, 0.9},
}

return config

-- src/config.lua: Central de todas as constantes do jogo (física, presets de campo, teclas, cores e mecânica de curva)
local config = {}

-- Configurações globais de física de passo fixo (Fixed Timestep)
config.fixed_dt = 1 / 60            -- 60 Hz exato (~0.016667 s)
config.max_dt_acc = 0.1             -- Limite máximo acumulado por frame (evita congelamentos)
config.max_physics_steps = 5        -- Limite de passos de física por frame de render

-- Presets de Campo Selecionáveis
config.default_preset = "3v3"       -- Padrão inicial com 4 jogadores no campo 3v3
config.presets = {
    ["1v1"] = {
        name = "1v1",
        virtual_width = 1024,
        virtual_height = 576,
        width = 780,
        height = 400,
        goal_width = 60,            -- Profundidade da rede
        goal_height = 140,          -- Abertura entre as traves (eixo Y)
        post_radius = 8,
        center_radius = 70,
        spawns = {
            red = {
                { x = -180, y = 0 },
            },
            blue = {
                { x = 180, y = 0 },
            },
        },
    },
    ["2v2"] = {
        name = "2v2",
        virtual_width = 1200,
        virtual_height = 675,
        width = 960,
        height = 480,
        goal_width = 70,
        goal_height = 160,
        post_radius = 9,
        center_radius = 85,
        spawns = {
            red = {
                { x = -280, y = -70 },
                { x = -140, y = 70 },
            },
            blue = {
                { x = 280, y = 70 },
                { x = 140, y = -70 },
            },
        },
    },
    ["3v3"] = {
        name = "3v3",
        virtual_width = 1360,
        virtual_height = 765,
        width = 1120,
        height = 560,
        goal_width = 80,
        goal_height = 180,
        post_radius = 10,
        center_radius = 100,
        spawns = {
            red = {
                { x = -360, y = 0 },
                { x = -200, y = -110 },
                { x = -200, y = 110 },
            },
            blue = {
                { x = 360, y = 0 },
                { x = 200, y = -110 },
                { x = 200, y = 110 },
            },
        },
    },
}

-- Física dos Jogadores
config.player = {
    radius = 15,
    mass = 2.0,                     -- Razão jogador:bola = 2:1
    acceleration = 450,             -- Força de aceleração ao pressionar direcionais
    damping = 0.96,                 -- Fator de atrito aplicado UMA vez por tick de 1/60s
    max_speed = 300,                -- Limite de velocidade máxima do jogador
    restitution = 0.5,              -- Elasticidade na colisão jogador x jogador
    kick_margin = 4,                -- Margem adicional de contato para chute
    kick_strength = 540,            -- Impulso radial instantâneo
    kick_player_speed_ratio = 0.0,  -- Inércia do jogador somada ao chute (padrão 0)
}

-- Física da Bola
config.ball = {
    radius = 10,
    mass = 1.0,                     -- Razão bola:jogador = 1:2
    damping = 0.99,                 -- Fator de atrito base aplicado UMA vez por tick de 1/60s
    wall_restitution = 0.5,         -- Elasticidade no impacto com paredes
    post_restitution = 0.8,         -- Elasticidade no impacto com traves
    player_restitution = 0.5,       -- Elasticidade no impacto com jogadores
    max_speed = 850,                -- Limite de velocidade máxima (previne tunelamento)
}

-- Mecânica de Curva (Spin estilo 8 Ball Pool)
config.spin = {
    max_turn_rate_per_tick = 0.020, -- Radianos por tick (~1.15 graus/tick a 60 FPS) no spinX máximo
    decay = 0.985,                  -- Decaimento do efeito por tick (x0.985)
    max_power_penalty = 0.15,       -- Perda de potência de até 15% nas bordas do círculo
    wall_damping = 0.5,             -- Amortecimento do spin na colisão com parede ou trave (x0.5)
    top_spin_factor = 0.006,        -- Redução do atrito para spinY > 0 (conserva velocidade)
    back_spin_factor = 0.018,       -- Aumento do atrito para spinY < 0 (bola morre mais rápido)
}

-- Seletor de Efeito (HUD)
config.spin_selector = {
    enabled = true,
    radius = 40,                    -- Raio do círculo grande
    cue_radius = 8,                 -- Raio do ponto interno
    move_speed = 2.0,               -- Velocidade de deslocamento pelas teclas (unidades por segundo)
    reset_key = "c",                -- Tecla de atalho para resetar o efeito ao centro
    local_keyboard_enabled = false, -- Desligado por padrão no teclado compartilhado (mouse sempre ativo)
}

-- Previsão de Trajetória
config.trajectory = {
    max_ticks = 120,                -- Até 120 ticks de previsão (~2 segundos de simulação)
    max_bounces = 2,                -- Até 2 quiques em parede ou trave
    step_stride = 2,                -- Desenha 1 a cada 2 pontos para pontilhado estético
}

-- Regras da Partida
config.game = {
    goal_reset_delay = 2.0,         -- Segundos de pausa pós-gol
}

-- Definição dos Jogadores (escalável para N jogadores, com suporte a comandos determinísticos)
config.players = {
    {
        id = "p1",
        name = "P1",
        team = "red",
        number = 1,
        color = {0.88, 0.22, 0.22},
        inner_color = {0.65, 0.15, 0.15},
        keys = { up = "w", down = "s", left = "a", right = "d", kick = "space" },
        spin_keys = { up = "t", down = "g", left = "f", right = "h", reset = "c" },
    },
    {
        id = "p2",
        name = "P2",
        team = "blue",
        number = 1,
        color = {0.22, 0.48, 0.88},
        inner_color = {0.15, 0.32, 0.65},
        keys = { up = "up", down = "down", left = "left", right = "right", kick = "rshift" },
        spin_keys = { up = "up", down = "down", left = "left", right = "right", reset = "delete" },
    },
    {
        id = "p3",
        name = "P3",
        team = "red",
        number = 2,
        color = {0.95, 0.40, 0.20},
        inner_color = {0.75, 0.22, 0.10},
        keys = { up = "i", down = "k", left = "j", right = "l", kick = "u" },
        spin_keys = { up = "home", down = "end", left = "delete", right = "pagedown", reset = "insert" },
    },
    {
        id = "p4",
        name = "P4",
        team = "blue",
        number = 2,
        color = {0.18, 0.70, 0.85},
        inner_color = {0.10, 0.48, 0.60},
        keys = {
            up = "kp8", down = "kp5", left = "kp4", right = "kp6", kick = "kp0",
            up_alt = "8", down_alt = "5", left_alt = "4", right_alt = "6", kick_alt = "0",
        },
        spin_keys = { up = "kp9", down = "kp3", left = "kp7", right = "kp1", reset = "kp." },
    },
}

-- Atalhos de controle global
config.keys = {
    reset = "r",
    quit = "escape",
    debug = "f3",
    fullscreen = "f11",
    cycle_preset = "f2",
    toggle_spin_keyboard = "f4",    -- Alterna controle de efeito pelo teclado local
}

-- Cores procedurais (RGB normalizado 0 a 1)
config.colors = {
    clear = {0.08, 0.10, 0.12},
    pitch = {0.31, 0.50, 0.31},
    pitch_border = {0.24, 0.40, 0.24},
    lines = {1.0, 1.0, 1.0, 0.75},
    goal_box = {0.25, 0.38, 0.25, 0.7},
    posts = {0.90, 0.90, 0.90},
    ball = {1.0, 1.0, 1.0},
    ball_outline = {0.15, 0.15, 0.15},
    kicking_glow = {1.0, 1.0, 1.0, 0.95},
    score_p1 = {0.95, 0.35, 0.35},
    score_p2 = {0.35, 0.65, 0.95},
    hud_text = {0.90, 0.90, 0.90},
    debug_bg = {0.0, 0.0, 0.0, 0.65},
    debug_text = {0.2, 1.0, 0.4},
    trajectory_dot = {1.0, 1.0, 0.3},     -- Amarelo claro para a linha de trajetória
    spin_widget_bg = {0.12, 0.14, 0.17, 0.85},
    spin_widget_circle = {0.92, 0.92, 0.92},
    spin_widget_dot = {0.90, 0.25, 0.25}, -- Ponto vermelho clássico de contato
    spin_widget_cross = {0.40, 0.45, 0.50, 0.6},
    spin_widget_btn = {0.22, 0.26, 0.32, 0.9},
}

return config

module settings;


immutable TITLE = "The Mission";
immutable SCREEN_W = 1024;
immutable SCREEN_H = 768;
immutable WORLD_DIM = 30; // Размерность поля
immutable _LC_OFST = 8; // Желаемый отступ левого угла комнаты от края экрана

immutable CELL_W = 2.0f / WORLD_DIM;
immutable CELL_HW = CELL_W / 2.0f;
immutable U_SIZE = CELL_HW * 0.66f;

immutable MAX_TIME_FRACT = 1.0f / 15;
immutable CHAR_B_SPEED = 2.0f / WORLD_DIM * 2.0f;
immutable ART_COUNT = 4;
immutable ART_B_SPEED = 2.0f / WORLD_DIM * 4.0f;
immutable ART_B_DELAY = 5.0f;
immutable ART_DEV = 0.5f;
immutable GUARD_B_SPEED = 2.0f / WORLD_DIM * 2.0f;
immutable LEVEL_COMPL = 0.2f;

immutable BANNER_TOUT = 3.0f;

immutable HYP2 = 2.828427125f;


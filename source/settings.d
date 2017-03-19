module settings;

const TITLE = "The Mission";
const SCREEN_W = 1024;
const SCREEN_H = 768;
const WORLD_DIM = 30; // Размерность поля
const _LC_OFST = 8; // Желаемый отступ левого угла комнаты от края экрана

const CELL_W = 2.0f / WORLD_DIM;
const CELL_HW = CELL_W / 2.0f;
const U_SIZE = CELL_HW * 0.66f;

const MAX_TIME_FRACT = 1.0f / 15;
const CHAR_B_SPEED = 2.0f / WORLD_DIM * 2.0f;
const ART_COUNT = 4;
const ART_B_SPEED = 2.0f / WORLD_DIM * 4.0f;
const ART_B_DELAY = 5.0f;
const ART_DEV = 0.5f;
const GUARD_B_SPEED = 2.0f / WORLD_DIM * 2.0f;
const LEVEL_COMPL = 0.2f;

const BANNER_TOUT = 3.0f;

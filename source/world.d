module mission.world;

import std.container.array;
import std.container.dlist;
import std.algorithm.comparison;
import std.random;
import std.math;
import mission.settings;
import mission.flagset;
import mission.pathfinding;
import mission.main;

////////////////////////////////////////////////////////////////////////////////
// Основные объекты

uint level = 0; // Текущий уровень, начиная с 0
GameState the_state; // Этап игры
Field the_field; // Игровое поле
UnitsList the_alives; // Активные объекты
Artillery the_artillery; // Все пушки
Character the_character; // Указатель на юнит главного героя, содержащийся в общем списке
SoundsQueue the_sounds; // Очередь звуков

private struct Reals2 {
    float x = 0.0f, y = 0.0f;
}

alias SpacePosition = Reals2;
alias Speed = Reals2;

// Состояние игры
enum GameState {
    INPROGRESS,
    LOSS,
    WIN
}

// Звуковое событие
enum SoundEvent {
    SHOT,
    HIT,
    LVLUP
}

alias SoundsQueue = DList!SoundEvent; // Очередь звуков

////////////////////////////////////////////////////////////////////////////////
// Клетка на игровом поле
struct Cell
{
    // Какие-либо атрибуты клетки
    enum Attribute {
        OBSTACLE, // Препятствие
        EXIT, // Зона выхода
        GUARDFORW, // Охране вперёд
        GUARDBACKW // Охране назад
    }

    alias Attributes = Set!Attribute;

    // Позиция на игровом поле
    struct Coordinates {
        int x, y;
    }

    Attributes attribs;

    this(Attributes attrs)
    {
        attribs = attrs;
    }
}

////////////////////////////////////////////////////////////////////////////////
// Игровое поле
final class Field
{
    Cell[WORLD_DIM][WORLD_DIM] cells;

    // Интерфейсный метод для AStar
    bool isobstacle(int x, int y) const
    { 
    	return Cell.Attribute.OBSTACLE in cells[y][x].attribs; 
    }

    static void cell_to_pos(out SpacePosition position, int x, int y)
    {
    	position.x = to_space_dim(x);
    	position.y = to_space_dim(y);
    }

    static void pos_to_cell(out int x, out int y, ref const SpacePosition position)
    {
    	float k = WORLD_DIM / 2.0f;
    	x = cast(int)floor((position.x + 1.0f) * k);
    	y = cast(int)floor((position.y + 1.0f) * k);
    }
}

alias Path = Array!(Cell.Coordinates); // Оптимальный путь между ячейками
alias FieldsAStar = AStar!(WORLD_DIM, WORLD_DIM, Cell.Coordinates, Field); // AStar, подогнанный к Field

////////////////////////////////////////////////////////////////////////////////
// Базовый класс игровых юнитов
class Unit
{
    // Спецификация юнита
    enum Type {
        Unit,      // Базовый тип
        Character, // Главный герой
        Guard,     // Стажник
        Fireball   // Выстрел
    }

    float size = U_SIZE;  // Радиус юнита
    SpacePosition position;  // Положение в двухмерном пространстве
    Speed speed; // Скорость перемещения

    Type id()
    {
        return Type.Unit;
    }

    // Столкнулись ли с другим юнитом
    final bool is_collided(const Unit unit)
    {
    	float a = position.x - unit.position.x;
	    float b = position.y - unit.position.y;
	    return sqrt(a * a + b * b) < size + unit.size;
    }

    // Осуществляем ход
    void move(float tdelta)
    {
    	position.x += speed.x * tdelta;
    	position.y += speed.y * tdelta;
    }
}

alias UnitsList = Array!Unit;

// Главный герой
final class Character : Unit
{
    // Характеристики пути к цели
    struct Target {
        Cell.Coordinates neighbour, target; // Ближайшая ячейка на пути и целевая
        SpacePosition neigpos; // Пространственные координаты центра ближайшей ячейки
        Path path; // Список директив смены направления
        uint stage; // Этап на пути
    }

    Target way; // Набор характеристик пути к цели
    bool path_requested; // Обсчитывается путь

    override Type id()
    {
        return Type.Character;
    }

    override void move(float tdelta)
    {
        int x, y;
        if (the_state == GameState.INPROGRESS)
            // Перемещаемся только во время игры
            super.move(tdelta);
        if (way.path.empty)
            return;
        if ((speed.x > 0.0f && position.x >= way.neigpos.x)
            || (speed.x < 0.0f && position.x <= way.neigpos.x)
            || (speed.y > 0.0f && position.y >= way.neigpos.y)
            || (speed.y < 0.0f && position.y <= way.neigpos.y))
        {
            // Этап завершен
            position = way.neigpos;
            if (way.stage >= way.path.length - 1)
            {
                // Цель достигнута
                way.path.clear();
                way.stage = 0;
                Field.pos_to_cell(x, y, position);
                way.target.x = x;
                way.target.y = y;
            }
            else
            {
                // Следующий этап
                Field.pos_to_cell(x, y, position);
                ++way.stage;
                auto delta = way.path[way.path.length - way.stage - 1];
                way.neighbour.x += delta.x;
                way.neighbour.y += delta.y;
                Field.cell_to_pos(way.neigpos, way.neighbour.x, way.neighbour.y);
            }
            set_speed();
        }
    }

    // Устанавливает скорость
    void set_speed()
    {
        if (way.path.empty)
        {
            speed.x = 0.0f;
            speed.y = 0.0f;
            return;
        }
        auto dx = way.neigpos.x - position.x;
        auto dy = way.neigpos.y - position.y;
        auto adx = fabs(dx);
        auto ady = fabs(dy);
        if ((adx < typeof(adx).epsilon && ady < typeof(ady).epsilon) || way.path.empty)
            return;
        if (adx > ady)
        {
            auto a = atan(ady / adx);
            speed.x = copysign(CHAR_B_SPEED * cos(a), dx);
            speed.y = copysign(CHAR_B_SPEED * sin(a), dy);
        }
        else
        {
            auto a = atan(adx / ady);
            speed.x = copysign(CHAR_B_SPEED * sin(a), dx);
            speed.y = copysign(CHAR_B_SPEED * cos(a), dy);
        }
    }

    // Запрос обсчета пути
    void way_new_request(int tx, int ty)
    {
        int x, y;
        speed.x = 0.0f;
        speed.y = 0.0f;
        Field.pos_to_cell(x, y, position);
        way.target.x = tx;
        way.target.y = ty;
        the_coworker.path_find_request(the_field, x, y, tx, ty);
        path_requested = true;
    }

    // Обработка рассчитанного пути
    void way_new_process()
    {
        Cell.Coordinates delta;
        int x, y;
        way.path = the_coworker.path;
        Field.pos_to_cell(x, y, position);
        if (!way.path.empty)
        {
            way.stage = 0;
            delta = way.path[way.path.length - 1];
            way.neighbour.x = x + delta.x;
            way.neighbour.y = y + delta.y;
            Field.cell_to_pos(way.neigpos, way.neighbour.x, way.neighbour.y);
        }
        set_speed();
    }
}

// Стажник
final class Guard : Unit
{
    override Type id()
    {
        return Type.Guard;
    }

    override void move(float tdelta)
    {
        int x, y;
        super.move(tdelta);
        Field.pos_to_cell(x, y, position);
        if (Cell.Attribute.GUARDBACKW in the_field.cells[y][x].attribs)
            speed.x = -fabs(speed.x);
        if (Cell.Attribute.GUARDFORW in the_field.cells[y][x].attribs)
            speed.x = fabs(speed.x);
    }
}

// Выстрел
final class Fireball : Unit 
{
    override Type id()
    {
        return Type.Fireball;
    } 
}

////////////////////////////////////////////////////////////////////////////////
// Пушки
final class Artillery
{
    // Настройки ведения огня
    struct Setting {
        Cell.Coordinates position;
        Speed speed;
        float delay;
        float timeout;
    }

    alias Settings = Array!Setting;

    Settings setting; // Все пушки артбатареи
}

////////////////////////////////////////////////////////////////////////////////
// Инициализация вселенной
void world_setup()
{
    lists_clear();

    // Размечаем поле
    for (int y = 0; y < WORLD_DIM; y++)
        for (int x = 0; x < WORLD_DIM; x++)
            the_field.cells[y][x].attribs.clear();
    the_field.cells[0][WORLD_DIM - 1].attribs |= Cell.Attribute.EXIT; // Позиция выхода
    the_field.cells[2][0].attribs |= Cell.Attribute.GUARDFORW; // Вешка направления движения охраны
    the_field.cells[2][WORLD_DIM - 1].attribs |= Cell.Attribute.GUARDBACKW; // Вешка направления движения охраны
    // Главный герой
    the_character = new Character();
    the_alives.insert(the_character);
    Field.cell_to_pos(the_character.position, 0, WORLD_DIM - 1);
    the_character.way.target.x = 0;
    the_character.way.target.y = WORLD_DIM - 1;
    the_character.set_speed();
    // Стража
    Unit unit = new Guard();
    the_alives.insert(unit);
    Field.cell_to_pos(unit.position, 0, 2);
    unit.size = U_SIZE * 1.5f;
    unit.speed.x = GUARD_B_SPEED;
    unit.speed.y = 0.0f;
    // Артиллерия
    Artillery.Setting[WORLD_DIM * 2 - 2] apositions;
    for (int i = 0; i < WORLD_DIM - 1; i++)
    {
        apositions[i].position.x = i;
        apositions[i].position.y = 0;
        apositions[i].speed.x = 0.0f;
        apositions[i].speed.y = deviation_apply(ART_B_SPEED, ART_DEV);
        apositions[i].delay = deviation_apply(ART_B_DELAY, ART_DEV);
        apositions[i].timeout = 0.0f;
        apositions[WORLD_DIM - 1 + i].position.x = 0;
        apositions[WORLD_DIM - 1 + i].position.y = i;
        apositions[WORLD_DIM - 1 + i].speed.x = deviation_apply(complexity_apply(ART_B_SPEED, LEVEL_COMPL), ART_DEV);
        apositions[WORLD_DIM - 1 + i].speed.y = 0.0f;
        apositions[WORLD_DIM - 1 + i].delay = deviation_apply(ART_B_DELAY, ART_DEV);
        apositions[WORLD_DIM - 1 + i].timeout = 0.0f;
    }
    randomShuffle(apositions[]);
    auto acount = min(complexity_apply(ART_COUNT, LEVEL_COMPL), apositions.length);
    foreach (ref pos; apositions[0..acount])
    {
        the_artillery.setting.insert(pos);
    }
}

// Изменения в состоянии мира за отведённый квант времени
void move_do(float tdelta)
{
    Unit unit;
    // Перемещаем существующие юниты и удаляем отжившие
    for (int i = 0; i < the_alives.length; ++i)
    {
        unit = the_alives[i];
        unit.move(tdelta);
        if (unit.position.x > 1.0f || unit.position.x < -1.0f 
            || unit.position.y > 1.0f || unit.position.y < -1.0f)
            the_alives.linearRemove(the_alives[i..i+1]);
    }
    // Генерируем новые выстрелы
    foreach (ref aset; the_artillery.setting)
    {
        aset.timeout -= tdelta;
        if (aset.timeout <= 0.0f)
        {
            aset.timeout = aset.delay;
            unit = new Fireball();
            the_alives.insert(unit);
            Field.cell_to_pos(unit.position, aset.position.x, aset.position.y);
            if (aset.speed.x > 0.0f)
                unit.position.x -= CELL_HW;
            else
                unit.position.y -= CELL_HW;
            unit.size = U_SIZE;
            unit.speed = aset.speed;
            the_sounds.insert(SoundEvent.SHOT);
        }
    }
}

// Проверка состояния игры
void state_check()
{
    int x, y;
    Field.pos_to_cell(x, y, the_character.position);
    if (Cell.Attribute.EXIT in the_field.cells[y][x].attribs)
    {
        the_state = GameState.WIN;
        return;
    }
    foreach (unit; the_alives)
    {
        if (unit is the_character)
            continue;
        if (the_character.is_collided(unit))
        {
            the_state = GameState.LOSS;
            return;
        }
    }
}

// Очистка всех списков
void lists_clear()
{
    the_alives.clear();
    the_alives.clear();
    the_artillery.setting.clear();
    the_sounds.clear();
}

float to_space_dim(int v)
{
    return cast(float)(v + 1) / WORLD_DIM * 2.0f - CELL_HW - 1.0f;
}

private float deviation_apply(float val, float dev)
{
    return (2 * dev * uniform(0.0f, 1.0f) - dev + 1) * val;
}

private int complexity_apply(int val, float kc)
{
    return val + cast(int)(round(val * level * kc));
}

private float complexity_apply(float val, float kc)
{
    return val + val * level * kc;
}


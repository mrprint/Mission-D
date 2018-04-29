module world;

import std.container.array;
import std.container.dlist;
import std.algorithm.comparison;
import std.random;
import std.math;
import lmath.matrix;
import lmath.spatial;
import settings;
import flagset;
import pathfinding;
import main;

////////////////////////////////////////////////////////////////////////////////
// Использующиеся системы координат

alias SpacePosition = Point!(float, 2, MatrixF3().ldIdentity());
alias ScreenPosition = Point!(float, 2, MatrixF3().ldIdentity.rotate(PI_4)
        .translate(HYP2 / 2, HYP2 / 2));
alias DeskPosition = Point!(int, 2, MatrixF3().ldIdentity.translate(1.0, 1.0)
        .scale(WORLD_DIM / 2, WORLD_DIM / 2));

////////////////////////////////////////////////////////////////////////////////
// Основные объекты

uint level = 0; // Текущий уровень, начиная с 0
GameState the_state; // Этап игры
Field the_field; // Игровое поле
UnitsList the_alives; // Активные объекты
Artillery the_artillery; // Все пушки
Character the_character; // Указатель на юнит главного героя, содержащийся в общем списке
SoundsQueue the_sounds; // Очередь звуков

alias Speed = SpacePosition;

// Состояние игры
enum GameState
{
    INPROGRESS,
    LOSS,
    WIN
}

// Звуковое событие
enum SoundEvent
{
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
    enum Attribute
    {
        OBSTACLE, // Препятствие
        EXIT, // Зона выхода
        GUARDFORW, // Охране вперёд
        GUARDBACKW // Охране назад
    }

    alias Attributes = Set!Attribute;

    DeskPosition coordinates;
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
}

alias Path = Array!(DeskPosition); // Оптимальный путь между ячейками
alias FieldsAStar = AStar!(WORLD_DIM, WORLD_DIM, DeskPosition, Field); // AStar, подогнанный к Field

////////////////////////////////////////////////////////////////////////////////
// Базовый класс игровых юнитов
class Unit
{
    // Спецификация юнита
    enum Type
    {
        Unit, // Базовый тип
        Character, // Главный герой
        Guard, // Стажник
        Fireball // Выстрел
    }

    float size = U_SIZE; // Радиус юнита
    SpacePosition position; // Положение в двухмерном пространстве
    Speed speed; // Скорость перемещения

    Type id()
    {
        return Type.Unit;
    }

    // Столкнулись ли с другим юнитом
    final bool is_collided(const Unit unit)
    {
        immutable t = position - unit.position;
        return t.x * t.x + t.y * t.y < size * size + unit.size * unit.size;
    }

    // Осуществляем ход
    void move(float tdelta)
    {
        position += speed * tdelta;
    }
}

alias UnitsList = Array!Unit;

// Главный герой
final class Character : Unit
{
    // Характеристики пути к цели
    struct Target
    {
        DeskPosition neighbour, target; // Ближайшая ячейка на пути и целевая
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
        if (the_state == GameState.INPROGRESS) // Перемещаемся только во время игры
            super.move(tdelta);
        if (way.path.empty)
            return;
        if ((speed.x > 0.0 && position.x >= way.neigpos.x) || (speed.x < 0.0
                && position.x <= way.neigpos.x) || (speed.y > 0.0
                && position.y >= way.neigpos.y) || (speed.y < 0.0 && position.y <= way.neigpos.y))
        {
            // Этап завершен
            if (way.stage + 1 >= way.path.length)
            {
                // Цель достигнута
                way.path.clear();
                way.stage = 0;
                way.target = way.neigpos;
            }
            else
            {
                // Следующий этап
                ++way.stage;
                way.neighbour += way.path[way.path.length - way.stage - 1];
                way.neigpos = way.neighbour;
            }
            set_speed();
        }
    }

    // Устанавливает скорость
    void set_speed()
    {
        if (way.path.empty)
        {
            speed = Speed([0.0, 0.0]);
            return;
        }
        auto d = way.neigpos - position;
        if (d.atzero())
        {
            speed = Speed([0.0, 0.0]);
            return;
        }
        speed = d.normalized() * CHAR_B_SPEED;
    }

    // Запрос обсчета пути
    void way_new_request(ref in DeskPosition pos)
    {
        speed = Speed([0.0, 0.0]);
        way.target = pos;
        the_coworker.path_find_request(the_field, DeskPosition(position), pos);
        path_requested = true;
    }

    // Обработка рассчитанного пути
    void way_new_process()
    {
        way.path = the_coworker.path;
        if (!way.path.empty)
        {
            way.stage = 0;
            way.neighbour = DeskPosition(position) + way.path[way.path.length - 1];
            way.neigpos = way.neighbour;
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
        super.move(tdelta);
        immutable dp = DeskPosition(position);
        if (Cell.Attribute.GUARDBACKW in the_field.cells[dp.y][dp.x].attribs)
            speed.x = -fabs(speed.x);
        if (Cell.Attribute.GUARDFORW in the_field.cells[dp.y][dp.x].attribs)
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
    struct Setting
    {
        DeskPosition position;
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
    foreach (y; 0 .. WORLD_DIM)
        foreach (x; 0 .. WORLD_DIM)
            the_field.cells[y][x].attribs.clear();
    the_field.cells[0][WORLD_DIM - 1].attribs |= Cell.Attribute.EXIT; // Позиция выхода
    the_field.cells[2][0].attribs |= Cell.Attribute.GUARDFORW; // Вешка направления движения охраны
    the_field.cells[2][WORLD_DIM - 1].attribs |= Cell.Attribute.GUARDBACKW; // Вешка направления движения охраны
    // Главный герой
    the_character = new Character();
    the_alives.insert(the_character);
    the_character.position = DeskPosition([0, WORLD_DIM - 1]);
    the_character.way.target = DeskPosition([0, WORLD_DIM - 1]);
    the_character.set_speed();
    // Стража
    Unit unit = new Guard();
    the_alives.insert(unit);
    unit.position = DeskPosition([0, 2]);
    unit.size = U_SIZE * 1.5;
    unit.speed = Speed([GUARD_B_SPEED, 0.0]);
    // Артиллерия
    Artillery.Setting[WORLD_DIM * 2 - 2] apositions;
    foreach (i; 0 ..WORLD_DIM - 1)
    {
        apositions[i].position = DeskPosition([i, 0]);
        apositions[i].speed = Speed([0.0, deviation_apply(ART_B_SPEED, ART_DEV)]),
            apositions[i].delay = deviation_apply(ART_B_DELAY, ART_DEV);
        apositions[i].timeout = 0.0;
        apositions[WORLD_DIM - 1 + i].position = DeskPosition([0, i]);
        apositions[WORLD_DIM - 1 + i].speed = Speed([deviation_apply(complexity_apply(ART_B_SPEED,
                LEVEL_COMPL), ART_DEV), 0.0]);
        apositions[WORLD_DIM - 1 + i].delay = deviation_apply(ART_B_DELAY, ART_DEV);
        apositions[WORLD_DIM - 1 + i].timeout = 0.0;
    }
    randomShuffle(apositions[]);
    auto acount = min(complexity_apply(ART_COUNT, LEVEL_COMPL), apositions.length);
    foreach (ref pos; apositions[0 .. acount])
    {
        the_artillery.setting.insert(pos);
    }
}

// Изменения в состоянии мира за отведённый квант времени
void move_do(float tdelta)
{
    Unit unit;
    // Перемещаем существующие юниты и удаляем отжившие
    for (int i; i < the_alives.length; ++i)
    {
        unit = the_alives[i];
        unit.move(tdelta);
        if (unit.position.x > 1.0 || unit.position.x < -1.0
                || unit.position.y > 1.0 || unit.position.y < -1.0)
            the_alives.linearRemove(the_alives[i .. i + 1]);
    }
    // Генерируем новые выстрелы
    foreach (ref aset; the_artillery.setting)
    {
        aset.timeout -= tdelta;
        if (aset.timeout <= 0.0)
        {
            aset.timeout = aset.delay;
            unit = new Fireball();
            the_alives.insert(unit);
            unit.position = aset.position;
            if (aset.speed.x > 0.0)
                unit.position.x = unit.position.x - CELL_HW;
            else
                unit.position.y = unit.position.y - CELL_HW;
            unit.size = U_SIZE;
            unit.speed = aset.speed;
            the_sounds.insert(SoundEvent.SHOT);
        }
    }
}

// Проверка состояния игры
void state_check()
{
    immutable dp = DeskPosition(the_character.position);
    if (Cell.Attribute.EXIT in the_field.cells[dp.y][dp.x].attribs)
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

private float deviation_apply(float val, float dev)
{
    return (2 * dev * uniform(0.0, 1.0) - dev + 1) * val;
}

private int complexity_apply(int val, float kc)
{
    return val + cast(int)(round(val * level * kc));
}

private float complexity_apply(float val, float kc)
{
    return val + val * level * kc;
}

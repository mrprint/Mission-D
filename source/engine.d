module engine;

import std.container.array;
import std.container.dlist;
import std.algorithm.sorting;
import std.math;
import std.format;
import std.traits;
import derelict.sfml2.system;
import derelict.sfml2.window;
import derelict.sfml2.audio;
import derelict.sfml2.graphics;
import lmath.matrix;
import settings;
import flagset;
import world;
import main;

immutable BKG_SIZE = 1024.0f;
immutable SPR_SIZE = 128.0f;
immutable TILE_HOT = SPR_SIZE * 0.75f;
immutable TEXT_COLOR = 0xFF0010FF;
immutable RES_DIR = "resources/";

final class Engine
{

    enum ControlState
    {
        LMBUTTON,
        RMBUTTON
    }

    enum TextureIndexes
    {
        BKG = 0,
        SPR
    }

    enum SpriteIndexes
    {
        BKG = 0,
        TILE,
        LWALL,
        RWALL,
        LBATT,
        RBATT,
        FBALL,
        EXIT,
        LGUARD,
        RGUARD,
        CHAR,
        CHART
    }

    enum SoundIndexes
    {
        SHOT = 0,
        HIT,
        LUP
    }

    // Юнит с рассчитанным расположением на экране
    struct ScreenPos
    {
        ScreenPosition pos;
        Unit unit;
        alias pos this;
    }

    alias ScreenPositions = Array!ScreenPos;

    sfRenderWindow* window;
    DrawingSizes sizes;

    sfFont* font;
    TextureInfo[] textures;
    SpriteInfo[] sprites;
    SoundInfo[] sounds;

    bool windowed = true;
    Set!ControlState controls;
    ScreenPosition mouse_p;
    Orchestre played_sounds;
    float banner_timeout;

    this()
    {
        banner_timeout = 0.0;
        textures = [TextureInfo("skybkg.png"), TextureInfo("sprites.png")];
        sprites = [SpriteInfo(textures[TextureIndexes.BKG], 0, 0, 1024, 1024,
                0, 0, BKG_SIZE / 2, BKG_SIZE / 2), SpriteInfo(textures[TextureIndexes.SPR], 130,
                0, 128, 64, 0, 64, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 380,
                77, 63, 96, 0, 0, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 445,
                77, 65, 97, 63, 0, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 232,
                66, 24, 47, 20, 25, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 468,
                0, 23, 50, 82, 22, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 0,
                0, 128, 128, 0, 0, SPR_SIZE / 2, SPR_SIZE), SpriteInfo(textures[TextureIndexes.SPR], 0,
                130, 66, 35, 29, 77, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 130, 66,
                100, 72, 11, 47, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 364, 0,
                102, 75, 18, 44, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR], 290,
                109, 88, 91, 19, 16, SPR_SIZE / 2, TILE_HOT), SpriteInfo(textures[TextureIndexes.SPR],
                260, 0, 102, 107, 5, 0, SPR_SIZE / 2, TILE_HOT)];
        sounds = [SoundInfo("shot.wav"), SoundInfo("hit.wav"), SoundInfo("gong.wav")];
        windowed = true;
    }

    ~this()
    {
        if (window)
            window.sfRenderWindow_destroy();
    }

    void work_do()
    {
        if (!init())
            return;

        main_loop();
    }

    private bool init()
    {
        videomode_set(windowed);
        if (!(window && window.sfRenderWindow_isOpen()))
            return false;

        foreach (ref texture; textures)
        {
            if (!texture.init())
                return false;
        }
        foreach (ref sprite; sprites)
        {
            if (!sprite.init())
                return false;
        }
        foreach (ref sound; sounds)
        {
            if (!sound.init())
                return false;
        }

        font = sfFont_createFromFile(cast(char*)(RES_DIR ~ "Orbitron Medium.ttf"));
        if (!font)
            return false;

        return true;
    }

    private void videomode_set(bool _windowed)
    {
        sfVideoMode mode;
        sfUint32 style;
        if (window)
            window.sfRenderWindow_close();
        if (_windowed)
        {
            mode = sfVideoMode(SCREEN_W, SCREEN_H);
            style = sfTitlebar | sfClose;
            window = sfRenderWindow_create(mode, cast(char*) TITLE, style, null);
            window.sfRenderWindow_setFramerateLimit(60);
        }
        else
        {
            mode = sfVideoMode_getDesktopMode();
            style = sfFullscreen;
            window = sfRenderWindow_create(mode, cast(char*) TITLE, style, null);
            window.sfRenderWindow_setVerticalSyncEnabled(true);
            // Обход SFML's bug #921
            auto view = sfView_createFromRect(sfFloatRect(0.0, 0.0, mode.width, mode.height));
            window.sfRenderWindow_setView(view);
            view.sfView_destroy();
        }
        windowed = _windowed;
        sizes.screen_w = mode.width;
        sizes.screen_h = mode.height;

        immutable tile_w = (sizes.screen_w - (_LC_OFST * 2)) / WORLD_DIM - (
                (sizes.screen_w - (_LC_OFST * 2)) / WORLD_DIM) % 2;
        immutable tile_h = tile_w / 2;
        sizes.room_w = tile_w * WORLD_DIM;
        sizes.room_h = tile_h * WORLD_DIM;
        sizes.lc_ofst = (sizes.screen_w - sizes.room_w) / 2;
        sizes.tc_ofst = (sizes.screen_h - sizes.room_h) / 2;
        sizes.spr_scale = tile_w / SPR_SIZE;
        sizes.bkg_scale = ((sizes.screen_w > sizes.screen_h) ? sizes.screen_w
                : sizes.screen_h) / BKG_SIZE;
        ScreenPosition.adjust!SpacePosition(MatrixF3().ldIdentity.scale(sizes.room_w / HYP2,
                sizes.room_h / HYP2).translate(sizes.lc_ofst, sizes.tc_ofst));
        ScreenPosition.adjust!DeskPosition();
    }

    private void main_loop()
    {
        auto clock = sfClock_create();
        while (window.sfRenderWindow_isOpen())
        {
            input_process();
            update(clock.sfClock_restart());
            frame_render();
        }
    }

    private void frame_render()
    {
        sprite_draw(sprites[SpriteIndexes.BKG].sprite,
                ScreenPosition([sizes.screen_w / 2, sizes.screen_h / 2]), sizes.bkg_scale);
        field_draw();
        // Отображаем игровую информацию
        text_print(ScreenPosition([sizes.lc_ofst, sizes.lc_ofst]), TEXT_COLOR,
                format("Level %d", level + 1));
        switch (the_state)
        {
        default:
            break;
        case GameState.LOSS:
            text_print(ScreenPosition([cast(float) sizes.screen_w / 2,
                    cast(float) sizes.screen_h / 2]), TEXT_COLOR, "YOU LOSS!", true); // Запомнилось из какой-то древней игрушки
            break;
        case GameState.WIN:
            text_print(ScreenPosition([cast(float) sizes.screen_w / 2,
                    cast(float) sizes.screen_h / 2]), TEXT_COLOR, "LEVEL UP!", true);
            break;
        }
        window.sfRenderWindow_display();
    }

    private void input_process()
    {
        sfEvent evt;
        bool do_close;
        bool chmode;

        if (!window.sfRenderWindow_isOpen())
            return;
        while (window.sfRenderWindow_pollEvent(&evt))
        {
            switch (evt.type)
            {
            default:
                break;
            case sfEvtClosed:
                do_close = true;
                break;
            case sfEvtKeyPressed:
                switch (evt.key.code)
                {
                default:
                    break;
                case sfKeyEscape:
                    do_close = true;
                    break;
                case sfKeyF11:
                    chmode = true;
                    break;
                }
                break;
            case sfEvtMouseButtonPressed:
                mouse_p = ScreenPosition([evt.mouseButton.x, evt.mouseButton.y]);
                switch (evt.mouseButton.button)
                {
                default:
                    break;
                case sfMouseLeft:
                    controls |= ControlState.LMBUTTON;
                    break;
                case sfMouseRight:
                    controls |= ControlState.RMBUTTON;
                    break;
                }
                break;
            case sfEvtMouseButtonReleased:
                mouse_p = ScreenPosition([evt.mouseButton.x, evt.mouseButton.y]);
                switch (evt.mouseButton.button)
                {
                default:
                    break;
                case sfMouseLeft:
                    controls ~= ControlState.LMBUTTON;
                    break;
                case sfMouseRight:
                    controls ~= ControlState.RMBUTTON;
                    break;
                }
                break;
            }
        }
        if (chmode)
            videomode_set(!windowed);
        if (do_close)
            window.sfRenderWindow_close();
    }

    private void update(sfTime tdelta)
    {
        // Для антифликинга
        static bool lb_down;
        static bool rb_down;

        if (!window.sfRenderWindow_isOpen())
            return;
        float dt = tdelta.sfTime_asSeconds();
        if (dt > MAX_TIME_FRACT)
            dt = MAX_TIME_FRACT; // Замедляем время, если машина не успевает считать

        if (the_state != GameState.INPROGRESS)
        {
            // Обработка таймаута вывода баннеров выигрыша/поражения
            if (banner_timeout > 0.0)
            {
                banner_timeout -= dt;
                if (banner_timeout <= 0.0)
                {
                    // Снимаем баннер и настраиваем уровень
                    the_state = GameState.INPROGRESS;
                    world_setup();
                }
            }
            else
            {
                // Показываем баннер и выполняем базовые настройки при смене состояния
                banner_timeout = BANNER_TOUT;
                switch (the_state)
                {
                default:
                    break;
                case GameState.LOSS:
                    the_sounds.insert(SoundEvent.HIT);
                    level = 0;
                    break;
                case GameState.WIN:
                    the_sounds.insert(SoundEvent.LVLUP);
                    ++level;
                    break;
                }
            }
        }
        else
        {
            state_check(); // Оцениваем состояние игры
        }

        if (ControlState.LMBUTTON in controls && the_state == GameState.INPROGRESS)
        {
            if (!the_character.path_requested && the_coworker.ready && !lb_down)
            {
                // Будем идти в указанную позицию
                path_change(DeskPosition(mouse_p));
                lb_down = true;
            }
        }
        else
            lb_down = false;
        if (ControlState.RMBUTTON in controls && the_state == GameState.INPROGRESS)
        {

            if (!the_character.path_requested && the_coworker.ready && !rb_down)
            {
                // Пытаемся изменить состояние ячейки "свободна"/"препятствие"
                if (cell_flip(DeskPosition(mouse_p)))
                {
                    // При необходимости обсчитываем изменения пути
                    if (the_character.way.path.length > 0)
                        the_character.way_new_request(the_character.way.target);
                }
                rb_down = true;
            }
        }
        else
            rb_down = false;
        if (the_character.path_requested && the_coworker.ready)
        {
            the_character.path_requested = false;
            the_character.way_new_process();
        }
        move_do(dt); // Рассчитываем изменения
        sounds_play(); // Воспроизводим звуки
    }

    private void sprite_draw(sfSprite* spr, ScreenPosition pos, float scale)
    {
        spr.sfSprite_setPosition(to!sfVector2f(pos));
        spr.sfSprite_setScale(sfVector2f(scale, scale));
        window.sfRenderWindow_drawSprite(spr, null);
    }

    // Отрисовка игрового поля
    private void field_draw()
    {
        // Рисуем пол
        foreach (y; 0 .. WORLD_DIM)
        {
            foreach (x; 0 .. WORLD_DIM)
            {
                if (Cell.Attribute.OBSTACLE !in the_field.cells[y][x].attribs)
                    sprite_draw(sprites[SpriteIndexes.TILE].sprite,
                            ScreenPosition(DeskPosition([x, y])), sizes.spr_scale);
                if (Cell.Attribute.EXIT in the_field.cells[y][x].attribs)
                    sprite_draw(sprites[SpriteIndexes.EXIT].sprite,
                            ScreenPosition(DeskPosition([x, y])), sizes.spr_scale);
            }
        }
        // Рисуем стены
        foreach (i; 0 .. WORLD_DIM)
        {
            sprite_draw(sprites[SpriteIndexes.RWALL].sprite,
                    ScreenPosition(DeskPosition([i, 0])), sizes.spr_scale);
            sprite_draw(sprites[SpriteIndexes.LWALL].sprite,
                    ScreenPosition(DeskPosition([0, i])), sizes.spr_scale);
        }
        // Рисуем пушки
        foreach (ref aset; the_artillery.setting)
        {
            if (fabs(aset.speed.x) < float.epsilon)
                sprite_draw(sprites[SpriteIndexes.RBATT].sprite,
                        ScreenPosition(aset.position), sizes.spr_scale);
            else
                sprite_draw(sprites[SpriteIndexes.LBATT].sprite,
                        ScreenPosition(aset.position), sizes.spr_scale);
        }
        // Заполняем список юнитов с их экранными координатами
        ScreenPositions positions;
        foreach (unit; the_alives)
        {
            ScreenPos up = {unit.position, unit};
            positions.insert(up);
        }
        sort!("a.y < b.y")(positions[]); // Сортируем по экранному y
        // Рисуем юниты от дальних к ближним
        foreach (upos; positions)
        {
            switch (upos.unit.id())
            {
            default:
                break;
            case Unit.Type.Character:
                if (the_character.path_requested)
                    sprite_draw(
                            sprites[SpriteIndexes.CHART].sprite, upos, sizes.spr_scale);
                else
                    sprite_draw(sprites[SpriteIndexes.CHAR].sprite, upos, sizes.spr_scale);
                break;
            case Unit.Type.Fireball:
                sprite_draw(sprites[SpriteIndexes.FBALL].sprite,
                        upos, sizes.spr_scale * 0.5);
                break;
            case Unit.Type.Guard:
                sprite_draw(sprites[upos.unit.speed.x >= 0.0
                        ? SpriteIndexes.RGUARD : SpriteIndexes.LGUARD].sprite,
                        upos, sizes.spr_scale);
            }
        }
    }

    // Изменение состояния указанной мышкой ячейки
    private bool cell_flip(DeskPosition md)
    {
        immutable dp = DeskPosition(the_character.position);
        if (md.x < 0 || md.x >= WORLD_DIM || md.y < 0 || md.y >= WORLD_DIM || md == dp)
            return false;
        if (Cell.Attribute.OBSTACLE in the_field.cells[md.y][md.x].attribs)
            the_field.cells[md.y][md.x].attribs ~= Cell.Attribute.OBSTACLE;
        else
            the_field.cells[md.y][md.x].attribs |= Cell.Attribute.OBSTACLE;
        return true;
    }

    // Ищем новый путь
    private void path_change(DeskPosition md)
    {
        if (md.x < 0 || md.x >= WORLD_DIM || md.y < 0 || md.y >= WORLD_DIM)
            return;
        the_character.way_new_request(md);
    }

    private void sounds_play()
    {
        played_sounds.update();
        while (!the_sounds.empty)
        {
            switch (the_sounds.front)
            {
            default:
                break;
            case SoundEvent.SHOT:
                played_sounds.play(sounds[SoundIndexes.SHOT].buffer);
                break;
            case SoundEvent.HIT:
                played_sounds.play(sounds[SoundIndexes.HIT].buffer);
                break;
            case SoundEvent.LVLUP:
                played_sounds.play(sounds[SoundIndexes.LUP].buffer);
                break;
            }
            the_sounds.removeFront();
        }
    }

    private void text_print(ScreenPosition pos, uint color, string str, bool centered = false)
    {
        auto text = sfText_create();
        text.sfText_setFont(font);
        text.sfText_setCharacterSize(24);
        text.sfText_setColor(sfColor_fromInteger(color));
        text.sfText_setString(cast(char*) str);
        if (centered)
        {
            sfFloatRect bounds = text.sfText_getLocalBounds();
            text.sfText_setOrigin(sfVector2f(bounds.width / 2.0, bounds.height / 2.0));
        }
        else
            text.sfText_setOrigin(sfVector2f(0.0, 0.0));
        text.sfText_setPosition(to!sfVector2f(pos));
        window.sfRenderWindow_drawText(text, null);
        text.sfText_destroy();
    }

    static auto to(Type)(ref in ScreenPosition pos)
            if (allSameType!(sfVector2f, Type))
    {
        return sfVector2f(pos.x, pos.y);
    }
}

// Вся информация о текстуре и её инициализации
private struct TextureInfo
{
    string source;
    sfTexture* texture;

    this(string _source)
    {
        source = _source;
    }

    ~this()
    {
        if (texture)
            texture.sfTexture_destroy();
    }

    bool init()
    {
        texture = sfTexture_createFromFile(cast(char*)(RES_DIR ~ source), null);
        if (!texture)
            return false;
        texture.sfTexture_setSmooth(true);
        return true;
    }
}

// Вся информация о спрайте и его инициализации
private struct SpriteInfo
{
    const TextureInfo* texture;
    sfIntRect txrect;
    sfVector2u offset;
    sfVector2f spot;
    sfSprite* sprite;

    this(ref const TextureInfo _texture, int txx, int txy, int txw, int txh, uint ofsx,
            uint ofsy, float spx, float spy)
    {
        texture = &_texture;
        txrect = sfIntRect(txx, txy, txw, txh);
        offset = sfVector2u(ofsx, ofsy);
        spot = sfVector2f(spx, spy);
    }

    ~this()
    {
        if (sprite)
            sprite.sfSprite_destroy();
    }

    bool init()
    {
        sprite = sfSprite_create();
        sprite.sfSprite_setTexture(texture.texture, false);
        sprite.sfSprite_setTextureRect(txrect);
        sprite.sfSprite_setOrigin(sfVector2f(spot.x - offset.x, spot.y - offset.y));
        return true;
    }
}

// Вся информация о звуке и его инициализации
private struct SoundInfo
{
    string source;
    sfSoundBuffer* buffer;

    this(string _source)
    {
        source = _source;
    }

    ~this()
    {
        if (buffer)
            buffer.sfSoundBuffer_destroy();
    }

    bool init()
    {
        buffer = sfSoundBuffer_createFromFile(cast(char*)(RES_DIR ~ source));
        if (!buffer)
            return false;
        return true;
    }
}

// Воспроизводящиеся звуки
private struct Orchestre
{
    DList!(sfSound*) sounds;
    int count;

    ~this()
    {
        foreach (sound; sounds)
        {
            sound.sfSound_destroy();
        }
    }

    void play(const sfSoundBuffer* buffer)
    {
        if (count >= 256) // Максимально допустимое количество звуков в SFML
            return;
        auto s_entity = sfSound_create();
        s_entity.sfSound_setBuffer(buffer);
        s_entity.sfSound_play();
        sounds.insert(s_entity);
        ++count;
    }

    void update()
    {
        while (!sounds.empty && sounds.front.sfSound_getStatus() == sfStopped)
        {
            sounds.front.sfSound_destroy();
            sounds.removeFront();
            --count;
        }
    }
}

private struct DrawingSizes
{
    float spr_scale;
    float bkg_scale;
    int screen_w;
    int screen_h;
    int room_w;
    int room_h;
    int lc_ofst; // Реальный отступ левого угла комнаты от края экрана
    int tc_ofst; // Отступ верхнего угла комнаты от края экрана
}

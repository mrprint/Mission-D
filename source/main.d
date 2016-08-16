module mission.main;

import std.concurrency;
import derelict.sfml2.system;
import derelict.sfml2.window;
import derelict.sfml2.audio;
import derelict.sfml2.graphics;
import mission.engine;
import mission.flagset;
import mission.world;
import mission.pathfinding;

Coworker the_coworker;

private struct SharedData {
    Field field;
    Path path;
    bool ready = true;
}

private __gshared SharedData shared_data;

void main(string[] args)
{
    sfml_load();
    auto engine = new Engine();
    the_field = new Field();
    the_artillery = new Artillery();
    the_state = GameState.INPROGRESS;
    level = 0;
    the_coworker.start();
    world_setup();
    engine.work_do();
    the_coworker.stop();
}

private void sfml_load()
{
    DerelictSFML2System.load();
    DerelictSFML2Window.load();
    DerelictSFML2Audio.load();
    DerelictSFML2Graphics.load();
}

// Вспомогательный поток расчета пути
private struct Coworker
{
    private {
        
        enum Message {
            _EMPTY,
            DONE,
            STOPPED
        }
        
        struct Request {
            Cell.Coordinates start, finish;
        }

        Tid childTid;
    }

    void start() { childTid = spawn(&cwbody, thisTid); }

    void stop()
    {
        send(childTid, Message.DONE);
        receive((Message _message) {});
    }

    // Запрос на расчёт пути
    void path_find_request(Field _field, int st_x, int st_y, int fn_x, int fn_y)
    {
        Request request;
        if (shared_data.ready)
        {
            shared_data.field = _field;
            request.start.x = st_x; request.start.y = st_y;
            request.finish.x = fn_x; request.finish.y = fn_y;
            shared_data.ready = false;
            send(childTid, request);
        }
    }

    // Получение результата
    @property static Path path() { return shared_data.path; }

    @property static bool ready() { return shared_data.ready; }

    // Тело потока
    // Реализованная механика не учитывает возможные изменения на поле во время расчета, 
    // поэтому они должны явно блокироваться на соответствующих участках
    private static void cwbody(Tid mainTid)
    {
        auto a_star = new FieldsAStar();
        Message message;
        Request request;
        bool requested;
        while (true)
        {
            requested = false;
            receive(
                (Message _message) {message = _message;},
                (Request _request) {request = _request; requested = true;},
                (Variant any) {}
            );
            if (message == Message.DONE) 
                break;
            if (requested)
            {
                shared_data.path.clear();
                a_star.search_ofs(shared_data.path, shared_data.field, request.start, request.finish);
                shared_data.ready = true;
            }
        }
        send(mainTid, Message.STOPPED);
    }
}

module pathfinding;

import std.container.array;
import std.container.binaryheap;
import std.math;

class AStar(
    size_t H, size_t W, // Размерность карты
    TCoords, // Тип координат, предоставляющий члены "x" и "y". Со знаком.
    TMap, // Карта. Предоставляет "isobstacle(x, y)"
    TWeight = int, // Тип веса
    TPath = Array!TCoords // Возвращаемый путь, предоставляющий insert
)
{
    private {
        
        enum State {
            WILD = 0,
            OPENED,
            CLOSED
        }

        struct Attributes // Атрибуты позиции
        {
            TWeight fscore, gscore;
            byte ofsx;
            byte ofsy;
            ubyte state;
        }

        Attributes[H * W] attrs;

        struct AttrsPtr // Координаты и ссылка на атрибуты
        {
            Attributes *pa;
            TCoords pos;
            
            this(ref const TCoords p, ref Attributes[H * W] attrs) 
            { 
                pos = p; 
                pa = &(attrs[index2d(pos.x, pos.y)]); 
            }
        }

        struct Directions { 
            int x, y, d;
            this (int[] args)
            {
                x = args[0]; y = args[1]; d = args[2];
            } 
        } 

        static const Directions[8] dirs = [[ -1, -1, 19 ],[ 0, -1, 10 ],[ 1, -1, 19 ],[ -1, 0, 10 ],
                                           [ 1, 0, 10 ],[ -1, 1, 19 ],[ 0, 1, 10 ],[ 1, 1, 19 ]];
        BinaryHeap!(Array!AttrsPtr, "a.pa.fscore > b.pa.fscore") opened;
        Array!AttrsPtr temp_buff; // Для переупорядочивания
    }

    this()
    { 
        temp_buff.reserve(H + W); 
    }
    
    // Получить смещения (в обратном порядке)
    bool search_ofs(ref TPath path, ref const TMap map, ref const TCoords start_p, ref const TCoords finish_p)
    {
        if (!do_search(map, start_p, finish_p))
            return false;
        get_path_ofs(path, start_p, finish_p);
        return true;
    }

    // Получить абсолютные координаты (в обратном порядке)
    bool search(ref TPath path, ref const TMap map, ref const TCoords start_p, ref const TCoords finish_p)
    {
        if (!do_search(map, start_p, finish_p))
            return false;
        get_path(path, start_p, finish_p);
        return true;
    }

    private {

        bool do_search(ref const TMap map, ref const TCoords start_p, ref const TCoords finish_p)
        {
            attrs[] = Attributes(cast(TWeight)0, cast(TWeight)0, 0, 0, 0);
            opened.clear();

            auto current = opened_push(start_p, cost_estimate(start_p, finish_p));
            while (!opened.empty)
            {
                current = opened_pop();
                if (current.pos.x == finish_p.x && current.pos.y == finish_p.y)
                    return true;
                for (int i = 0; i < 8; ++i)
                {
                    int dx = dirs[i].x;
                    int dy = dirs[i].y;
                    TCoords npos;
                    npos.x = current.pos.x + dx;
                    npos.y = current.pos.y + dy;
                    if (!inbound(npos.x, npos.y) || map.isobstacle(npos.x, npos.y))
                        continue;
                    size_t ni = index2d(npos.x, npos.y);
                    if (attrs[ni].state == State.CLOSED)
                        continue;
                    TWeight t_gscore = current.pa.gscore + dirs[i].d;
                    if (attrs[ni].state == State.WILD)
                    {
                        opened_push(npos, t_gscore + cost_estimate(npos, finish_p));
                    }
                    else
                    {
                        if (t_gscore >= attrs[ni].gscore)
                            continue;
                        rearrange(attrs[ni], t_gscore + cost_estimate(npos, finish_p));
                    }
                    attrs[ni].ofsx = cast(byte)dx;
                    attrs[ni].ofsy = cast(byte)dy;
                    attrs[ni].gscore = t_gscore;
                }
            }
            return false;
        }

        AttrsPtr opened_push(ref const TCoords p)
        {
            auto a = AttrsPtr(p, attrs); opened.insert(a); a.pa.state = State.OPENED; return a;
        }

        AttrsPtr opened_push(ref const TCoords s, TWeight score)
        {
            auto a = AttrsPtr(s, attrs); a.pa.fscore = score; opened.insert(a); a.pa.state = State.OPENED; return a;
        }

        AttrsPtr opened_pop()
        {
            auto a = opened.removeAny(); a.pa.state = State.CLOSED; return a;
        }

        void rearrange(ref const Attributes attr, TWeight score)
        {
            AttrsPtr a;
            while (true)
            {
                a = opened.removeAny();
                if (*a.pa == attr)
                    break;
                temp_buff.insert(a);
            }
            a.pa.fscore = score;
            opened.insert(a);
            while (!temp_buff.empty)
            {
                opened.insert(temp_buff.back);
                temp_buff.removeBack();
            }
        }

        void get_path_ofs(out TPath path, ref const TCoords start_p, ref const TCoords finish_p)
        {
            size_t ci = index2d(finish_p.x, finish_p.y);
            size_t si = index2d(start_p.x, start_p.y);
            while (ci != si)
            {
                TCoords p;
                p.x = attrs[ci].ofsx;
                p.y = attrs[ci].ofsy;
                path.insert(p);
                ci -= W * p.y + p.x;
            }
        }

        void get_path(out TPath path, ref const TCoords start_p, ref const TCoords finish_p)
        {
            get_path_ofs(path, start_p, finish_p);
            TCoords cp = start_p;
            foreach_reverse (ref pv; path)
            {
                cp.x = cp.x + pv.x;
                cp.y = cp.y + pv.y;
                pv = cp;
            }
        }

        static size_t index2d(size_t x, size_t y)
        {
            return y * W + x;
        }

        static TWeight cost_estimate(ref const TCoords a, ref const TCoords b)
        {
            TCoords dt; dt.x = b.x - a.x; dt.y = b.y - a.y;
            return cast(TWeight)(10 * (dt.x * dt.x + dt.y * dt.y));
        }

        static bool inbound(int x, int y)
        {
            return x >= 0 && x < cast(int)W && y >= 0 && y < cast(int)H;
        }
    }
}
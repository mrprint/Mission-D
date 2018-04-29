module lmath.matrix;

import std.math;
import std.traits;
import std.conv;

/**
* matrix value
* Params:
*   Type = type of elements
*   Dx = x dimension
*   Dy = y dimension
*/
struct Matrix(Type, uint Dx, uint Dy = Dx) if (isNumeric!Type)
{
    alias TypePublic = Type;

    union
    {
        Type[Dx][Dy] data;
        Type[Dx * Dy] plaindata;
    }

    this(ref in Type[Dx][Dy] data_)
    {
        data = data_;
    }

    this(in Type[][] data_)
    in
    {
        assert(data_.length == Dy);
        foreach (ref row; data_)
            assert(row.length == Dx);
    }
    body
    {
        foreach (y; 0u .. Dy)
            data[y] = data_[y][0u .. Dx];
    }

    this(Type val)
    {
        plaindata[] = val;
    }

    this(TypeB)(ref in Matrix!(TypeB, Dx, Dy) arg) if (!allSameType!(Type, TypeB))
    {
        foreach (y; 0u .. Dy)
            foreach (x; 0u .. Dx)
                static if (isIntegral!Type && isFloatingPoint!TypeB)
                    data[y][x] = cast(Type) floor(arg.data[y][x]);
                else
                    data[y][x] = cast(Type) arg.data[y][x];
    }

    static if (Dy == 1)
    {
        this(ref in Type[Dx] data_)
        {
            data[0] = data_;
        }

        this(in Type[] data_)
        in
        {
            assert(data_.length == Dx);
        }
        body
        {
            data[0] = data_[0u .. Dx];
        }

        void fromLonger(TypeB, uint Dxl)(auto ref in TypeB[Dxl] data_)
                if (Dxl >= Dx && isNumeric!TypeB)
        {
            foreach (x; 0u .. Dx)
                data[0][x] = cast(Type) data_[x];
        }

        void fromLonger(TypeB, uint Dxl)(auto ref in Matrix!(TypeB, Dxl, Dy) arg)
                if (Dxl >= Dx && isNumeric!TypeB)
        {
            fromLonger(arg.data[0]);
        }
    }

    bool opEquals()(auto ref in Matrix arg) pure const
    {
        // if (this is arg)
        //     return true;
        foreach (y; 0u .. Dy)
            foreach (x; 0u .. Dx)
                static if (isFloatingPoint!Type)
                {
                    if (abs(data[y][x] - arg.data[y][x]) >= Type.epsilon)
                        return false;
                }
                else
                {
                    if (data[y][x] != arg.data[y][x])
                        return false;
                }
        return true;
    }

    // ulong toHash() const
    // {
    //     return 0;
    // }

    /**
    * loads zero matrix
    */
    ref auto ldZero()
    {
        plaindata[] = cast(Type) 0;
        return this;
    }

    static if (Dx == Dy)
    {
        ref auto ldIdentity()
        {
            foreach (y; 0u .. Dy)
            {
                foreach (i; 0u .. y)
                    data[y][i] = cast(Type) 0;
                data[y][y] = cast(Type) 1;
                foreach (i; (y + 1) .. Dx)
                    data[y][i] = cast(Type) 0;
            }
            return this;
        }
    }

    auto opBinary(string op, TypeB, uint Da, uint Db)(auto ref in Matrix!(TypeB, Da, Db) arg) pure const
            if (op == "*" && Db >= Dx && isNumeric!TypeB)
    {
        alias TypeW = BestFloatingPoint!(Type, TypeB).type;
        Matrix!(TypeW, Da, Dy) result;
        foreach (y; 0u .. Dy)
        {
            foreach (x; 0u .. Da)
            {
                TypeW acc = 0;
                foreach (i; 0u .. Dx)
                    acc += cast(TypeW) data[y][i] * cast(TypeW) arg.data[i][x];
                static if (Db > Dx)
                {
                    foreach (i; Dx .. Db)
                        acc += cast(TypeW) arg.data[i][x];
                }
                result.data[y][x] = acc;
            }
        }
        return result;
    }

    ref auto opOpAssign(string op, TypeB, uint Da, uint Db)(auto ref in Matrix!(TypeB, Da, Db) arg)
            if (op == "*" && Db >= Dx && Da >= Dx && isNumeric!TypeB)
    {
        alias TypeW = BestFloatingPoint!(Type, TypeB).type;
        Matrix result;
        foreach (y; 0u .. Dy)
        {
            foreach (x; 0u .. Da)
            {
                TypeW acc = 0;
                foreach (i; 0u .. Dx)
                    acc += cast(TypeW) data[y][i] * cast(TypeW) arg.data[i][x];
                static if (Db > Dx)
                {
                    foreach (i; Dx .. Db)
                        acc += cast(TypeW) arg.data[i][x];
                }
                if (x < Dx)
                {
                    static if (isIntegral!Type && isFloatingPoint!TypeW)
                        result.data[y][x] = cast(Type) floor(acc);
                    else
                        result.data[y][x] = cast(Type) acc;
                }

            }
        }
        this = result;
        return this;
    }

    Matrix opBinary(string op)(auto ref in Matrix arg) pure const 
            if (op == "/" || op == "+" || op == "-")
    {
        Matrix result = this;
        mixin("result.plaindata[] " ~ op ~ "= arg.plaindata[];");
        return result;
    }

    ref auto opOpAssign(string op)(auto ref in Matrix arg)
            if (op == "/" || op == "+" || op == "-")
    {
        mixin("plaindata[] " ~ op ~ "= arg.plaindata[];");
        return this;
    }

    Matrix opBinary(string op)(Type val) pure const 
            if (op == "/" || op == "+" || op == "-")
    {
        Matrix result = this;
        mixin("result.plaindata[] " ~ op ~ "= val;");
        return result;
    }

    ref auto opOpAssign(string op)(Type val) if (op == "/" || op == "+" || op == "-")
    {
        mixin("plaindata[] " ~ op ~ "= val;");
        return this;
    }

    static if (Dx == Dy && Dx >= 2 && isFloatingPoint!Type)
    {
        ref auto rotate(Type ang)
        {
            auto mm = Matrix().ldIdentity;
            const sa = sin(ang);
            const ca = cos(ang);
            mm.data[0][0] = ca;
            mm.data[0][1] = sa;
            mm.data[1][0] = -sa;
            mm.data[1][1] = ca;
            this *= mm;
            return this;
        }
    }

    static if (Dx == Dy && Dx >= 2)
    {
        ref auto scale(Type sX, Type sY)
        {
            auto mm = Matrix().ldIdentity;
            mm.data[0][0] = sX;
            mm.data[1][1] = sY;
            this *= mm;
            return this;
        }

        ref auto scale(Type sXY)
        {
            auto mm = Matrix().ldIdentity;
            mm.data[0][0] = sXY;
            mm.data[1][1] = sXY;
            this *= mm;
            return this;
        }
    }

    static if (Dx == Dy && Dy >= 3)
    {
        ref auto translate(Type ofsX, Type ofsY)
        {
            auto mm = Matrix().ldIdentity;
            mm.data[2][0] = ofsX;
            mm.data[2][1] = ofsY;
            this *= mm;
            return this;
        }
    }

    static if (Dx == Dy && isFloatingPoint!Type)
    {
        ref auto ldInvertible()
        {
            immutable MAXB = 1e99;
            immutable MINB = 1 / MAXB;
            real gaus_deter = 1;
            Type gaus_minved = MAXB;
            int[Dx] rn, cn;

            foreach_reverse (j; 0u .. Dx)
                rn[j] = cn[j] = j;
            foreach_reverse (gaus_rest; 0u .. Dx)
            {
                int jved, kved;
                Type vved = -1;

                foreach_reverse (j; 0u .. Dx)
                {
                    if (~rn[j])
                    {
                        foreach_reverse (k; 0u .. Dx)
                        {
                            if (~cn[k])
                            {
                                if (vved < abs(data[j][k]))
                                {
                                    vved = abs(data[j][k]);
                                    jved = j;
                                    kved = k;
                                }
                            }
                        }
                    }
                }

                if (gaus_minved > vved)
                    gaus_minved = vved;
                gaus_deter *= data[jved][kved];
                if (vved < MINB)
                {
                    foreach_reverse (j; 0u .. Dx)
                    {
                        if (~rn[j])
                        {
                            foreach_reverse (k; 0u .. Dx)
                                data[j][k] = Type.nan;
                        }
                        if (~cn[j])
                        {
                            foreach_reverse (k; 0u .. Dx)
                                data[j][k] = Type.nan;
                        }
                    }
                    return this;
                }

                int jt = rn[jved], kt = cn[kved];

                if (jt != kved)
                    gaus_deter = -gaus_deter;

                foreach_reverse (j; 0u .. Dx)
                {
                    const t = data[kt][j];
                    data[kt][j] = data[jved][j];
                    data[jved][j] = t;
                }
                foreach_reverse (j; 0u .. Dx)
                {
                    const t = data[j][jt];
                    data[j][jt] = data[j][kved];
                    data[j][kved] = t;
                }

                rn[jved] = rn[kt];
                cn[kved] = cn[jt];
                rn[kt] = cn[jt] = -1;

                vved = data[kt][jt];
                data[kt][jt] = 1;
                foreach_reverse (j; 0u .. Dx)
                {
                    if (j == kt)
                        continue;
                    const mul = data[j][jt] / vved;
                    data[j][jt] = 0;
                    foreach_reverse (k; 0u .. Dx)
                        data[j][k] -= data[kt][k] * mul;
                }
                foreach_reverse (k; 0u .. Dx)
                    data[kt][k] /= vved;
            }
            return this;
        }

        Matrix invertible() pure const
        {
            Matrix t = this;
            return t.ldInvertible;
        }
    }

    static if (Dy == 1 && Dx >= 2)
    {
        @property Type x() const
        {
            return data[0][0];
        }

        @property void x(Type arg)
        {
            data[0][0] = arg;
        }

        @property Type y() const
        {
            return data[0][1];
        }

        @property void y(Type arg)
        {
            data[0][1] = arg;
        }
    }

    static if (Dy == 1 && Dx >= 3)
    {
        @property Type z() const
        {
            return data[0][2];
        }

        @property void z(Type arg)
        {
            data[0][2] = arg;
        }
    }

    string toString() const
    {
        return "Matrix(" ~ text(data) ~ ")";
    }
}

alias MatrixD3 = Matrix!(double, 3);
alias MatrixD2 = Matrix!(double, 2);
alias VectorD3 = Matrix!(double, 3, 1);
alias VectorD2 = Matrix!(double, 2, 1);

alias MatrixF3 = Matrix!(float, 3);
alias MatrixF2 = Matrix!(float, 2);
alias VectorF3 = Matrix!(float, 3, 1);
alias VectorF2 = Matrix!(float, 2, 1);

template BestFloatingPoint(Ta, Tb)
{
    static if (isFloatingPoint!Ta)
    {
        static if (isFloatingPoint!Tb)
        {
            static if (Ta.sizeof > Tb.sizeof)
                alias type = Ta;
            else
                alias type = Tb;
        }
        else
            alias type = Ta;
    }
    else
    {
        static if (isFloatingPoint!Tb)
            alias type = Tb;
    }
}

unittest
{
    const MatrixD3 a = [[0, 1, 0], [-1, 0, 0], [0, 0, 1]];
    const MatrixF3 b = [[2, 0, 0], [0, 1, 0], [0, 0, 1]];
    const MatrixD3 c = [[1, 0, 0], [0, 1, 0], [0, 3, 1]];

    auto ab = a * b;
    assert(ab * c == MatrixD3([[0, 1, 0], [-2, 0, 0], [0, 3, 1]]));
    ab *= c;
    assert(ab == MatrixD3([[0, 1, 0], [-2, 0, 0], [0, 3, 1]]));

    assert(a + MatrixD3(b) == MatrixD3([[2, 1, 0], [-1, 1, 0], [0, 0, 2]]));
    MatrixD3 ta = a;
    ta += MatrixD3(b);
    assert(ta == MatrixD3([[2, 1, 0], [-1, 1, 0], [0, 0, 2]]));

    assert(Matrix!(double, 2, 1)([2, 1]) * Matrix!(double, 2, 3)([[0, 1], [-1, 0], [3, 4]]) == Matrix!(double,
            2, 1)([2, 6]));

    assert(MatrixD3().ldIdentity.rotate(PI_2).scale(2, 1).translate(0,
            3) == MatrixD3([[0, 1, 0], [-2, 0, 0], [0, 3, 1]]));

    assert(Matrix!(double, 3, 1)([2, 6, 1]) * MatrixD3([[0, 1, 0], [-1, 0, 0],
            [3, 4, 1]]).invertible == Matrix!(double, 3, 1)([2, 1, 1]));
}

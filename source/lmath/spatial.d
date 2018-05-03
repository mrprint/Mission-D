module lmath.spatial;

import lmath.matrix;
import std.math;
import std.traits;
import std.conv;

/**
* Params:
*   Type = type of elements
*/
struct Point(Type, uint Dd, alias Transform) if (isNumeric!Type)
{
    alias TransformType = typeof(Transform);
    alias TypePublic = Type;
    alias TransformPublic = Transform;

    static auto transform = Transform;
    Matrix!(Type, Dd, 1) dm;
    alias dm this;

    this(ref in Type[Dd] data)
    {
        foreach (i; 0u .. Dd)
            dm.data[0][i] = data[i];
    }

    this(in Type[] data)
    in
    {
        assert(data.length == Dd);
    }
    body
    {
        foreach (i; 0u .. Dd)
            dm.data[0][i] = data[i];
    }

    this(TypeB, alias TransformB)(auto ref in Point!(TypeB, Dd, TransformB) arg)
            if (isNumeric!TypeB)
    {
        this = arg;
    }

    auto dot(TypeB)(auto ref in Point!(TypeB, Dd, Transform) arg) pure const 
            if (isNumeric!TypeB)
    {
        alias TypeW = BestFloatingPoint!(Type, TypeB).type;
        TypeW acc = 0;
        foreach (x; 0u .. Dd)
            acc += cast(TypeW)(dm.data[0][x] * arg.dm.data[0][x]);
        return acc;
    }

    Point opBinary(string op)(auto ref in Point arg) pure const 
            if (op == "/" || op == "+" || op == "-")
    {
        Point result = this;
        mixin("result.dm " ~ op ~ "= arg.dm;");
        return result;
    }

    ref auto opOpAssign(string op)(auto ref in Point arg)
            if (op == "/" || op == "+" || op == "-")
    {
        mixin("dm " ~ op ~ "= arg.dm;");
        return this;
    }

    Point opBinary(string op)(auto ref in Point arg) pure const if (op == "*")
    {
        Matrix result = this;
        result.dm.plaindata[] *= arg.dm.plaindata[];
        return result;
    }

    ref auto opOpAssign(string op)(auto ref in Point arg) if (op == "*")
    {
        dm.plaindata[] *= arg.dm.plaindata[];
        return this;
    }

    Point opBinary(string op)(Type val) pure const if (op == "*")
    {
        Point result = this;
        result.dm.plaindata[] *= val;
        return result;
    }

    ref auto opOpAssign(string op)(Type val) if (op == "*")
    {
        dm.plaindata[] *= val;
        return this;
    }

    private enum Adjustment
    {
        NONE = 0,
        SELF,
        OTHER
    }

    private static ref const(TransformType) getSetAdjust(PointB)(
            auto ref in typeof(PointB.TransformPublic) arg, uint adjust = Adjustment.NONE)
            if (allSameType!(TransformType, typeof(PointB.TransformPublic)))
    {
        static unitransform = PointB.TransformPublic.invertible * Transform;
        if (adjust == Adjustment.SELF)
            transform = Transform * arg;
        if (adjust == Adjustment.SELF || adjust == Adjustment.OTHER)
            unitransform = PointB.transform.invertible * transform;

        return unitransform;
    }

    static void adjust(PointB)(auto ref in typeof(PointB.TransformPublic) arg)
            if (allSameType!(TransformType, typeof(PointB.TransformPublic)))
    {
        getSetAdjust!(PointB)(arg, Adjustment.SELF);
        PointB.getSetAdjust!(Point)(TransformType().ldIdentity(), Adjustment.OTHER);
    }

    static void adjust(PointB)()
            if (allSameType!(TransformType, typeof(PointB.TransformPublic)))
    {
        getSetAdjust!(PointB)(TransformType().ldIdentity(), Adjustment.OTHER);
        PointB.getSetAdjust!(Point)(TransformType().ldIdentity(), Adjustment.OTHER);
    }

    void opAssign(TypeB, alias TransformB)(auto ref in Point!(TypeB, Dd, TransformB) arg)
            if (isNumeric!TypeB)
    {
        static immutable zt = TransformType();
        static if (isIntegral!TypeB)
            dm.fromLonger((Matrix!(BestFloatingPoint!(Transform.TypePublic,
                    TransformB.TypePublic).type, Dd, 1)(arg.dm) + 0.5) * getSetAdjust!(Point!(TypeB,
                    Dd, TransformB))(zt));
        else
            dm.fromLonger(arg.dm * getSetAdjust!(Point!(TypeB, Dd, TransformB))(zt));
    }

    static if (Dd >= 2)
    {
        Type hypot_naive() pure const
        {
            Type acc = 0;
            foreach (i; dm.data[0])
                acc += i * i;
            return cast(Type) sqrt(cast(float) acc);
        }

        Point normalized() pure const
        {
            Point result = this;
            result.dm /= hypot_naive();
            return result;
        }
    }

    static if (isFloatingPoint!Type)
    {
        bool atzero() pure const
        {
            return x < Type.epsilon && x > -Type.epsilon && y < Type.epsilon && y > -Type.epsilon;
        }
    }

    string toString() const
    {
        return "Point(" ~ text(dm.plaindata) ~ ")";
    }
}

unittest
{
    alias ctest1 = Point!(int, 2, Matrix!(float, 2)().ldIdentity.rotate(PI_4));
    alias ctest2 = Point!(double, 2, Matrix!(float, 2)().ldIdentity());
    ctest1 aa = [1, 1];
    ctest2 bb = aa;
    //assert(bb == ctest2([1.41421, 0]));
}

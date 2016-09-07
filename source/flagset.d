module mission.flagset;

/// The set of enumerated
struct Set(T)
{
    alias stortype = typeof(1 << T.max);
    private stortype storage;
    
    this(T val)
    {
        this |= val;
    }
    
    void clear()
    {
        storage = 0;
    }
    
    void opOpAssign(string op)(T val) if (op == "|" || op == "+")
    {
        storage |= (cast(stortype)1 << val);
    }
    
    void opOpAssign(string op)(T val) if (op == "~" || op == "-")
    {
        storage &= ~(cast(stortype)1 << val);
    }

    void opOpAssign(string op)(Set val) if (op == "|" || op == "+")
    {
        storage |= val.storage;
    }
    
    void opOpAssign(string op)(Set val) if (op == "~" || op == "-")
    {
        storage &= ~val.storage;
    }

    const bool opBinaryRight(string op)(T val) if (op == "in")
    {
        auto cval = (cast(stortype)1 << val);
        return (storage & cval) == cval;
    }

    const bool opBinary(string op)(Set val) if (op == "in")
    {
        return (val.storage & storage) == storage;
    }
}
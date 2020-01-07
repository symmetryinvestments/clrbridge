import cstring;
import clr : Decimal;
import Primitives : Primitives;
import std.stdio;
void test()
{
    //testValue!bool(false);
    //testValue!bool(true);
    integerTest!ubyte;
    integerTest!byte;
    integerTest!ushort;
    integerTest!short;
    integerTest!uint;
    integerTest!int;
    integerTest!ulong;
    integerTest!long;
    testValue!uint(1234);
    testValue!int(-4719);
    //testValue!char('A');
    assert("abcd" == Primitives.Return(CStringLiteral!"abcd").asSlice);

    floatTest!float;
    floatTest!double;

    testValue!Decimal(Decimal(0, 1, 2, 3));
    testValue!Decimal(Decimal(uint.min, uint.min, uint.min, uint.min));
    testValue!Decimal(Decimal(uint.max, uint.max, uint.max, uint.max));
    testValue!Decimal(Decimal(0x12345678, 0x9abcdef0, 0x2468ace0, 0xfdc97531));
}
void testValue(T)(T value)
{
    writefln("test type %s value %s", typeid(T), value);
    assert(value == Primitives.Return(value));
    // double check that it's not always equal
    if (value != T.init)
        assert(value != Primitives.Return(T.init));
}
void integerTest(T)()
{
    testValue!T(0);
    testValue!T(T.min);
    testValue!T(T.max);
    testValue!T(0x0F);
    testValue!T(0x76);
    static if (0x1234 <= T.max)
    {
        testValue!T(0x1234);
    }
}
void floatTest(T)()
{
    testValue!T(0.0);
    testValue!T(1.0);
    testValue!T(12.3456);
}

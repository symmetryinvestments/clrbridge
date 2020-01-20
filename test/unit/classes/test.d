import cstring;
import clr : Decimal;
import clrbridge.global;
import classes;
import std.stdio;

void test()
{
    {
        const c = EmptyClass.New();
        scope (exit) globalClrBridge.release(c);
    }
    {
        const c = Int32Class.New();
        scope (exit) globalClrBridge.release(c);
        c.SetValue(100);
        writefln("c.GetValue() = %s", c.GetValue());
        // instance methods not implemented
        //assert(100 == c.GetValue());
    }
}

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
        foreach (int value; [100, -123435, 0x8301])
        {
            c.SetValue(value);
            int actual = c.GetValue();
            writefln("expecting value %s", actual);
            assert(value == actual);
            // fields not implemented yet
            //assert(c.value == value);
            //c.value = 0;
            //assert(c.value == 0);
            //c.value = value;
            //assert(c.value == value);
        }
    }
}

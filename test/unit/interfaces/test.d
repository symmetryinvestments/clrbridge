import cstring;
import clr : Decimal;
import clrbridge.global;
import interfaces;
import std.stdio;

void test()
{
    {
        const iface = Factory.CreateIEmpty();
        scope (exit) globalClrBridge.release(iface);
    }
    {
        const iface = Factory.CreateIInt32();
        scope (exit) globalClrBridge.release(iface);
        // TODO: implement methods
        //iface.SetValue(1234);
        //assert(iface.GetValue() == 1234);
    }
}

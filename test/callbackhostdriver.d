import std.stdio;
import cstring;
import clrbridge;
import clrbridge.callbackhost;

extern (C) int _clrCallbackHostEntry(CreateDelegate createDelegate, int argc, CString* argv/*, CString* envp*/)
{
    import core.runtime;
    try
    {
        Runtime.initialize();
        initGlobalClrBridgeWithCallbackHost(createDelegate);
        const result = mainClr(argc, argv);
        Runtime.terminate();
        return result;
    }
    catch (Throwable e)
    {
        printf("%s", e.toString().toCString());
        return 1;
    }
}
int mainClr(int argc, CString* argv)
{
    static import testlist;
    testlist.runAll();
    return 0;
}

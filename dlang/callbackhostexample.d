import std.stdio;
import cstring;
import clrbridge;
import clrbridge.callbackhost;
import mscorlib.system;

export extern (C) int _clrCallbackHostEntry(CreateDelegate createDelegate, int argc, CString* argv/*, CString* envp*/)
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
    writefln("mainClr argc=%s!\n", argc);stdout.flush();
    for (int i = 0; i < argc; i++)
    {
        writefln("arg[%s] '%s'", i, argv[i]);
    }
    Console.WriteLine(CStringLiteral!"Calling C# from D!");
    return 0;
}

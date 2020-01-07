import std.string : toStringz;

import std.stdio;
import hresult;
import cstring;

import clrbridge;
import clrbridgeglobal;

// TODO: move this setup code into clrbridge.d
alias CreateDelegate = extern(C) HRESULT function(CString assemblyName, CString methodName, void** outFuncAddr) nothrow @nogc;

// TODO: move this function to the clrbridge library
extern(C) int mainClr(CreateDelegate createDelegate, int argc/*, CString* argv, CString envp*/)
{
    import core.stdc.stdio : printf;
    printf("mainClr!\n");
    import core.runtime;
    try
    {
        Runtime.initialize();
        {
            static struct CreateDelegateFactory
            {
                CreateDelegate createDelegate;
                HRESULT createClrBridgeDelegate(CString methodName, void** outFuncAddr) const
                {
                    return cast(HRESULT)createDelegate(CStringLiteral!"ClrBridge", methodName, outFuncAddr);
                }
            }
            const factory = CreateDelegateFactory(createDelegate);
            const result = loadClrBridge(&factory.createClrBridgeDelegate, &globalClrBridge);
            if (result.failed)
                writefln("Error: loadClrBridge failed with %s", result);
        }
        const result = mainClr2(argc/*, argv*/);
        Runtime.terminate();
        return result;
    }
    catch (Throwable e) 
    {
        printf("%s", e.toString().toStringz());
        return 1;
    }

    return 0;
}

int mainClr2(int argc/*, CString* argv*/)
{
    writefln("mainClr2 argc=%s!\n", argc);stdout.flush();
    import mscorlib.System;
    Console.WriteLine(CStringLiteral!"Calling C# from D!");
    return 0;
}

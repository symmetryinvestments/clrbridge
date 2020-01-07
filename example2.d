import std.string : toStringz;

import std.stdio;
import hresult;
import cstring;

// uncommenting causes dlopen to fail
import clrbridge;
import clrbridgeglobal;

// TODO: should return HRESULT but is causing dlopen to fail???
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
        const result = mainClr2(createDelegate, argc/*, argv*/);
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

int mainClr2(CreateDelegate createDelegate, int argc/*, CString* argv*/)
{
    printf("mainClr2 argc=%d!\n", argc);
    static struct CreateDelegateFactory
    {
        CreateDelegate createDelegate;
        HRESULT createClrBridgeDelegate(CString methodName, void** outFuncAddr) const
        {
            return cast(HRESULT)createDelegate(CStringLiteral!"ClrBridge", methodName, outFuncAddr);
        }
    }
    const factory = CreateDelegateFactory(createDelegate);
    {
        const result = loadClrBridge(&factory.createClrBridgeDelegate, &globalClrBridge);
        if (result.failed)
            writefln("Error: loadClrBridge failed with %s", result);
    }
    return 0;
}

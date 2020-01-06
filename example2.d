import std.string : toStringz;

import std.stdio;
import hresult;
import cstring;

alias CreateDelegate = extern(C) HRESULT function(CString assemblyName, CString typeName, CString methodName, void** outFuncAddr) nothrow @nogc;

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
}
int mainClr2(CreateDelegate createDelegate, int argc/*, CString* argv*/)
{
    printf("mainClr2 argc=%d!\n", argc);

    {
        void function(void*) debugWriteObject;
        // for some reason this causes dlopen to fail???
        //const result = createDelegate(CStringLiteral!"ClrBridge", CStringLiteral!"ClrBridge",
        //    CStringLiteral!"DebugWriteObject", cast(void**)&debugWriteObject);
        //writefln("result = %s", result);
    }

     static struct CreateDelegateFactory
     {
         /*
         HRESULT createClrBridgeDelegate(CString methodName, void** outFuncAddr) const
         {
             return coreclrHost.create_delegate(CStringLiteral!"ClrBridge",
                 CStringLiteral!"ClrBridge", methodName, outFuncAddr);
         }
         */
     }

    {

    }

    return 0;
}
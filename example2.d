import std.string : toStringz;

import std.stdio;
import cstring;


extern(C) uint function(CString assemblyName, CString typeName, CString methodName, void** outFuncAddr) nothrow @nogc CreateDelegate;

// TODO: move this function to the clrbridge library
extern(C) int mainClr(/*CreateDelegate createDelegate, */int argc/*, CString* argv, CString envp*/)
{
    import core.stdc.stdio : printf;
    printf("mainClr!\n");
    import core.runtime;
    try
    {
        Runtime.initialize();
        const result = mainClr2(argc/*, argv*/);
        Runtime.terminate();
        return result;
    }
    catch (Throwable e) 
    {
        printf("%s", e.toString().toStringz());
        return 1;
    }        
}
int mainClr2(int argc/*, CString* argv*/)
{
    printf("mainClr2 argc=%d!\n", argc);
    return 0;
}
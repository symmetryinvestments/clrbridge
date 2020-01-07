// module to initialize clrbridge via the ClrLibRunner hosting mechanism
module clrbridgelibrunner;

// use this so we can use CString as a parameter in _mainClr without importing it in the mixin template
import fromlib;
import hresult;
import cstring;

alias CreateDelegate = extern(C) HRESULT function(CString assemblyName, CString methodName, void** outFuncAddr) nothrow @nogc;

mixin template MainClrMixin()
{
    // TODO: move this function to the clrbridge library
    extern(C) int _mainClr(CreateDelegate createDelegate, int argc, from!"cstring".CString* argv/*, from!"cstring".CString envp*/)
    {
        import core.stdc.stdio : printf;
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
            const result = mainClr(argc, argv);
            Runtime.terminate();
            return result;
        }
        catch (Throwable e) 
        {
            printf("%s", e.toString().toStringz());
            return 1;
        }
    }
}

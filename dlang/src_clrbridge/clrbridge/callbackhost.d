// module to initialize clrbridge via the ClrLibRunner hosting mechanism
module clrbridge.callbackhost;

import hresult;
import cstring;

alias CreateDelegate = extern(C) HRESULT function(CString assemblyName, CString methodName, void** outFuncAddr) nothrow @nogc;

void initGlobalClrBridgeWithCallbackHost(CreateDelegate createDelegate)
{
    import std.format : format;
    import clrbridge;
    import clrbridge.global;
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
        throw new Exception(format("loadClrBridge failed with %s", result));
}

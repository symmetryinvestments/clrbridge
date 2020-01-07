// module to initialize clrbridge via the coreclr library hosting mechanism
module clrbridge.coreclr;

import cstring;
import hresult;
import coreclr.host;
import clrbridge;

/// Convenience function to completely initialize the ClrBridge
void initGlobalClrBridgeWithCoreclr(string clrBridgeDll)
{
    import std.format : format;
    import std.path : pathSeparator;
    import std.file : exists;
    import coreclr : loadCoreclr;
    import coreclr.globalhost;
    import clrbridge.global;

    // Add this check because it gives a nice error message for something that is probably
    // going to happen farily commonly
    if (!exists(clrBridgeDll))
        throw new Exception(format("initClrBridge failed: clrBridgeDll '%s' does not exist", clrBridgeDll));

    loadCoreclr();
    {
        CoreclrHostOptions options;
        auto propMap = coreclrDefaultProperties();
        propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES] = format("%s%s%s",
            propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES],
            pathSeparator,
            clrBridgeDll);
        options.properties = CoreclrProperties(propMap);
        globalCoreclrHost.initialize(options);
    }
    {
        const result = loadClrBridgeCorclr(&globalCoreclrHost, &globalClrBridge);
        if (result.failed)
            throw new Exception(format("initClrBridge failed: loadClrBridge failed with %s", result));
    }
}

private ClrBridgeError loadClrBridgeCorclr(CoreclrHost* coreclrHost, ClrBridge* bridge)
{
     static struct CoreclrDelegateFactory
     {
         CoreclrHost* coreclrHost;
         HRESULT createClrBridgeDelegate(CString methodName, void** outFuncAddr) const
         {
             return coreclrHost.create_delegate(CStringLiteral!"ClrBridge",
                 CStringLiteral!"ClrBridge", methodName, outFuncAddr);
         }
     }
     const factory = CoreclrDelegateFactory(coreclrHost);
     return loadClrBridge(&factory.createClrBridgeDelegate, bridge);
}

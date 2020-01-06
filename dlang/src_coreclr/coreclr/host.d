// TODO: rename this to backend/coreclr.d
module coreclr.host;

import std.path : dirName;

import hresult;
import cstring;

import coreclr;

string defaultTrustedPlatformAssembliesFiles(string dir = dirName(getCoreclrLibname()))
{
    import std.stdio;
    import std.path;
    import std.file;
    import std.algorithm;
    import std.range;

    immutable extensions = [
        "*.ni.dll", // Probe for .ni.dll first so that it's preferred
        "*.dll",    // if ni and il coexist in the same dir
        "*.ni.exe", // ditto
        "*.exe",
    ];
    import std.array;
    Appender!string assemblies;
    bool[string] added;

    string prefix = "";
    foreach(extension; extensions)
    foreach(entry; dirEntries(dir, extension, SpanMode.shallow).filter!(e => e.isFile))
    {
        if (entry.name !in added)
        {
            added[entry.name] = true;
            assemblies.put(prefix);
            assemblies.put(entry.name);
            prefix = pathSeparator;
        }
    }

    return assemblies.data;
}

struct CoreclrProperties
{
    private uint count;
    const(CString)* keys;
    const(CString)* values;

    this(string[string] propMap)
    in { assert(propMap.length <= uint.max); } do
    {
        import std.array;
        import std.string;
        import std.algorithm : each, map;
        this.count = cast(uint)propMap.length;
        this.keys = propMap.keys.map!(e => CString(e.toStringz)).array.ptr;
        this.values = propMap.values.map!(e => CString(e.toStringz)).array.ptr;
    }
}

enum StandardCoreclrProp : string
{
    /// pathSeparator separated list of directories
    APP_PATHS = "APP_PATHS",
    /// pathSeparator separated list of files. See TrustedPlatformAssembliesFiles
    TRUSTED_PLATFORM_ASSEMBLIES = "TRUSTED_PLATFORM_ASSEMBLIES",
    /// pathSeparator separated list of directories
    APP_NI_PATHS = "APP_NI_PATHS",
    /// pathSeparator separated list of directories
    NATIVE_DLL_SEARCH_DIRECTORIES = "NATIVE_DLL_SEARCH_DIRECTORIES",
    /// boolean
    SYSTEM_GC_SERVER = "System.GC.Server",
    /// boolean
    SYSTEM_GLOBALISATION_INVARIANT = "System.Globalization.Invariant",
}

string[string] coreclrDefaultProperties()
{
    import std.file : getcwd;

    const cwd = getcwd();
    return [
        StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES : defaultTrustedPlatformAssembliesFiles(),
        StandardCoreclrProp.APP_PATHS : cwd,
        StandardCoreclrProp.APP_NI_PATHS : cwd,
        StandardCoreclrProp.NATIVE_DLL_SEARCH_DIRECTORIES : cwd,
        StandardCoreclrProp.SYSTEM_GC_SERVER : "false",
        StandardCoreclrProp.SYSTEM_GLOBALISATION_INVARIANT : "false"
    ];
}

struct CoreclrHostOptions
{
    CString exePath;
    CString appDomainFriendlyName;
    CoreclrProperties properties;
}

// Uses the global coreclr
struct CoreclrHost
{
    private void* handle;
    private uint domainId; // an isolation unit within a process

    HRESULT tryInitialize(const ref CoreclrHostOptions options)
    {
        import std.internal.cstring : tempCString;
        import std.file : thisExePath;

        // TODO: verify we can use tempCString
        if (options.exePath is null)
        {
            const exePath = tempCString(thisExePath);
            const newOptions = const CoreclrHostOptions(CString(exePath), options.appDomainFriendlyName, options.properties);
            return tryInitialize(newOptions);
        }

        const appDomain = options.appDomainFriendlyName ? options.appDomainFriendlyName : options.exePath;

        version (DebugCoreclr)
        {
            writefln("calling coreclr_initialize...");
            writefln("exePath = '%s'", options.exePath);
            writefln("appDomainFriendlyName = '%s'", options.appDomainFriendlyName);
            writefln("%s properties:", options.properties.count);
            foreach (i; 0 .. options.properties.count)
            {
                writefln("%s=%s", options.properties.keys[i], options.properties.values[i]);
            }
        }
        const result = coreclr_initialize(
            options.exePath, // absolute path of the native host executable
            appDomain,
            options.properties.count,
            options.properties.keys,
            options.properties.values,
            &handle, &domainId);
        version (DebugCoreclr)
        {
            writefln("coreclr_initialize returned %s", result);
        }
        return result;
    }

    void initialize(const ref CoreclrHostOptions options)
    {
        const result = tryInitialize(options);
        if (result.failed)
        {
            import std.format : format;
            throw new Exception(format("coreclr_initialize failed, result=0x%08x", result.rawValue));
        }
    }

    void shutdown()
    {
        coreclr_shutdown(handle, domainId);
    }

    int shutdown_2()
    {
        int ret;
        coreclr_shutdown_2(handle, domainId, &ret);
        return ret;
    }

    HRESULT create_delegate(CString assembly, CString type, CString method, void** dg) const
    {
        return coreclr_create_delegate(handle, domainId, assembly, type, method, dg);
    }

    void* create_delegate(string assembly, string type, string method) const
    {
        import std.format : format;

        void* dg;

        // TODO: use tempCString instead???
        const result = create_delegate(
            assembly.toCString,
            type.toCString,
            method.toCString,
            &dg);
        if (result.failed)
            throw new Exception(format("create_delegate %s %s %s failed with %s",
                assembly, type, method, result));
        return dg;
    }
}

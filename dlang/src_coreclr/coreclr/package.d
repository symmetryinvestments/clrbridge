/**
Checkout API here: https://github.com/dotnet/coreclr/blob/master/src/coreclr/hosts/inc/coreclrhost.h

This module loads the coreclr library into a set of global function pointers.
These global function pointers are initialized to an implementation that asserts.
Once the loadCoreclr function is called, then these global function pointers will be bound
to the corresponding functions in the coreclr library.

*/
module coreclr;

import hresult;
import cstring;

private
{
    import derelict.util.system;
    static if(Derelict_OS_Windows)
        enum defaultLibNames = `C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App\3.1.0\coreclr.dll`;
    else static if (Derelict_OS_Mac)
        enum defaultLibNames = "/usr/local/share/dotnet/shared/Microsoft.NETCore.App/2.2.3/libcoreclr.dylib";
    else static if (Derelict_OS_Linux)
        enum defaultLibNames =
              "libcoreclr.so"
            ~ ",/nix/store/b0v83nvcsd49n3awa9v4aa2vmxfz5308-dotnet-sdk-2.2.401/shared/Microsoft.NETCore.App/2.2.6/libcoreclr.so"
            ~ ",/usr/share/dotnet/shared/Microsoft.NETCore.App/3.1.0/libcoreclr.so"
            ;
    else
        static assert(0, "Need to implement CoreCLR libNames for this operating system.");
}

struct FuncDefs
{
    alias coreclr_initialize = extern(C) HRESULT function(
        CString exePath,
        CString appDomainFriendlyName,
        int propertyCount,
        const CString* propertyKeys,
        const CString* propertyValues,
        void** hostHandle,
        uint* domainId) nothrow @nogc;

    alias coreclr_shutdown = extern(C) int function(void* hostHandle, uint domainId) nothrow @nogc;

    alias coreclr_shutdown_2 = extern(C) int function(void* hostHandle, uint domainId, int* latchedExitCode) nothrow @nogc;

    alias coreclr_create_delegate = extern(C) HRESULT function(
        const void* hostHandle,
        uint domainId,
        CString entryPointAssemblyName,
        CString entryPointTypeName,
        CString entryPointMethodName,
        void** dg) nothrow @nogc;

    alias coreclr_execute_assembly = extern(C) int function(
        void* hostHandle,
        uint domainId,
        int argc,
        const char** argv,
        const char* managedAssemblyPath,
        uint* exitCode) nothrow @nogc;
}

private bool notLoaded() nothrow @nogc
{ assert(0, "the coreclr library has not been loaded, have you called coreclr.loadCoreclr?"); }

// TODO: see if there is a shorter way to define the notLoaded functions
private struct NotLoaded
{
    static extern(C) HRESULT coreclr_initialize(
        CString exePath,
        CString appDomainFriendlyName,
        int propertyCount,
        const CString* propertyKeys,
        const CString* propertyValues,
        void** hostHandle,
        uint* domainId) nothrow @nogc
    { notLoaded(); assert(0); }

    static extern(C) int coreclr_shutdown(void* hostHandle, uint domainId) nothrow @nogc
    { notLoaded(); assert(0); }

    static extern(C) int coreclr_shutdown_2(void* hostHandle, uint domainId, int* latchedExitCode) nothrow @nogc
    { notLoaded(); assert(0); }

    static extern(C) HRESULT coreclr_create_delegate(
        const void* hostHandle,
        uint domainId,
        CString entryPointAssemblyName,
        CString entryPointTypeName,
        CString entryPointMethodName,
        void** dg) nothrow @nogc
    { notLoaded(); assert(0); }

    static extern(C) int coreclr_execute_assembly(
        void* hostHandle,
        uint domainId,
        int argc,
        const char** argv,
        const char* managedAssemblyPath,
        uint* exitCode) nothrow @nogc
    { notLoaded(); assert(0); }
}

__gshared FuncDefs.coreclr_initialize       coreclr_initialize       = &NotLoaded.coreclr_initialize;
__gshared FuncDefs.coreclr_shutdown         coreclr_shutdown         = &NotLoaded.coreclr_shutdown;
__gshared FuncDefs.coreclr_shutdown_2       coreclr_shutdown_2       = &NotLoaded.coreclr_shutdown_2;
__gshared FuncDefs.coreclr_create_delegate  coreclr_create_delegate  = &NotLoaded.coreclr_create_delegate;
__gshared FuncDefs.coreclr_execute_assembly coreclr_execute_assembly = &NotLoaded.coreclr_execute_assembly;
private __gshared string loadCoreclrLibName = null; // used by 'host.d' to find other libraries/assemblies

// try atomic exchange if supported, otherwise, fallback to a normal exchange
bool tryAtomicExchange(shared bool* value, bool newValue)
{
    import core.atomic;
    static if (is(atomicExchange))
        return atomicExchange(value, newValue);
    else
    {
        // fallback to non-atomic exchange
        auto save = *value;
        *value = newValue;
        return save;
    }
}

/**
Load the coreclr library functions (i.e. coreclr_initialize, coreclr_shutdown, etc).
Params:
  libNames = A string containing one or more comma-separated shared library names.
*/
void loadCoreclr(string libNames = defaultLibNames)
{
    import derelict.util.loader;

    static shared calledAlready = false;

    if (tryAtomicExchange(&calledAlready, true))
        throw new Exception("loadCoreclr was called more than once");

    static class CoreclrLoader : SharedLibLoader
    {
        this(string libNames) { super(libNames); }
        protected override void loadSymbols()
        {
            bindFunc(cast(void**)&coreclr_initialize, "coreclr_initialize");
            bindFunc(cast(void**)&coreclr_shutdown, "coreclr_shutdown");
            bindFunc(cast(void**)&coreclr_shutdown_2, "coreclr_shutdown_2");
            bindFunc(cast(void**)&coreclr_create_delegate, "coreclr_create_delegate");
            bindFunc(cast(void**)&coreclr_execute_assembly, "coreclr_execute_assembly");
        }
        public string libName() { return this.lib.name; }
    }
    auto loader = new CoreclrLoader(libNames);
    loader.load();
    loadCoreclrLibName = loader.libName;
    assert(loadCoreclrLibName !is null, "codebug: did not expect SharedLibLoader.lib.name to return null after calling load()");
}

string getCoreclrLibname()
in { if (loadCoreclrLibName is null) assert(notLoaded()); } do
{
    return loadCoreclrLibName;
}

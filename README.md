# clrbridge

Call .NET code from other languages.  Currently focused on the D programming language, with the possibility of adding support for other langauges.

# Current State

See tests to see what currently works.

* [test/tests](test/tests)
* [test/unit](test/unit)

Currently ClrBridge supports calling methods with primitive types and enum types.  The development strategy is to translate mscorlib, but translating the whole thing requires full support, so the code generator skips unsupported constructs during this initial stage of development.  As more functionality gets added, the features that are currently skipped will be enabled and unit tests added along the way.

# How it Works

.NET code requires the CLR runtime to execute.  This repo currently supports 2 mechanisms to initialize the CLR runtime in order to run .NET code from native code.

### Method 1: Coreclr Library Host

This method uses the coreclr library to host .NET CLR assemblies from native executables. The coreclr library initializes a .NET CLR runtime within a native process, and provides functions to call static .NET methods. The `ClrBridge.dll` .NET library provides a set of static methods to enable full access to the .NET CLR runtime.

Here's an example program that uses this method:
```D
import std.path;
import std.stdio;

import cstring;
import clrbridge;
import clrbridge.coreclr;

import mscorlib.System;

int main(string[] args)
{
    initGlobalClrBridgeWithCoreclr(buildPath(__FILE_FULL_PATH__.dirName, "out", "ClrBridge.dll"));

    Console.WriteLine();
    Console.WriteLine(true);
    Console.WriteLine(CStringLiteral!"hello!");

    return 0;
}
```

### Method 2: Clr Callback Host

This method starts by running a .NET process and then P/Invoking into a native shared library and providing a callback method to grant access to the methods in `ClrBridge.dll`.  Once the native executable has been called, this method functions the same way as the Coreclr Library Host method, where it uses `ClrBridge.dll` to enable full access to the .NET CLR runtime. The ClrCallbackHost.exe .NET executable can be used to run native shared libraries:
```
ClrCallbackHost.exe <shared_library> <args>...
```
This will call the `_clrCallbackHostEntry` entry point with the given command-line arguments and a function pointer to load methods from `ClrBridge.dll`.  Here's an example program that uses this method:

```D
import std.stdio;
import cstring;
import clrbridge;
import clrbridge.callbackhost;
import mscorlib.System;

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
```

### Method 3: COM Clr Host

Support for this method has not been added yet.  This one is lower priority since as far as I know it will only work for Windows.

# How to Build

Note that all files created should go into the "out" directory or the "out-pure" directory.  "out-pure" will contain files that doesn't need to be cleaned/regenerated (i.e. versioned source trees from other projects).

You can run a full clean build with:
```bash
rund minish.d cleanBuildAll
```

The build is separated into individual steps which you can see in [cleanBuildAll](cleanBuildAll).

# Notes

Currently I use a sequence of calls to create/pass arrays to the CLR.  Instead, I could leverage the technique I use for return values to create an array in one call.  Namely, layout the array elements in memory, then call a function to serialize it into a .NET array.  ClrBridge would iterate over each elements, marshaling each value like it does a return value.  Note that this is just an optimization, I'll have to check performance to see if this extra code is worth it.

### Idea: Using D's GC to release C# object references

All .NET Object references returned by ClrBridge are "pinned", meaning that C# will not garbage collect them.  It is up to the D code to release object references in order for the Clr to collect them.  Right now the D application can call `globalClrBridge.release` to release a reference, however, I'd like to see if it's feasible to have the D garbage collector call this automatically when these C# objects are out of scope and no longer referenced. I believe this will require wrapping the .NET object references to D objects allocated on the heap.

# TODO

#### ClrBridge Assembly Resolution

Add support in ClrBridge to resolve assemblies when they are missing.  This is the same thing that `ClrBridgeCodegen` does with

```
        AppDomain.CurrentDomain.AssemblyResolve += new ResolveEventHandler(AssemblyResolveCallback);
```

Might provide a function in ClrBridge.dll that allows the client to add assembly paths.

#### Dll FileName Info in Generated Code

I should include some information about the original DLL in the generated Code.  Information that could help ClrBridge find the dll at runtime.
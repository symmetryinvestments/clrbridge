# clrbridge

Call .NET code from other languages.  Currently focused on the D programming language, with the possibility of adding support for other langauges.

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

    foreach (i; 0 .. 4)
        Console.WriteLine();
    Console.WriteLine(false);
    Console.WriteLine(true);
    Console.WriteLine(CStringLiteral!"hello!");
    foreach (i; 0 .. 4)
        Console.WriteLine();

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

extern (C) int _clrCallbackHostEntry(CreateDelegate createDelegate, int argc, CString* argv/*, CString* envp*/)
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

Note that all files created should go into the "out" directory.

```bash
# clean and run everything, the rest of the commands allow you to build smaller pieces
rund minish.d cleanBuildAll

# download dependencies (i.e. DerelictUtil)
rund minish.d downloadDeps

# build the ClrBridge.dll .NET library
rund minish.d buildClrBridge

# at this point the noCodegenExample.d should work this example
# uses ClrBridge.dll to call into .NET code, but doesn't require any generated code
rund noCodegenExample.d

# build the ClrBridgeCodgen.exe .NET executable
# this tool will take an assembly and generate D code to easily call into it
rund minish.d buildClrBridgeCodegen

# invoke ClrBridgeCodegen.exe to generate D wrapper code for common .NET libraries
rund minish.d generateDWrappers

# execute the example that uses the code from generateDWrappers
rund example.d

# build the ClrCallbackHost.exe .NET executable
rund minish.d buildClrCallbackHost

# run exmaple2 that uses ClrCallbackHost.exe
rund minish.d runCallbackHostExample

# run tests
rund minish.d runTests
```

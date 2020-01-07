# clrbridge

Call .NET code from other languages.  Currently focused on the D programming language, with the possibility of adding support for other langauges.

# How it Works

This tool uses the coreclr library to host .NET CLR assemblies from native executables. However, coreclr library alone only provides access to static methods. The ClrBridge.dll .NET assembly supplements the coreclr library by providing static methods that enable full access to the .NET CLR runtime.

> NOTE: Might add support for other hosting APIs, like the COM CLR Hosting API.

# How to Build

Note that all files created should go into the "out" directory.

```bash
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

# build the ClrLibRunner tool
rund minish.d buildClrLibRunner

# run exmaple2 that uses ClrLibRunner
rund minish.d runExample2
```

# TODO

* Add a .NET executable that calls a shared library, which can be used to call the CLR from native code instead.  It would pass in the command-line arguments and a callback function equivalent to libcoreclr's create_delegate function.
* Add support for a COM backend (as far as I know this will only work on windows so it's lower priority than supporting the coreclr backend)

#!/usr/bin/env rund
//!importPath ../../dlang/src_hresult
//!importPath ../../dlang/src_cstring
//!importPath ../../out/DerelictUtil/source
//!importPath ../../dlang/src_coreclr
//!importPath ../../dlang/src_clr
//!importPath ../../dlang/src_clrbridge

import std.path : buildPath, dirName, absolutePath, buildNormalizedPath;
import std.stdio;

import cstring;
import clrbridge;
import clrbridge.coreclr;

static import test;

int main(string[] args)
{
    assert(args.length == 2, "expected 1 command-line argument, the .NET dll");
    const testAssembly = args[1];
    const clrBridgeDll = buildPath(__FILE_FULL_PATH__.dirName.dirName.dirName, "out", "ClrBridge.dll");
    writefln("loading '%s'", clrBridgeDll);
    initGlobalClrBridgeWithCoreclr(clrBridgeDll, [testAssembly.absolutePath.buildNormalizedPath]);
    test.test();
    return 0;
}

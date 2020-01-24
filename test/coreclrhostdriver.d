#!/usr/bin/env rund
//!importPath ../dlang/src_hresult
//!importPath ../dlang/src_cstring
//!importPath ../out/DerelictUtil/source
//!importPath ../dlang/src_coreclr
//!importPath ../dlang/src_clr
//!importPath ../dlang/src_clrbridge
//!importPath ../out/dlibs/src
//!importPath tests

import std.path : buildPath, dirName;
import std.stdio;

import cstring;
import clrbridge;
import clrbridge.coreclr;

static import testlist;

int main(string[] args)
{
    initGlobalClrBridgeWithCoreclr(buildPath(__FILE_FULL_PATH__.dirName.dirName, "out", "ClrBridge.dll"));
    testlist.runAll();
    return 0;
}

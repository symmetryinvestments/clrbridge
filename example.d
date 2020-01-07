#!/usr/bin/env rund
//!importPath dlang/src_hresult
//!importPath dlang/src_cstring
//!importPath out/DerelictUtil/source
//!importPath dlang/src_coreclr
//!importPath dlang/src_clr
//!importPath dlang/src_clrbridge
//!importPath out/src_mscorlib

import std.path : buildPath, dirName;
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

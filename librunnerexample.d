import std.string : toStringz;

import std.stdio;
import hresult;
import cstring;

import clrbridge;
import clrbridgelibrunner;

import mscorlib.System;

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

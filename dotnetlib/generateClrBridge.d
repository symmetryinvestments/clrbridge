import std.stdio : writefln;
import std.path : buildPath, dirName;

import clr;

void main()
{
    writefln("using System;");
    writefln("using System.Reflection;");
    writefln("using System.Runtime.InteropServices;");
    writefln("");
    writefln("public static partial class ClrBridge");
    writefln("{");
    foreach (t; primitiveTypes)
    {
        writefln("    public static IntPtr Box%s(%s value)", t, t);
        writefln("    {");
        writefln("        return GCHandle.ToIntPtr(GCHandle.Alloc((Object)value));");
        writefln("    }");
        writefln("    public static void CallStatic%s(IntPtr methodPtr, %s value)", t, t);
        writefln("    {");
        writefln("        MethodInfo method = (MethodInfo)GCHandle.FromIntPtr(methodPtr).Target;");
        writefln("        method.Invoke(null, new Object[] {value});");
        writefln("    }");
        writefln("    public static void ArrayBuilderAdd%s(IntPtr arrayBuilderPtr, %s value)", t, t);
        writefln("    {");
        writefln("        ArrayBuilder<%s> arrayBuilder = (ArrayBuilder<%s>)GCHandle.FromIntPtr(arrayBuilderPtr).Target;", t, t);
        writefln("        arrayBuilder.Add(value);");
        writefln("    }");
    }
    writefln("}");
 }
 
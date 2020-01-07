// Generates D code to call C# code using the ClrBridge library
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;

static class ClrBridgeCodegen
{
    static void Usage()
    {
        Console.WriteLine("Usage: GenerateDelegateTypes.exe");
    }
    public static Int32 Main(String[] args)
    {
        Assembly assembly = Assembly.Load("ClrBridge");
        Type type = assembly.GetType("ClrBridge");
        if (type == null) throw new Exception(String.Format(
            "assembly {0} does not have the 'ClrBridge' type", assembly));

        Console.WriteLine("// NOTE: this file can be completely removed once we can support dynamic runtime delegate types");
        Console.WriteLine("using System;");
        Console.WriteLine("using System.Reflection;");
        Console.WriteLine("public static class ClrBridgeDelegateTypes");
        Console.WriteLine("{");
        Console.WriteLine("    public static Type TryGetDelegateType(String methodName)");
        Console.WriteLine("    {");
        foreach (MethodInfo method in type.GetMethods())
        {
            if (!method.IsStatic) continue;
            Console.WriteLine("        if (methodName == \"{0}\") return typeof(Delegate{0});", method.Name);
        }
        Console.WriteLine("        return null;");

        Console.WriteLine("    }");
        foreach (MethodInfo method in type.GetMethods())
        {
            if (!method.IsStatic) continue;
            Console.Write("    delegate {0} Delegate{1}(", ReturnTypeString(method.ReturnType), method.Name);
            String prefix = "";
            foreach (ParameterInfo p in method.GetParameters())
            {
                Console.Write("{0}{1} {2}", prefix, ParameterTypeString(p.ParameterType), p.Name);
                prefix = ", ";
            }
            Console.WriteLine(");");
        }
        Console.WriteLine("}");
        return 0;
    }
    static String ReturnTypeString(Type type)
    {
        if (type == typeof(void)) return "void";
        return type.Name;
    }
    static String ParameterTypeString(Type type)
    {
        if (type.IsByRef)
            return "ref " + type.Name.Remove(type.Name.Length - 1);
        return type.Name;
    }
}

// Patches .NET Assemblies so they can be used by ClrBridge.
// This tool normalizes namespace casing so that ClrBridgeCodegen can create
// unique files for each namespace.  This solves a problem on windows where files
// with the same characters but different casing are still the same file.
//
// TODO: output all the modifications so that we can patch assemblies that reference this assembly
//
using System;
using System.Collections.Generic;
using Mono.Cecil;

static class AssemblyPatcher
{
    static void Usage()
    {
        Console.WriteLine("Usage: AssemblyPatcher.exe [--options...] <AssemblyToPatch> <OutputAssembly>");
    }
    public static Int32 Main(String[] args)
    {
        List<String> nonOptionArgs = new List<String>();
        for (UInt32 i = 0; i < args.Length; i++)
        {
            String arg = args[i];
            if (!arg.StartsWith("-"))
                nonOptionArgs.Add(arg);
            else
            {
                Console.WriteLine("Error: unknown command-line option '{0}'", arg);
                return 1;
            }
        }
        if (nonOptionArgs.Count != 2)
        {
            Usage();
            return 1;
        }
        String inAssemblyFile = nonOptionArgs[0];
        String outAssemblyFile = nonOptionArgs[1];
        Console.WriteLine("in-assembly  : {0}", inAssemblyFile);
        Console.WriteLine("out-assembly : {0}", outAssemblyFile);
        ModuleDefinition module = ModuleDefinition.ReadModule(inAssemblyFile);
        UInt32 modifications = Patch(module);
        if (modifications == 0)
        {
            Console.WriteLine("Assembly '{0}' does not need to be patched", inAssemblyFile);
        }
        else
        {
            Console.WriteLine("Writing {0} modifications to new assembly to '{1}'...", modifications, outAssemblyFile);
            module.Write(outAssemblyFile);
        }
        return 0;
    }
    public static UInt32 Patch(ModuleDefinition module)
    {
        UInt32 modifications = 0;
        Dictionary<String,Boolean> namespaceMap = new Dictionary<String,Boolean>();
        Dictionary<String,String> namespaceUpperMap = new Dictionary<String,String>();
        foreach (TypeDefinition type in module.Types)
        {
            Boolean result;
            if (!namespaceMap.TryGetValue(type.Namespace, out result))
            {
                String namespaceUpper = type.Namespace.ToUpper();
                String conflictNamespace;
                if (namespaceUpperMap.TryGetValue(namespaceUpper, out conflictNamespace))
                {
                    Console.WriteLine("Namespace Conflict with type {0}:", type.FullName);
                    Console.WriteLine("    {0}", type.Namespace);
                    Console.WriteLine("    {0}", conflictNamespace);
                    type.Namespace = conflictNamespace;
                    modifications++;                    
                }
                else
                {
                    namespaceUpperMap.Add(namespaceUpper, type.Namespace);
                    namespaceMap.Add(type.Namespace, true);
                }
            }
        }
        return modifications;
    }
}

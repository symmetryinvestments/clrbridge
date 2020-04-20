using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;

class ConfigParseException : Exception
{
    public ConfigParseException(String msg) : base(msg)
    { }
}

class ConfigParser
{
    static readonly Char[] NewlineArray = new Char[] {'\n'};
    static readonly Char[] CarriageReturnArray = new Char[] {'\r'};

    readonly String filename;
    readonly String text;
    UInt32 lineNumber;
    Config config;
    AssemblyConfig currentAssembly;
    TypeConfig currentType;
    public ConfigParser(String filename, String text)
    {
        this.filename = filename;
        this.text = text;
    }
    ConfigParseException ParseException(String msg)
    {
        throw new ConfigParseException(String.Format("{0}(line {1}): {2}", filename, lineNumber, msg));
    }
    public Config Parse()
    {
        if (config != null) throw new InvalidOperationException();
        String[] lines = text.Split(NewlineArray);
        if (lines != null)
        {
            for (int i = 0; i < lines.Length; i++)
            {
                this.lineNumber = (UInt32)(i + 1);
                ParseLine(lines[i].Trim(CarriageReturnArray));
            }
        }
        if (config == null)
            throw ParseException("missing the 'Assemblies' directive");
        return config;
    }
    public void ParseLine(String line)
    {
        String remaining = line;
        String directive = Peel(ref remaining);
        if (directive.Length == 0 || directive.StartsWith("#")) return;
        if (directive == "Assemblies")
        {
            if (config != null)
                throw ParseException("found multiple 'Assemblies' directive");
            String optionalArg = Peel(ref remaining);
            Boolean whitelist;
            if (optionalArg.Length == 0)
                whitelist = false;
            else if (optionalArg.Equals("Whitelist", StringComparison.Ordinal))
                whitelist = true;
            else
                throw ParseException(String.Format(
                    "invalid argument '{0}' for 'Assemblies' directive, expected 'Whitelist' or nothing", optionalArg));
            EnforceDirectiveDone(directive, remaining);
            config = new Config(filename, whitelist);
        }
        // TODO: implement ExcludeAssembly (only allow if Assemblies is not in Whitelist mode)
        else if (directive == "DlangKeepNamespaceCasing")
        {
            EnforceInAssembliesConfig(directive);
            EnforceDirectiveDone(directive, remaining);
            config.dlangKeepNamespaceCasing = true;
        }
        else if (directive == "Assembly")
        {
            EnforceHaveAssembliesConfig(directive);
            String name = Peel(ref remaining);
            if (name.Length == 0)
                throw ParseException("the 'Assembly' directive requires a name");
            Boolean whitelist;
            String optionalArg = Peel(ref remaining);
            if (optionalArg.Length == 0)
                whitelist = false;
            else if (optionalArg.Equals("Whitelist", StringComparison.Ordinal))
                whitelist = true;
            else
                throw ParseException(String.Format(
                    "invalid argument '{0}' for 'Assembly' directive, expected 'Whitelist' or nothing", optionalArg));
            EnforceDirectiveDone(directive, remaining);

            this.currentType = null;
            this.currentAssembly = new AssemblyConfig(name, whitelist);
            config.assemblyMap.Add(name, this.currentAssembly);
        }
        // TODO: implement ExcludeType (only allow if the assembly is not in Whitelist mode)
        else if (directive == "Type")
        {
            EnforceHaveAssembly(directive);
            String name = Peel(ref remaining);
            if (name.Length == 0)
                throw ParseException("the 'Type' directive requires a name");
            EnforceDirectiveDone(directive, remaining);
            this.currentType = new TypeConfig(lineNumber, name);
            this.currentAssembly.typeMap.Add(name, this.currentType);
        }
        else if (directive == "ExcludeMethod")
        {
            EnforceHaveType(directive);
            String name = Peel(ref remaining);
            if (name.Length == 0)
                throw ParseException(String.Format("the '{0}' directive requires a name", directive));
            EnforceDirectiveDone(directive, remaining);
            if (!this.currentType.AddExcludeMethod(name))
                throw ParseException(String.Format("method '{0}' has already been excluded", name));
        }
        else throw ParseException(String.Format("Unknown directive '{0}'", directive));
    }

    void EnforceHaveAssembliesConfig(String directive)
    {
        if (config == null)
            throw ParseException(String.Format("directive '{0}' must appear after the 'Assemblies' directive", directive));
    }
    void EnforceInAssembliesConfig(String directive)
    {
        EnforceHaveAssembliesConfig(directive);
        if (currentAssembly != null)
            throw ParseException(String.Format("directive '{0}' must in the 'Assemblies' directive", directive));
    }

    void EnforceHaveAssembly(String directive)
    {
        if (currentAssembly == null)
            throw ParseException(String.Format("directive '{0}' must appear after an 'Assembly' directive", directive));
        Debug.Assert(config != null); // code bug if fails
    }

    void EnforceHaveType(String directive)
    {
        if (currentType == null)
            throw ParseException(String.Format("directive '{0}' must appear after a 'Type' directive", directive));
        Debug.Assert(currentAssembly != null); // code bug if fails
        Debug.Assert(config != null); // code bug if fails
    }
    void EnforceDirectiveDone(String directive, String remaining)
    {
        String afterPeel = remaining;
        String more = Peel(ref afterPeel);
        if (more.Length != 0)
            throw ParseException(String.Format("too many arguments for the '{0}' directive, extra is: {1}", directive, remaining));
    }
    String Peel(ref String line)
    {
        Int32 start = line.Skip(0, ' ');
        Int32 end = line.Until(start, ' ');
        if (start == end)
        {
            line = "";
            return "";
        }
        String result = line.Substring(start, end - start);
        line = line.Substring(end);
        return result;
    }
}
static class ParseExtensions
{
    public static Int32 Skip(this String s, Int32 offset, Char c)
    {
        for (;; offset++) {
            if (offset >= s.Length || s[offset] != c)
                return offset;
        }
    }
    public static Int32 Until(this String s, Int32 offset, Char c)
    {
        for (;; offset++) {
            if (offset >= s.Length || s[offset] == c)
                return offset;
        }
    }
}

class TypeConfig
{
    public readonly UInt32 lineNumber;
    public readonly String name;
    HashSet<String> excludeMethods;
    public TypeConfig(UInt32 lineNumber, String name)
    {
        this.lineNumber = lineNumber;
        this.name = name;
    }
    // returns: true if newly added, false if already added
    public Boolean AddExcludeMethod(String name)
    {
        if (excludeMethods == null) excludeMethods = new HashSet<String>();
        return excludeMethods.Add(name);
    }
    public Boolean CheckIsMethodDisabled(MethodInfo methodInfo)
    {
        return excludeMethods != null && excludeMethods.Contains(methodInfo.Name);
    }
    public Boolean AppearsIn(IEnumerable<Type> types)
    {
        foreach (Type type in types)
        {
            if (type.FullName == this.name)
                return true;
        }
        return false;
    }
}
class AssemblyConfig
{
    public readonly String name;
    public readonly Boolean whitelist;
    public readonly Dictionary<String,TypeConfig> typeMap = new Dictionary<String,TypeConfig>();
    public AssemblyConfig(String name, Boolean whitelist)
    {
        this.name = name;
        this.whitelist = whitelist;
    }
    /*
    public Boolean CheckIsTypeDisabled(Type type)
    {
        if (whitelist)
            return !typeMap.ContainsKey(type.FullName);
        // TODO: handle ExcludeTypes
        return false;
    }
    */
    // returns: null if type is disabled
    public TypeConfig TryGetTypeConfig(Type type)
    {
        TypeConfig typeConfig;
        if (!typeMap.TryGetValue(type.FullName, out typeConfig))
        {
            if (whitelist) return null;
            typeConfig = new TypeConfig(0, type.FullName);
            typeMap.Add(type.FullName, typeConfig);
        }
        return typeConfig;
    }
}
class Config
{
    public readonly String filename;
    public readonly Boolean whitelist;
    public readonly Dictionary<String,AssemblyConfig> assemblyMap = new Dictionary<String,AssemblyConfig>();
    public Boolean dlangKeepNamespaceCasing = false;
    public Config(String filename, Boolean whitelist)
    {
        this.filename = filename;
        this.whitelist = whitelist;
    }
    public AssemblyConfig GetAssemblyConfig(Assembly assembly)
    {
        String assemblyName = assembly.GetName().Name;
        AssemblyConfig assemblyConfig;
        if (!assemblyMap.TryGetValue(assemblyName, out assemblyConfig))
        {
            assemblyConfig = new AssemblyConfig(assemblyName, whitelist);
            assemblyMap.Add(assemblyName, assemblyConfig);
        }
        return assemblyConfig;
    }
}

using System;
using System.Collections.Generic;
using System.Reflection;

enum ListKind { Whitelist, Blacklist }

class ConfigParser
{
    static readonly Char[] NewlineArray = new Char[] {'\n'};

    readonly String filename;
    readonly String text;
    UInt32 lineNumber;
    AssemblyConfig currentAssembly;
    TypeConfig currentType;
    public ConfigParser(String filename, String text)
    {
        this.filename = filename;
        this.text = text;
    }
    Exception ParseException(String msg)
    {
        throw new Exception(String.Format("{0}(line {1}): {2}", filename, lineNumber, msg));
    }
    public Config Parse()
    {
        Config config = new Config(filename, true);
        String[] lines = text.Split(NewlineArray);
        if (lines != null)
        {
            for (int i = 0; i < lines.Length; i++)
            {
                this.lineNumber = (UInt32)(i + 1);
                ParseLine(config, lines[i]);
            }
        }
        return config;
    }
    public void ParseLine(Config config, String line)
    {
        String remaining = line;
        String directive = Peel(ref remaining);
        if (directive.Length == 0 || directive.StartsWith("#")) return;
        if (directive == "Assembly")
        {
            String name = Peel(ref remaining);
            if (name.Length == 0)
                throw ParseException("the 'Assembly' directive requires a name");
            String listKindString = Peel(ref remaining);
            if (listKindString.Length == 0)
                throw ParseException("the 'Assembly' directive is missing 'Whitelist' or 'Blacklist'");
            EnforceDirectiveDone(directive, remaining);
            ListKind listKind = ParseListKind(listKindString);

            this.currentType = null;
            this.currentAssembly = new AssemblyConfig(name, listKind);
            config.assemblyMap.Add(name, this.currentAssembly);
        }
        else if (directive == "Type")
        {
            String name = Peel(ref remaining);
            if (name.Length == 0)
                throw ParseException("the 'Type' directive requires a name");
            EnforceDirectiveDone(directive, remaining);
            if (currentAssembly == null)
                throw ParseException("the 'Type' directive cannot appear before an 'Assembly' directive");
            this.currentType = new TypeConfig(lineNumber, name);
            this.currentAssembly.typeMap.Add(name, this.currentType);
        }
        else throw ParseException(String.Format("Unknown directive '{0}'", directive));
    }
    ListKind ParseListKind(String str)
    {
        if (str.Equals("Whitelist", StringComparison.Ordinal)) return ListKind.Whitelist;
        if (str.Equals("Blacklist", StringComparison.Ordinal)) return ListKind.Blacklist;
        throw ParseException(String.Format("expected 'Whitelist' or 'Blacklist' but got '{0}'", str));
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
    public TypeConfig(UInt32 lineNumber, String name)
    {
        this.lineNumber = lineNumber;
        this.name = name;
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
    public readonly ListKind listKind;
    public readonly Dictionary<String,TypeConfig> typeMap = new Dictionary<String,TypeConfig>();
    public AssemblyConfig(String name, ListKind listKind)
    {
        this.name = name;
        this.listKind = listKind;
    }
    public IEnumerable<Type> EnumerateEnabledTypes(List<Type> types)
    {
        if (typeMap.Count == 0)
            return types;
        List<Type> filtered = new List<Type>();
        foreach (Type type in types)
        {
            if (TypeEnabled(type))
                filtered.Add(type);
        }
        return filtered;
    }
    public Boolean TypeEnabled(Type type)
    {
        TypeConfig typeConfig;
        if (typeMap.TryGetValue(type.FullName, out typeConfig))
            return false;
        return true;
    }
}
class Config
{
    public readonly String filename;
    public readonly Boolean whitelistAssemblies;
    public readonly Dictionary<String,AssemblyConfig> assemblyMap = new Dictionary<String,AssemblyConfig>();
    public Config(String filename, Boolean whitelistAssemblies)
    {
        this.filename = filename;
        this.whitelistAssemblies = whitelistAssemblies;
    }
    public AssemblyConfig GetAssemblyConfig(Assembly assembly)
    {
        AssemblyConfig assemblyConfig;
        if (assemblyMap.TryGetValue(assembly.GetName().Name, out assemblyConfig))
            return assemblyConfig;
        return null;
    }
}

// Generates D code to call C# code using the ClrBridge library
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

// TODO: maybe provide a way to configure assembly name to D package name map?
//       if I provide any configuration options, they should probably be in a file
//       and I would need to make sure that all .NET assemblies that have been translated
//       have the SAME configuration.  I might be able to verify this somehow?
class AlreadyReportedException : Exception
{
    public AlreadyReportedException() { }
}

static class ClrBridgeCodegen
{
    static void Usage()
    {
        Console.WriteLine("Usage: ClrBridgeCodegen.exe [--options...] <OutputDir> <DotNetAssemblies>...");
        Console.WriteLine("Options:");
        Console.WriteLine("  --shallow      Only generate for the given assembly, ignore assembly references");
        // TODO: add an option that says to use whatever config is already in outputDir
        //       in this case we verify that a config file exists in .metadat/config
        Console.WriteLine("  --config file  Specify a config file.  Must be the same file for each invocation");
        Console.WriteLine("                 on the same <OutputDir>.");
    }
    static String GetOptionArg(String[] args, ref UInt32 optionIndex)
    {
        optionIndex++;
        if (optionIndex >= args.Length)
        {
            Console.WriteLine("Error: option '{0}' requires an argument", args[optionIndex - 1]);
            throw new AlreadyReportedException();
        }
        return args[optionIndex];
    }
    public static Int32 Main(String[] args)
    {
        try { return Main2(args); }
        catch (AlreadyReportedException) { return 1; }
    }
    public static Int32 Main2(String[] args)
    {
        Boolean shallow = false;
        String configFile = null;
        List<String> nonOptionArgs = new List<String>();
        for (UInt32 i = 0; i < args.Length; i++)
        {
            String arg = args[i];
            if (!arg.StartsWith("-"))
                nonOptionArgs.Add(arg);
            else if (arg == "--shallow")
                shallow = true;
            //
            // Any options that change how the code is generated must be contained within the config file
            // the config file is copied to the output directory and is used to on future invocations
            // to ensure that the exact same configuration is used each time.
            //
            else if (arg == "--config")
                configFile = GetOptionArg(args, ref i);
            else
            {
                Console.WriteLine("Error: unknown command-line option '{0}'", arg);
                return 1;
            }
        }
        if (nonOptionArgs.Count < 2)
        {
            Usage();
            return 1;
        }
        String outputDir = nonOptionArgs[0];
        List<String> assemblyStrings = nonOptionArgs.GetRange(1, nonOptionArgs.Count - 1);

        Console.WriteLine("outputDir: {0}", outputDir);
        foreach (String assemblyString in assemblyStrings)
        {
            Console.WriteLine("assembly : {0}", assemblyString);
        }
        Console.WriteLine("shallow  : {0}", shallow);
        Console.WriteLine("config   : {0}", (configFile == null) ? "<none>" : configFile);

        // check output dir and config file
        String outputMetadataDir = Path.Combine(outputDir, ".metadata");
        String configMetadataCopy = Path.Combine(outputMetadataDir, "config");

        Boolean alreadyHaveConfig = File.Exists(configMetadataCopy);
        if (!alreadyHaveConfig)
        {
            Directory.CreateDirectory(outputMetadataDir);
            if (configFile != null)
                File.Copy(configFile, configMetadataCopy);
            else
                File.Create(configMetadataCopy).Dispose();
        }

        String configText = (configFile == null) ? "" : File.ReadAllText(configFile);

        // note that we don't have to check if configs match if we just copied it, but
        // it shouldn't do much harm to check anyway
        // if (alreadyHaveConfig)
        {
            String existingConfigText = File.ReadAllText(configMetadataCopy);
            if (existingConfigText != configText)
            {
                if (configFile == null)
                    Console.WriteLine("Error: missing --config file that was given on a previous invocation to output directory '{0}'", outputDir);
                else
                    Console.WriteLine("Error: new config file '{0}' does not match existing config in output directory '{1}'", configFile, outputDir);
                throw new AlreadyReportedException();
            }
            Console.WriteLine("[DEBUG] both configs match ({0} bytes)", configText.Length);
        }

        Config config;
        try
        {
            config = (configFile == null) ? new Config("", false) : new ConfigParser(configFile, configText).Parse();
        }
        catch (ConfigParseException e)
        {
            Console.WriteLine(e.Message);
            return 1;
        }

        AppDomain.CurrentDomain.AssemblyResolve += new ResolveEventHandler(AssemblyResolveCallback);

        Dictionary<Assembly, ExtraAssemblyInfo> sharedAssemblyMap = new Dictionary<Assembly, ExtraAssemblyInfo>();
        List<TempPackage> newlyGeneratedAssemblies = new List<TempPackage>();
        foreach (String assemblyString in assemblyStrings)
        {
            Assembly assembly;
            if (assemblyString.StartsWith("file:"))
            {
                String fileName = Path.GetFullPath(assemblyString.Substring(5));
                ExtraAssemblyPaths.Add(Path.GetDirectoryName(fileName));
                assembly = Assembly.LoadFile(fileName);
            }
            else if (assemblyString.StartsWith("gac:"))
                assembly = Assembly.Load(assemblyString.Substring(4));
            else
            {
                Console.WriteLine("Error: assembly string must start with 'file:' or 'gac:' but got '{0}'", assemblyString);
                return 1;
            }
            TempPackage tempPackage = new Generator(config, sharedAssemblyMap, assembly, outputDir,
                config.GetAssemblyConfig(assembly)).GenerateModules(false);
            if (!tempPackage.IsNull())
                newlyGeneratedAssemblies.Add(tempPackage);
        }
        if (!shallow)
        {
            for (;;)
            {
                Int32 generatedCount = 0;
                foreach (var pair in sharedAssemblyMap)
                {
                    if (pair.Value.state == AssemblyState.Initial)
                    {
                        TempPackage tempPackage = new Generator(config, sharedAssemblyMap, pair.Key, outputDir,
                            config.GetAssemblyConfig(pair.Key)).GenerateModules(false);
                        if (!tempPackage.IsNull())
                            newlyGeneratedAssemblies.Add(tempPackage);
                        Debug.Assert(pair.Value.state == AssemblyState.Generated);
                        break; // break out of the loop because the map would have been modified
                    }
                    Debug.Assert(pair.Value.state == AssemblyState.Generated);
                    generatedCount++;
                }
                if (generatedCount == sharedAssemblyMap.Count)
                    break;
            }
        }
        // Move assemblies to their final location
        // We do this at the end so that if an assembly fails, we regenerate all assemblies, otherwise,
        // an assembly that caused another assembly to be generated could have succeeded and then won't cause
        // the failed assembly to be loaded in a future run
        foreach (TempPackage pkg in newlyGeneratedAssemblies)
        {
            Console.WriteLine("moving temporary package dir '{0}' to final package dir '{1}'", pkg.tempDir, pkg.finalDir);
            Directory.Move(pkg.tempDir, pkg.finalDir);
        }
        Console.WriteLine("all {0} assemblies have been generated", sharedAssemblyMap.Count);
        return 0;
    }
    static readonly List<String> ExtraAssemblyPaths = new List<String>();
    static Assembly AssemblyResolveCallback(Object sender, ResolveEventArgs args)
    {
        Console.WriteLine("[DEBUG] Resolving Assembly '{0}'...", args.Name);
        String shortName = args.Name;
        {
            Int32 commaIndex = args.Name.IndexOf(",");
            if (commaIndex != -1)
                shortName = args.Name.Remove(commaIndex);
        }
        Console.WriteLine("[DEBUG]    shortname '{0}'", shortName);
        foreach (String extraPath in ExtraAssemblyPaths)
        {
            String assemblyFile = Path.Combine(extraPath, shortName + ".dll");
            Console.WriteLine("[DEBUG]    checking for '{0}'", assemblyFile);
            if (File.Exists(assemblyFile))
            {
                Console.WriteLine("[DEBUG]     => resolved to file '{0}'", assemblyFile);
                return Assembly.LoadFile(assemblyFile);
            }
        }
        Console.WriteLine("[DEBUG]     => NOT FOUND!");
        return null;
    }
}

struct TempPackage
{
    public static TempPackage NullValue() { return new TempPackage(null, null); }
    public readonly String tempDir;
    public readonly String finalDir;
    public TempPackage(String tempDir, String finalDir)
    {
        this.tempDir = tempDir;
        this.finalDir = finalDir;
    }
    public Boolean IsNull() { return tempDir == null; }
}

class ExtraReflection
{
    protected readonly Dictionary<Assembly, ExtraAssemblyInfo> sharedAssemblyMap;
    protected readonly Assembly thisAssembly;
    protected readonly Dictionary<Type, ExtraTypeInfo> typeInfoMap;
    public ExtraReflection(Dictionary<Assembly, ExtraAssemblyInfo> sharedAssemblyMap, Assembly thisAssembly)
    {
        this.sharedAssemblyMap = sharedAssemblyMap;
        this.thisAssembly = thisAssembly;
        this.typeInfoMap = new Dictionary<Type,ExtraTypeInfo>();
    }

    public ExtraAssemblyInfo GetExtraAssemblyInfo(Assembly assembly)
    {
        ExtraAssemblyInfo info;
        if (!sharedAssemblyMap.TryGetValue(assembly, out info))
        {
            info = new ExtraAssemblyInfo(
                assembly.GetName().Name.Replace(".", "_")
            );
            sharedAssemblyMap[assembly] = info;
        }
        return info;
    }
    public ExtraTypeInfo GetExtraTypeInfo(Type type)
    {
        ExtraTypeInfo info;
        if (!typeInfoMap.TryGetValue(type, out info))
        {
            ExtraAssemblyInfo assemblyInfo = GetExtraAssemblyInfo(type.Assembly);
            String moduleName = type.Namespace.IsEmpty() ? assemblyInfo.packageName :
                String.Format("{0}.{1}", assemblyInfo.packageName, type.Namespace.ToDQualifiedIdentifier());
            String moduleRelativeName = type.GetUnqualifiedTypeNameForD();
            if (type.DeclaringType != null)
                moduleRelativeName = String.Format("{0}.{1}", GetExtraTypeInfo(type.DeclaringType).moduleRelativeName, moduleRelativeName);
            info = new ExtraTypeInfo(moduleName, moduleRelativeName);
            typeInfoMap[type] = info;
        }
        return info;
    }

    // namespaceContext is the C# Namespace for which code is currently being generated
    public String ToDMarshalType(String namespaceContext, Type type)
    {
        if (type == typeof(Boolean)) return "ushort";
        String importQualifier;
        return ToDEquivalentType(namespaceContext, type, out importQualifier);
    }

    // TODO: add TypeContext?  like fieldDecl?  Might change const(char)* to string in some cases?
    // namespaceContext is the C# Namespace for which code is currently being generated
    public String ToDEquivalentType(String namespaceContext, Type type, out String importQualifier)
    {
        // skip these types for now
        if (type.IsByRef || type.IsPointer)
        {
            importQualifier = ""; // no import necessary
            return type.UnsupportedTypeRef();
        /*
            Type elementType = type.GetElementType();
            Debug.Assert(elementType != type);
            return "ref " + ToDEquivalentType(namespaceContext, elementType);
            */
        }

        if (type.IsGenericParameter)
        {
            importQualifier = ""; // no import necessary
            return type.Name.ToDIdentifier();
        }

        Debug.Assert(type != typeof(void)); // not handled yet
        if (type == typeof(Boolean)) { importQualifier = ""; return "bool"; }
        if (type == typeof(Byte))    { importQualifier = ""; return "ubyte"; }
        if (type == typeof(SByte))   { importQualifier = ""; return "byte"; }
        if (type == typeof(UInt16))  { importQualifier = ""; return "ushort"; }
        if (type == typeof(Int16))   { importQualifier = ""; return "short"; }
        if (type == typeof(UInt32))  { importQualifier = ""; return "uint"; }
        if (type == typeof(Int32))   { importQualifier = ""; return "int"; }
        if (type == typeof(UInt64))  { importQualifier = ""; return "ulong"; }
        if (type == typeof(Int64))   { importQualifier = ""; return "long"; }
        if (type == typeof(Char))    { importQualifier = ""; return "char"; }
        if (type == typeof(String))  { importQualifier = ""; return "__d.CString"; }
        if (type == typeof(Single))  { importQualifier = ""; return "float"; }
        if (type == typeof(Double))  { importQualifier = ""; return "double"; }
        if (type == typeof(Decimal)) { importQualifier = ""; return "__d.clr.Decimal"; }
        // TODO: figure out how to properly handle IntPtr
        //if (type == typeof(System.IntPtr)) { importQualifier = ""; return "void*"; }
        // TODO: using this causes D compiler to take too much memory while compiling mscorlib
        //       so for now I'm disabling it by using __d.clr.DotNetObject instead
        //if (type == typeof(Object))  { importQualifier = "mscorlib.System"; return "mscorlib.System.MscorlibObject"; }
        if (type == typeof(Object))  { importQualifier = ""; return "__d.clr.DotNetObject"; }

        // TODO: do this for all types, not just enums
        // we need to include the qualifier even on types in the same module so their names don't conflict
        // with other symbols in this same module (like methods/variables)
        Boolean useRealType = false;
        if (type.IsEnum)
        {
            useRealType = true;
        }
        else if (
               !type.IsGenericType // skip generic types for now
            && !type.IsArray // skip arrays for now
            && !(typeof(Delegate).IsAssignableFrom(type)) // skip delegates for now
            && !type.IsValueType // skip value types for now
        )
        {
            useRealType = true;
        }
        if (useRealType)
        {
            ExtraTypeInfo typeInfo = GetExtraTypeInfo(type);
            if (type.Assembly == thisAssembly && namespaceContext == type.Namespace)
            {
                importQualifier = "";
            }
            else
            {
                // from import idiom does not work with circular references :(
                //importQualifier = String.Format("__d.clrbridge.from!\"{0}\"", typeInfo.moduleName);
                importQualifier = typeInfo.moduleName;
            }
            return String.Format("{0}.{1}", importQualifier, typeInfo.moduleRelativeName);
        }

        // references to this type are temporarily disabled, so for now we just treat it as a generic Object
        importQualifier = "";
        return type.UnsupportedTypeRef();
    }
}

class Generator : ExtraReflection
{
    readonly Config config;
    readonly String outputDir;
    readonly Dictionary<String,DModule> moduleMap;
    readonly Dictionary<String,DModule> moduleUpperCaseMap;
    readonly String thisAssemblyPackageName; // cached version of GetExtraAssemblyInfo(thisAssembly).packageName
    readonly String finalPackageDir;
    readonly String tempPackageDir;
    readonly AssemblyConfig assemblyConfig;

    public Generator(Config config, Dictionary<Assembly, ExtraAssemblyInfo> sharedAssemblyMap, Assembly thisAssembly, String outputDir, AssemblyConfig assemblyConfig)
        : base(sharedAssemblyMap, thisAssembly)
    {
        this.config = config;
        this.outputDir = outputDir;
        this.moduleMap = new Dictionary<String,DModule>();
        this.moduleUpperCaseMap = new Dictionary<String,DModule>();
        this.thisAssemblyPackageName = GetExtraAssemblyInfo(thisAssembly).packageName;
        this.finalPackageDir = Path.Combine(outputDir, this.thisAssemblyPackageName);
        this.tempPackageDir = this.finalPackageDir + ".generating";
        this.assemblyConfig = assemblyConfig;
    }

    String TryReadLastGeneratedHash()
    {
        String hashFile = Path.Combine(finalPackageDir, "AssemblyHash");
        if (!File.Exists(hashFile))
            return null;
        String lastGeneratedHash = File.ReadAllText(hashFile);
        if (lastGeneratedHash.Length != 32)
            throw new Exception(String.Format("assembly hash file should be 32 characters but got {0}", lastGeneratedHash.Length));
        return lastGeneratedHash;
    }

    // returns: the temporary directory of the assembly if it was newly generated
    public TempPackage GenerateModules(bool force)
    {
        ExtraAssemblyInfo thisAssemblyInfo = GetExtraAssemblyInfo(thisAssembly);
        Debug.Assert(thisAssemblyInfo.state == AssemblyState.Initial);
        thisAssemblyInfo.state = AssemblyState.Generating;
        Boolean result = GenerateModules2(force);
        Debug.Assert(thisAssemblyInfo.state == AssemblyState.Generating);
        thisAssemblyInfo.state = AssemblyState.Generated;
        return result ? new TempPackage(tempPackageDir, finalPackageDir) : TempPackage.NullValue();
    }

    // returns: true if it is newly generated, false if it is already generated
    Boolean GenerateModules2(bool force)
    {
        // Rather than completely skipping the assembly when it is disabled, I'm stil going to generate it,
        // but all the types will be empty.  This means they can still be referenced like normal so other assemblies
        // won't need to know that they are disabled.

        // hash the assembly, so we can check if it is already generated
        // and then save it once we are done so it can be checked later
        String assemblyHash;
        using (FileStream stream = File.Open(thisAssembly.Location,  FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var md5 = System.Security.Cryptography.MD5.Create();
            assemblyHash = HexString.FromBytes(md5.ComputeHash(stream));
            Debug.Assert(assemblyHash.Length == 32);
        }
        if (!force)
        {
            String lastGeneratedHash = TryReadLastGeneratedHash();
            if (lastGeneratedHash == assemblyHash)
            {
                Console.WriteLine("code already generated for assembly '{0}', hash={1}", thisAssembly, assemblyHash);
                return false; // already generated
            }
        }
        if (Directory.Exists(tempPackageDir))
        {
            Console.WriteLine("deleting old temporary package dir '{0}'", tempPackageDir);
            Directory.Delete(tempPackageDir, true);
        }

        Type[] allTypes = thisAssembly.GetTypes();

        // Check that there are no undefined types configured
        if (assemblyConfig != null)
        {
            HashSet<TypeConfig> typeConfigsFound = new HashSet<TypeConfig>();
            foreach (Type type in allTypes)
            {
                TypeConfig typeConfig;
                if (assemblyConfig.typeMap.TryGetValue(type.FullName, out typeConfig))
                {
                    typeConfigsFound.Add(typeConfig);
                }
            }
            if (typeConfigsFound.Count != assemblyConfig.typeMap.Count)
            {
                foreach (TypeConfig typeConfig in assemblyConfig.typeMap.Values)
                {
                    if (!typeConfigsFound.Contains(typeConfig))
                    {
                        Console.WriteLine("{0}({1}) Error: type '{2}' does not exist in assembly '{3}'",
                            config.filename, typeConfig.lineNumber, typeConfig.name, assemblyConfig.name);
                    }
                }
                throw new AlreadyReportedException();
            }
        }

        List<Type> rootTypes = new List<Type>();
        foreach (Type type in allTypes)
        {
            if (type.DeclaringType != null)
                GetExtraTypeInfo(type.DeclaringType).subTypes.Add(type);
            else
                rootTypes.Add(type);
        }

        foreach (Type type in rootTypes)
        {
            //writer.WriteLine("type {0}", type);
            DModule module;
            if (!moduleMap.TryGetValue(type.Namespace.NullToEmpty(), out module))
            {
                String namespaceUpper = type.Namespace.NullToEmpty().ToUpper();
                if (moduleUpperCaseMap.TryGetValue(namespaceUpper, out module))
                {
                    // This is a problem because we cannot create files/directories that only differ in casing on windows.
                    // Futhermore, the code could be generated on windows/linux and move to or from the other so we shouldn't
                    // generated different code for windows/linux.
                    // One solution would be to normalize all the namespaces to lowercase (D style), however that would cause
                    // a problem if a C# application intentionally used different case to declare the same symbols.
                    // For now, I'll assert an error if this happens, and maybe write a tool to fix an assembly that has this problem.
                    Console.WriteLine("Error: there are multiple namespaces that match but have different upper/lower casing:");
                    Console.WriteLine("    {0}", module.dotnetNamespace);
                    Console.WriteLine("    {0}", type.Namespace);
                    throw new AlreadyReportedException();
                }
                String outputDFilename = Path.Combine(tempPackageDir, Util.NamespaceToModulePath(type.Namespace));
                Console.WriteLine("[DEBUG] NewDModule '{0}'", outputDFilename);
                Directory.CreateDirectory(Path.GetDirectoryName(outputDFilename));
                StreamWriter writer = new StreamWriter(new FileStream(outputDFilename, FileMode.Create, FileAccess.Write, FileShare.Read));
                ExtraTypeInfo typeInfo = GetExtraTypeInfo(type);
                module = new DModule(thisAssembly, type.Namespace, typeInfo.moduleName, writer);
                writer.WriteLine("module {0};", typeInfo.moduleName);
                writer.WriteLine("");
                writer.WriteLine("// Keep D Symbols inside the __d struct to prevent symbol conflicts");
                writer.WriteLine("struct __d");
                writer.WriteLine("{");
                writer.WriteLine("    import cstring : CString, CStringLiteral;");
                writer.WriteLine("    static import clr;");
                writer.WriteLine("    static import clrbridge;");
                writer.WriteLine("    import clrbridge.global : globalClrBridge;");
                writer.WriteLine("    alias ObjectArray = clrbridge.Array!(clr.PrimitiveType.Object);");
                writer.WriteLine("}");
                moduleMap.Add(type.Namespace.NullToEmpty(), module);
                moduleUpperCaseMap.Add(namespaceUpper, module);
            }
            GenerateType(module, type);
        }

        foreach (DModule module in moduleMap.Values)
        {
            module.Dispose();
        }

        String allSourceFile = Path.Combine(tempPackageDir, "all.d");
        Directory.CreateDirectory(Path.GetDirectoryName(allSourceFile));
        using (StreamWriter writer = new StreamWriter(new FileStream(allSourceFile, FileMode.Create, FileAccess.Write, FileShare.Read)))
        {
            writer.WriteLine("module {0}.all;", thisAssemblyPackageName);
            foreach (DModule module in moduleMap.Values)
            {
                writer.WriteLine("public import {0};", module.fullName);
            }
        }

        String assemblyHashFile = Path.Combine(tempPackageDir, "AssemblyHash");
        Console.WriteLine("writing assembly hash file '{0}' with '{1}'", assemblyHashFile, assemblyHash);
        File.WriteAllText(assemblyHashFile, assemblyHash);
        return true; // newly generated
    }

    public static void GenerateImports(DContext context, IEnumerable<ModuleTypeRef> typeRefs)
    {
        HashSet<String> imports = new HashSet<String>();
        foreach (ModuleTypeRef typeRef in typeRefs)
        {
            if (!typeRef.importQualifier.IsEmpty() && imports.Add(typeRef.importQualifier))
            {
                // static imports are not lazy and make it take WAAAAY to long to compile
                // not sure how to solve this one
                // the from import idiom does not seem to work with circular references
                context.WriteLine("static import {0};", typeRef.importQualifier);
            }
        }
    }

    void GenerateType(DContext context, Type type)
    {
        if (type.IsValueType)
        {
            if (type.IsEnum)
            {
                Debug.Assert(!type.IsGenericType, "enum types can be generic?");
                GenerateEnum(context, type);
            }
            else
            {
                GenerateStruct(context, type);
            }
        }
        else if (type.IsInterface)
        {
            GenerateInterface(context, type);
        }
        else
        {
            Debug.Assert(type.IsClass);
            if (typeof(Delegate).IsAssignableFrom(type))
            {
                GenerateDelegate(context, type);
            }
            else
            {
                GenerateClass(context, type);
            }
        }
    }

    void Message(DModule module, String fmt, params Object[] args)
    {
        String message = String.Format(fmt, args);
        Console.WriteLine(message);
        module.WriteLine("/* {0} */", message);
    }

    void GenerateEnum(DContext baseContext, Type type)
    {
        const String EnumValueFieldName = "__value__";
        TypeConfig typeConfigOrDisabled = assemblyConfig.TryGetTypeConfig(type);
        baseContext.WriteLine("/* .NET enum{0} */ static struct {1}",
            (typeConfigOrDisabled == null) ? " (disabled)" : "", Util.GetUnqualifiedTypeNameForD(type));
        baseContext.EnterBlock();
        using (DTypeContext context = new DTypeContext(baseContext))
        {
            Type[] genericArgs = type.GetGenericArguments();
            Debug.Assert(genericArgs.IsEmpty(), "enums can have generic arguments???");
            GenerateMetadata(context, type, genericArgs);
            // We still have to generate some fields for enums even when they are disabled
            // because they are value types
            String baseTypeDName = context.TypeReferenceForD(this, Enum.GetUnderlyingType(type)); // TODO: Marshal Type instead???
            context.WriteLine("__d.clr.Enum!{0} {1};", baseTypeDName, EnumValueFieldName);
            context.WriteLine("alias {0} this;", EnumValueFieldName);
            if (typeConfigOrDisabled != null)
            {
                context.WriteLine("enum : typeof(this)", baseTypeDName);
                context.WriteLine("{");
                UInt32 nonStaticFieldCount = 0;
                foreach (FieldInfo field in type.GetFields())
                {
                    Debug.Assert(field.DeclaringType == type);
                    Debug.Assert(field.FieldType == type);
                    if (!field.IsStatic)
                    {
                        Debug.Assert(field.Name == EnumValueFieldName);
                        nonStaticFieldCount++;
                        continue;
                    }
                    context.WriteLine("    {0} = typeof(this)(__d.clr.Enum!{1}({2})),", Util.ToDIdentifier(field.Name), baseTypeDName, field.GetRawConstantValue());
                }
                context.WriteLine("}");
                Debug.Assert(nonStaticFieldCount == 1);

                // Commenting out for now because of a conflict with TypeNameKind ToString
                // It looks like C# might allow field names and method names to have the same symbol?
                // I'll need to see in which cases C# allows this, maybe only with static fields?
                // If so, the right solution would probably be to modify the field name that conflicts.
                //GenerateMethods(context, type);
                /*
                foreach (var method in type.GetMethods())
                {
                    context.WriteLine("// TODO: generate something for enum method {0}", method);
                }
                */

                // Generate opMethods so this behaves like an enum
                context.WriteLine("typeof(this) opBinary(string op)(const typeof(this) right) const");
                context.WriteLine("{ return typeof(this)(mixin(\"this.__value__ \" ~ op ~ \" right.__value__\")); }");
                // TODO: there's probably more (or less) to generate to get the behavior right
            }
        }
        baseContext.ExitBlock();
    }

    void GenerateStruct(DContext context, Type type)
    {
        TypeConfig typeConfigOrDisabled = assemblyConfig.TryGetTypeConfig(type);
        context.Write("/* .NET struct{0} */ static struct {1}",
            (typeConfigOrDisabled == null) ? " (disabled)" : "", Util.GetUnqualifiedTypeNameForD(type));
        Type[] genericArgs = type.GetGenericArguments();
        GenerateGenericParameters(context, genericArgs, type.DeclaringType.GetGenericArgCount());
        context.WriteLine();
        context.EnterBlock();
        using (DTypeContext typeContext = new DTypeContext(context))
        {
            GenerateMetadata(typeContext, type, genericArgs);
            if (typeConfigOrDisabled != null)
            {
                GenerateFields(typeContext, type);
                GenerateMethods(typeContext, type, typeConfigOrDisabled);
            }
            GenerateSubTypes(typeContext, type);
        }
        context.ExitBlock();
    }

    void GenerateDelegate(DContext context, Type type)
    {
        TypeConfig typeConfigOrDisabled = assemblyConfig.TryGetTypeConfig(type);
        context.Write("/* .NET delegate{0} */ static struct {1}",
            (typeConfigOrDisabled == null) ? " (disabled)" : "", Util.GetUnqualifiedTypeNameForD(type));
        Type[] genericArgs = type.GetGenericArguments();
        GenerateGenericParameters(context, genericArgs, type.DeclaringType.GetGenericArgCount());
        context.WriteLine();
        context.EnterBlock();
        if (typeConfigOrDisabled != null)
        {
            context.WriteLine("// TODO: generate delegate members");
        }
        context.ExitBlock();
    }

    void GenerateInterface(DContext context, Type type)
    {
        TypeConfig typeConfigOrDisabled = assemblyConfig.TryGetTypeConfig(type);
        context.Write("/* .NET interface{0} */ struct {1}",
            (typeConfigOrDisabled == null) ? " (disabled)" : "", Util.GetUnqualifiedTypeNameForD(type));
        Type[] genericArgs = type.GetGenericArguments();
        GenerateGenericParameters(context, genericArgs, type.DeclaringType.GetGenericArgCount());
        context.WriteLine();
        context.EnterBlock();
        using (DTypeContext typeContext = new DTypeContext(context))
        {
            Debug.Assert(type.GetFields().Length == 0);
            String baseTypeForD = typeContext.TypeReferenceForD(this, (type.BaseType == null) ? typeof(System.Object) : type.BaseType);
            typeContext.WriteLine("mixin __d.clrbridge.DotNetObjectMixin!({0});", baseTypeForD);
            GenerateMetadata(typeContext, type, genericArgs);
            if (typeConfigOrDisabled != null)
            {
                GenerateMethods(typeContext, type, typeConfigOrDisabled);
            }
            GenerateSubTypes(typeContext, type);
        }
        context.ExitBlock();
    }

    void GenerateClass(DContext context, Type type)
    {
        TypeConfig typeConfigOrDisabled = assemblyConfig.TryGetTypeConfig(type);
        context.Write("/* .NET class{0} */ static struct {1}",
            (typeConfigOrDisabled == null) ? " (disabled)" : "", Util.GetUnqualifiedTypeNameForD(type));
        Type[] genericArgs = type.GetGenericArguments();
        GenerateGenericParameters(context, genericArgs, type.DeclaringType.GetGenericArgCount());
        context.WriteLine();
        context.EnterBlock();
        using (DTypeContext typeContext = new DTypeContext(context))
        {
            String baseTypeForD;
            if (type == typeof(Object))
                baseTypeForD = "__d.clr.DotNetObject";
            else
            {
                Type baseType = (type.BaseType == null) ? typeof(System.Object) : type.BaseType;
                // this is a hack, I should not have this 'if' clause but if I don't do this then
                // the D compiler runs out of memory trying to compile mscorlib on my 8 GB System!
                if (type.BaseType == null)
                    baseTypeForD = "__d.clr.DotNetObject";
                else
                    baseTypeForD = typeContext.TypeReferenceForD(this, baseType);
            }
            typeContext.WriteLine("mixin __d.clrbridge.DotNetObjectMixin!({0});", baseTypeForD);
            GenerateMetadata(typeContext, type, genericArgs);
            if (typeConfigOrDisabled != null)
            {
                // generate metadata, one reason for this is so that when this type is used as a template parameter, we can
                // get the .NET name for this type
                GenerateFields(typeContext, type);
                GenerateMethods(typeContext, type, typeConfigOrDisabled);
            }
            GenerateSubTypes(typeContext, type);
        }
        context.ExitBlock();
    }

    // generates a multi-line expression that creates a TypeSpec
    // assumes code starts in the middle of a line where the expression starts,
    // linePrefix is the prefix for new line of the expression
    void GenerateTypeSpecExpression(DContext context, String linePrefix, Type type)
    {
        GenerateTypeSpecExpression(context, linePrefix, type, type.GetGenericArguments());
    }
    void GenerateTypeSpecExpression(DContext context, String linePrefix, Type type, Type[] genericArgs)
    {
        if (type.IsGenericParameter)
        {
            Debug.Assert(genericArgs.IsEmpty(), "you can have a generic parameter type with generic args??");
            context.Write("__d.clrbridge.GetTypeSpec!({0})", context.TypeReferenceForD(this, type));
            return;
        }
        context.WriteLine("__d.clr.TypeSpec(");
        context.WriteLine("{0}\"{1}\",", linePrefix, type.Assembly.FullName);
        bool hasGenerics = !genericArgs.IsEmpty();
        context.Write("{0}\"{1}\"{2}", linePrefix, type.FullName, hasGenerics ? ", [" : ")", type.Name);
        if (hasGenerics)
        {
            context.WriteLine();
            foreach (Type genericArg in genericArgs)
            {
                context.WriteLine("{0}    __d.clrbridge.GetTypeSpec!({1}),", linePrefix, context.TypeReferenceForD(this, genericArg));
            }
            context.Write("{0}])", linePrefix);
        }
    }

    // TODO: remove this?
    void GenerateGenericTypeSpecsExpression(DContext context, String linePrefix, Type[] genericArgs)
    {
        if (genericArgs.IsEmpty())
            context.Write("null");
        else
        {
            context.WriteLine("[");
            foreach (Type genericArg in genericArgs)
            {
                context.WriteLine("{0}    __d.clrbridge.GetTypeSpec!({1}),", linePrefix, context.TypeReferenceForD(this, genericArg));
            }
            context.Write("{0}]", linePrefix);
        }
    }
    void GenerateParameterTypeSpecExpression(DContext context, String linePrefix, ParameterInfo[] paramInfos)
    {
        if (paramInfos.IsEmpty())
            context.Write("null");
        else
        {
            context.WriteLine("[");
            String subTypePrefix = linePrefix + "        ";
            foreach (ParameterInfo paramInfo in paramInfos)
            {
                //context.WriteLine("{0}   {1},", linePrefix, TypeSpecReference(paramInfo.ParameterType));
                context.Write("{0}    /* param '{1}' */", linePrefix, paramInfo.Name);
                GenerateTypeSpecExpression(context, subTypePrefix, paramInfo.ParameterType);
                context.WriteLine(",");
            }
            context.Write("{0}]", linePrefix);
        }
    }

    void GenerateMetadata(DContext context, Type type, Type[] genericArgs)
    {
        context.WriteLine("static struct __clrmetadata");
        context.WriteLine("{");
        context.Write("    enum typeSpec = ");
        GenerateTypeSpecExpression(context, "        ", type, genericArgs);
        context.WriteLine(";");
        context.WriteLine("}");
    }

    void GenerateFields(DContext context, Type type)
    {
        foreach (FieldInfo field in type.GetFields())
        {
            Type fieldType = field.FieldType;
            // fields are represented as D @property functions
            // TODO: generate the setter as well
            context.WriteLine("@property {0} {1}() const {{ assert(0, \"fields not implemented yet\"); }}; // {2} {3}",
                context.TypeReferenceForD(this, fieldType),
                field.Name.ToDIdentifier(),
                field.FieldType, field.FieldType.AssemblyQualifiedName);
        }
    }

    void GenerateMethods(DTypeContext context, Type type, TypeConfig typeConfig)
    {
        Debug.Assert(typeConfig != null);
        foreach (ConstructorInfo constructor in type.GetConstructors())
        {
            if (type.IsValueType)
                continue; // script structs for now
            Debug.Assert(constructor.GetGenericArguments().IsEmpty(), "constructors can have generic arguments?");
            context.Write("{0} static typeof(this) New", constructor.IsPrivate ? "private" : "public");
            ParameterInfo[] parameters = constructor.GetParameters();
            GenerateParameterList(context, parameters);
            context.WriteLine();
            context.EnterBlock();
            using (DMethodContext methodContext = new DMethodContext(context))
            {
                GenerateMethodBody(methodContext, type, constructor, type, parameters);
            }
            context.ExitBlock();
        }
        // We put all the property methods in a hash set so we can quickly test
        // any method to see if it is a property
        HashSet<MethodInfo> propertyMethods = new HashSet<MethodInfo>();
        foreach (PropertyInfo property in type.GetProperties())
        {
            {
                MethodInfo method = property.GetGetMethod(false);
                if (method != null) propertyMethods.Add(method);
            }
            {
                MethodInfo method = property.GetSetMethod(false);
                if (method != null) propertyMethods.Add(method);
            }
        }
        foreach (MethodInfo method in type.GetMethods())
        {
            if (typeConfig.CheckIsMethodDisabled(method))
            {
                context.WriteLine("// ExcludeMethod {0}", method.Name);
                continue;
            }

            // skip methods that are not declared by this type to avoid symbol issues for now
            if (method.DeclaringType != type)
            {
                context.WriteLine("// skipping method '{0}' becuase it is declared in another type '{1}'",
                    method.Name, method.DeclaringType);
                continue;
            }

            Boolean isProperty = propertyMethods.Contains(method);
            if (isProperty)
                context.Write("@property ");
            context.Write("{0}", method.IsPrivate ? "private" : "public");
            if (method.IsStatic)
            {
                context.Write(" static");
            }
            else if (method.IsFinal)
            {
                context.Write(" final");
            }

            Type[] genericArguments = method.GetGenericArguments();
            Debug.Assert(method.ReturnType != null);
            if (method.ReturnType == typeof(void))
                context.Write(" void");
            else
                context.Write(" {0}", context.TypeReferenceForD(this, method.ReturnType));

            {
                String dIdentifier = Util.ToDIdentifier(method.Name);
                if (isProperty)
                {
                    if (dIdentifier.StartsWith("get_"))
                        dIdentifier = dIdentifier.Substring(4);
                    else if (dIdentifier.StartsWith("set_"))
                        dIdentifier = dIdentifier.Substring(4);
                    else
                        throw new Exception(String.Format("all property methods are expected to start with 'get_' or 'set_' but found '{0}'", dIdentifier));
                }
                context.Write(" {0}", dIdentifier);
            }
            ParameterInfo[] parameters = method.GetParameters();
            GenerateGenericParameters(context, genericArguments, type.GetGenericArgCount());
            GenerateParameterList(context, parameters);
            if (!method.IsStatic)
                context.Write(" const"); // all methods are const because the struct is just a handle to a C# object
            context.WriteLine();
            context.EnterBlock();
            using (DMethodContext methodContext = new DMethodContext(context))
            {
                GenerateMethodBody(methodContext, type, method, method.ReturnType, parameters);
            }
            context.ExitBlock();
        }
    }

    void GenerateGenericParameters(DContext context, Type[] genericArgs, UInt16 inheritedGenericArgCount)
    {
        if (genericArgs != null && inheritedGenericArgCount < genericArgs.Length)
        {
            context.Write("(");
            string prefix = "";
            // we skip inherited generic args because they will be in the containing template
            for (Int32 i = inheritedGenericArgCount; i < genericArgs.Length; i++)
            {
                Type t = genericArgs[i];
                context.Write("{0}{1}", prefix, t.Name.ToDIdentifier());
                prefix = ", ";
            }
            context.Write(")");
        }
    }

    void GenerateParameterList(DContext module, ParameterInfo[] parameters)
    {
        module.Write("(");
        {
            string prefix = "";
            foreach (ParameterInfo parameter in parameters)
            {
                module.Write("{0}{1} {2}", prefix, module.TypeReferenceForD(this, parameter.ParameterType), parameter.Name.ToDIdentifier());
                prefix = ", ";
            }
        }
        module.Write(")");
    }

    void GenerateMethodBody(DMethodContext context, Type type,
        MethodBase method, Type returnType, ParameterInfo[] parameters)
    {
        String methodKind = method.IsConstructor ? "Constructor" : "Method";

        // TODO: we may want to cache some of this stuff, but for now we'll just get it every time
        Type[] genericArgs = method.IsGenericMethod ? method.GetGenericArguments() : null;
        context.WriteLine("enum __method_spec__ = __d.clrbridge.{0}Spec(__clrmetadata.typeSpec,", methodKind);
        context.IncreaseDepth();
        if (!method.IsConstructor)
        {
            context.WriteLine("\"{0}\",", method.Name);
            context.Write    ("/* generic args */ ");
            GenerateGenericTypeSpecsExpression(context, "    ", genericArgs);
            context.WriteLine(",");
        }
        context.Write    ("/* parameter types */ ");
        GenerateParameterTypeSpecExpression(context, "    ", parameters);
        context.DecreaseDepth();
        context.WriteLine(");");

        String methodSuffix;
        if (method.IsConstructor)
            methodSuffix = "Constructor";
        else
        {
            methodSuffix = "ClosedMethod";
            context.WriteLine("assert(__method_spec__.genericTypes.length == 0, \"methods with generic args not implemented\");");
        }

        context.WriteLine("const __method__ = __d.globalClrBridge.get{0}!__method_spec__();", methodSuffix);
        context.WriteLine("scope (exit) __d.globalClrBridge.release(__method__);");

        //
        // Create parameters ObjectArray
        //
        {
            uint paramIndex = 0;
            foreach (ParameterInfo parameter in parameters)
            {
                if (parameter.ParameterType.IsArray ||
                    parameter.ParameterType.IsByRef ||
                    parameter.ParameterType.IsPointer)
                {
                    // skip complicated types for now
                }
                else if (parameter.ParameterType.IsEnum)
                {
                    context.WriteLine("auto  __param{0}__ = __d.clr.DotNetObject.nullObject;", paramIndex);
                    context.WriteLine("scope (exit) if (!__param{0}__.isNull) __d.globalClrBridge.release(__param{0}__);", paramIndex);
                    context.WriteLine("{");
                    context.WriteLine("    const  __enum_type__ = __d.globalClrBridge.getClosedType!({0}.__clrmetadata.typeSpec);", parameter.Name.ToDIdentifier());
                    context.WriteLine("    scope (exit) __enum_type__.finalRelease(__d.globalClrBridge);");
                    context.WriteLine("    __param{0}__ = __d.globalClrBridge.boxEnum(__enum_type__.type, {1});", paramIndex, parameter.Name.ToDIdentifier());
                    context.WriteLine("}");
                }
                else
                {
                    String boxType = TryGetBoxType(parameter.ParameterType);
                    if (boxType != null)
                    {
                        context.WriteLine("auto  __param{0}__ = __d.globalClrBridge.box!\"{1}\"({2}); // actual type is {3}",
                            paramIndex, boxType, parameter.Name.ToDIdentifier(), parameter.ParameterType.FullName);
                        context.WriteLine("scope (exit) __d.globalClrBridge.release(__param{0}__);", paramIndex);
                    }
                }
                paramIndex++;
            }
        }
        if (parameters.Length == 0)
        {
            context.WriteLine("__d.ObjectArray __param_values__ = __d.ObjectArray.nullObject;");
        }
        else
        {
            context.WriteLine("__d.ObjectArray __param_values__ = __d.globalClrBridge.makeObjectArray(");
            {
                uint paramIndex = 0;
                string prefix = " ";
                foreach (ParameterInfo parameter in parameters)
                {
                    if (parameter.ParameterType.IsArray ||
                        parameter.ParameterType.IsByRef ||
                        parameter.ParameterType.IsPointer)
                        context.WriteLine("    {0}__d.clr.DotNetObject.nullObject", prefix);
                    else if (parameter.ParameterType.IsEnum || TryGetBoxType(parameter.ParameterType) != null)
                        context.WriteLine("    {0}__param{1}__", prefix, paramIndex);
                    else
                        context.WriteLine("    {0}{1}", prefix, parameter.Name.ToDIdentifier());
                    prefix = ",";
                    paramIndex++;
                }
            }
            context.WriteLine(");");
            context.WriteLine("scope (exit) { __d.globalClrBridge.release(__param_values__); }");
        }
        String returnValueAddrString;
        if (returnType == typeof(void))
            returnValueAddrString = "null";
        else
        {
            returnValueAddrString = "cast(void**)&__return_value__";
            if (returnType == typeof(Boolean))
                context.WriteLine("ushort __return_value__;");
            else
                context.WriteLine("typeof(return) __return_value__;");
        }

        if (method.IsConstructor)
        {
            context.WriteLine("__return_value__ = cast(typeof(return))__d.globalClrBridge.callConstructor(__method__, __param_values__);");
        }
        else
        {
            String thisRefCode;
            if (type.IsValueType)
                // don't handle value types yet
                thisRefCode = "__d.clr.DotNetObject.nullObject";
            else
                thisRefCode = method.IsStatic ? "__d.clr.DotNetObject.nullObject" : "this";
            context.WriteLine("__d.globalClrBridge.funcs.CallGeneric(__method__, {0}, __param_values__, {1});", thisRefCode, returnValueAddrString);
        }

        if (returnType == typeof(Boolean))
            context.WriteLine("return (__return_value__ == 0) ? false : true;");
        else if (returnType != typeof(void))
            context.WriteLine("return __return_value__;");
    }

    void GenerateSubTypes(DContext module, Type type)
    {
        ExtraTypeInfo typeInfo;
        if (!typeInfoMap.TryGetValue(type, out typeInfo))
            return;
        foreach (Type subType in typeInfo.subTypes)
        {
            GenerateType(module, subType);
        }
    }

    static String TryGetBoxType(Type type)
    {
        if (type.IsByRef)
        {
            Type elementType = type.GetElementType();
            Debug.Assert(elementType != type);
            return TryGetBoxType(elementType);
        }

        // TODO: Handle type.IsGenericParameter
        //       will need to use D reflection to determine at D compile-time whether or not it's
        //       a type that needs to be boxed
        Debug.Assert(type != typeof(void)); // not handled yet
        if (type == typeof(Boolean)) return "Boolean";
        if (type == typeof(Byte))    return "Byte";
        if (type == typeof(SByte))   return "SByte";
        if (type == typeof(UInt16))  return "UInt16";
        if (type == typeof(Int16))   return "Int16";
        if (type == typeof(UInt32))  return "UInt32";
        if (type == typeof(Int32))   return "Int32";
        if (type == typeof(UInt64))  return "UInt64";
        if (type == typeof(Int64))   return "Int64";
        if (type == typeof(Char))    return "Char";
        if (type == typeof(String))  return "String";
        if (type == typeof(Single))  return "Single";
        if (type == typeof(Double))  return "Double";
        if (type == typeof(Decimal)) return "Decimal";
        Debug.Assert(!type.IsEnum, "type.IsEnum should have been handed before calling TryGetBoxType");
        if (type.IsValueType)
        {
            //Console.WriteLine("TODO: unknown box type for value type '{0}'", type);
            return "Object";
        }
        return null;
    }
}

class TabStringPool
{
    const String OneTab = "    ";
    private readonly List<String> tabList;
    public TabStringPool()
    {
        this.tabList = new List<String>();
        this.tabList.Add("");
    }
    public String this[UInt16 depth]
    {
        get
        {
            while (depth >= tabList.Count)
            {
                tabList.Add(tabList[tabList.Count-1] + OneTab);
            }
            return tabList[depth];
        }
    }
}

// Data for a type reference for a particular module
struct ModuleTypeRef
{
    public readonly String importQualifier;
    public readonly String dTypeString;
    public ModuleTypeRef(String importQualifier, String dTypeString)
    {
        this.importQualifier = importQualifier;
        this.dTypeString = dTypeString;
    }
}

abstract class DContext : IDisposable
{
    static readonly TabStringPool TabPool = new TabStringPool();

    public readonly String dotnetNamespace;
    public readonly TextWriter writer;
    internal UInt16 depth;
    internal Boolean atMiddleOfLine;

    // the typeRefMap is used to store all the types that have been referenced in the module
    // this allows us to generate a list of imports once we are done
    // note that this would not be necessary if we were using the "from" import idiom, but the D
    // compiler seems to have trouble with that idiom when there are circular references between modules
    public readonly Dictionary<Type,ModuleTypeRef> typeRefMap;

    public DContext(String dotnetNamespace, TextWriter writer, UInt16 depth)
    {
        this.dotnetNamespace = dotnetNamespace;
        this.writer = writer;
        this.depth = depth;
        this.atMiddleOfLine = false;
        this.typeRefMap = new Dictionary<Type,ModuleTypeRef>();
    }

    public abstract void Dispose();
    public String TypeReferenceForD(ExtraReflection extraReflection, Type type)
    {
        ModuleTypeRef typeRef;
        if (!typeRefMap.TryGetValue(type, out typeRef))
        {
            String importQualifier;
            String dTypeString = extraReflection.ToDEquivalentType(dotnetNamespace, type, out importQualifier);
            typeRef = new ModuleTypeRef(importQualifier, dTypeString);
            typeRefMap[type] = typeRef;
        }
        return typeRef.dTypeString;
    }

    public void IncreaseDepth() { this.depth += 1; }
    public void DecreaseDepth() { this.depth -= 1; }
    public void EnterBlock()
    {
        WriteLine("{");
        IncreaseDepth();
    }
    public void ExitBlock()
    {
        DecreaseDepth();
        WriteLine("}");
    }
    void AboutToWrite()
    {
        if (!atMiddleOfLine)
        {
            writer.Write(TabPool[depth]);
            atMiddleOfLine = true;
        }
    }
    public void Write(String msg)
    {
        AboutToWrite();
        writer.Write(msg);
    }
    public void Write(String fmt, params Object[] args)
    {
        AboutToWrite();
        writer.Write(fmt, args);
    }
    public void WriteLine()
    {
        // don't call AboutToWrite because we don't want line prefix on empty lines
        writer.WriteLine();
        atMiddleOfLine = false;
    }
    public void WriteLine(String msg)
    {
        AboutToWrite();
        writer.WriteLine(msg);
        atMiddleOfLine = false;
    }
    public void WriteLine(String fmt, params Object[] args)
    {
        AboutToWrite();
        writer.WriteLine(fmt, args);
        atMiddleOfLine = false;
    }
}

class DModule : DContext
{
    public readonly Assembly assembly;
    public readonly String fullName;
    public DModule(Assembly assembly, String dotnetNamespace, String fullName, StreamWriter writer)
        : base(dotnetNamespace, writer, 0)
    {
        this.assembly = assembly;
        this.fullName = fullName;
    }
    public override void Dispose()
    {
        Generator.GenerateImports(this, typeRefMap.Values);
        writer.Dispose();
    }
}

class DTypeContext : DContext
{
    private readonly DContext parentContext;
    public DTypeContext(DContext parentContext)
        : base(parentContext.dotnetNamespace, parentContext.writer, parentContext.depth)
    {
        // we assume we are on a newline so that the method body starts on it's own line
        Debug.Assert(parentContext.atMiddleOfLine == false, "codebug");
        this.parentContext = parentContext;
    }
    public override void Dispose()
    {
        Debug.Assert(depth == parentContext.depth, "codebug");
        Debug.Assert(atMiddleOfLine == false, "codebug");
        Generator.GenerateImports(parentContext, typeRefMap.Values);
    }
}

class DMethodContext : DContext
{
    readonly DTypeContext typeContext;
    public DMethodContext(DTypeContext typeContext)
       : base(typeContext.dotnetNamespace, new StringWriter(), typeContext.depth)
    {
        // we assume we are on a newline so that the method body starts on it's own line
        Debug.Assert(typeContext.atMiddleOfLine == false, "codebug");
        this.typeContext = typeContext;
    }
    public override void Dispose()
    {
        Debug.Assert(depth == typeContext.depth, "codebug");
        Debug.Assert(atMiddleOfLine == false, "codebug");
        Generator.GenerateImports(typeContext, typeRefMap.Values);
        typeContext.writer.Write(writer.ToString());
    }
}

enum AssemblyState
{
    Initial,
    Generating,
    Generated,
}

class ExtraAssemblyInfo
{
    public readonly string packageName;
    public AssemblyState state;
    public ExtraAssemblyInfo(string packageName)
    {
        this.packageName = packageName;
        this.state = AssemblyState.Initial;
    }
}

class ExtraTypeInfo
{
    public readonly String moduleName;
    // Name of the type if referencing from the root of the module
    public readonly String moduleRelativeName;
    public readonly List<Type> subTypes; // types that are declared inside this type
    public ExtraTypeInfo(String moduleName, String moduleRelativeName)
    {
        this.moduleName = moduleName;
        this.moduleRelativeName = moduleRelativeName;
        this.subTypes = new List<Type>();
    }
}

struct DKeyword
{
    static readonly String[] Strings = new String[] {
        "alias", "align", "asm", "assert",
        "body", "break",
        "cast", "continue",
        "debug",
        "export",
        "final", "finally", "function",
        "immutable", "import",
        "lazy",
        "module",
        "null",
        "package",
        "return",
        "scope", "shared", "super",
        "template", "this", "typeof",
        "version",
    };
    static readonly Dictionary<String,DKeyword> staticMap;
    static DKeyword()
    {
        staticMap = new Dictionary<String,DKeyword>();
        foreach (String str in Strings)
        {
            staticMap.Add(str, new DKeyword(str));
        }
    }
    public static bool TryGet(String keywordString, out DKeyword outKeyword)
    {
        return staticMap.TryGetValue(keywordString, out outKeyword);
    }

    public readonly String str;
    public readonly String escaped;
    DKeyword(String str)
    {
        this.str = str;
        this.escaped = str + "_";
    }
}

static class Util
{
    static readonly Char[] DotCharArray = new Char[] {'.'};
    public static String NamespaceToModulePath(String @namespace)
    {
        String path = "";
        if (@namespace != null)
        {
            @namespace = @namespace.ToDQualifiedIdentifier();
            foreach (String part in @namespace.Split('.'))
            {
                path = Path.Combine(path, part);
            }
        }
        return Path.Combine(path, "package.d");
    }
    public static String ToDQualifiedIdentifier(this String s)
    {
        // TODO: this is definitely innefficient
        String[] parts = s.Split(DotCharArray);
        for (UInt32 i = 0; i < parts.Length; i++)
        {
            parts[i] = ToDIdentifier(parts[i]);
        }
        return String.Join(".", parts);
    }
    // add a trailing '_' to keywords
    public static String ToDIdentifier(this String s)
    {
        Debug.Assert(!s.Contains("."), String.Format("identifier '{0}' contains '.' so need to use ToDQualifiedIdentifier", s));
        {
            DKeyword keyword;
            if (DKeyword.TryGet(s, out keyword))
                return keyword.escaped;
        }
        // TODO: might be faster/better to use StringBuilder with an initial capacity
        //       test performance before refactoring to see if it makes a difference
        return s
            .Replace("$", "_")
            .Replace("|", "_")
            .Replace("<", "_")
            .Replace(">", "_")
            .Replace("{", "_")
            .Replace("}", "_")
            .Replace("-", "_")
            .Replace("=", "_")
            .Replace("`", "_")
            .Replace("+", "_");
    }
    public static String GetUnqualifiedTypeNameForD(this Type type)
    {
        // these names need to be changed to avoid symbol conflicts with primitive types in D
        if (type.Name == "Object")
            return "MscorlibObject";
        if (type.Name == "Exception")
            return "MscorlibException";
        if (type.Name == "TypeInfo")
            return "MscorlibTypeInfo";
        return type.Name.ToDIdentifier();
    }
    public static String UnsupportedTypeRef(this Type type)
    {
        return String.Format("__d.clrbridge.UnsupportedType!q{{{0}}}", type.ToString().Replace("`", "_"));
    }
}

static class Extensions
{
    public static String NullToEmpty(this String s)
    {
       return (s == null) ? "" : s;
    }
    public static Boolean IsEmpty<T>(this T[] array) { return array == null || array.Length == 0; }
    public static Boolean IsEmpty(this String s) { return s == null || s.Length == 0; }
    public static UInt16 ToUInt16(this Int32 value)
    {
        if (value > (Int32)UInt16.MaxValue)
            throw new Exception(String.Format("Cannot convert value {0} of type Int32 to UInt16 because it is too big", value));
        return (UInt16)value;
    }
    public static UInt16 GetGenericArgCount(this Type type)
    {
        if (type == null)
            return 0;
        Type[] genericArgs = type.GetGenericArguments();
        return (genericArgs == null) ? (UInt16)0 : genericArgs.Length.ToUInt16();
    }
}

static class HexString
{
    public static String FromBytes(Byte[] array)
    {
        StringBuilder s = new StringBuilder(array.Length * 2);
        foreach (Byte b in array)
        {
            s.AppendFormat("{0:x2}", b);
        }
        return s.ToString();
    }
    public static Byte[] ToBytes(String s)
    {
        if (s.Length % 2 != 0) throw new Exception("hex string length must be divisible by 2");
        Byte[] bytes = new Byte[s.Length / 2];
        for (Int32 i = 0; i < s.Length; i += 2)
        {
            // TODO: creating a substring is probably overkill
            bytes[i / 2] = Convert.ToByte(s.Substring(i, 2), 16);
        }
        return bytes;
    }
}

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


static class ClrBridgeCodegen
{
    static void Usage()
    {
        Console.WriteLine("Usage: ClrBridgeCodegen.exe <DotNetAssembly> <OutputDir>");
    }
    public static Int32 Main(String[] args)
    {
        if (args.Length != 2)
        {
            Usage();
            return 1;
        }
        String assemblyString = args[0];
        String outputDir = args[1];
        Console.WriteLine("assembly : {0}", assemblyString);
        Console.WriteLine("outputDir: {0}", outputDir);

        Assembly assembly;
        if (assemblyString.StartsWith("file:"))
            assembly = Assembly.LoadFile(Path.GetFullPath(assemblyString.Substring(5)));
        else if (assemblyString.StartsWith("gac:"))
            assembly = Assembly.Load(assemblyString.Substring(4));
        else
        {
            Console.WriteLine("Error: assembly string must start with 'file:' or 'gac:' but got '{0}'", assemblyString);
            return 1;
        }
        new Generator(assembly, outputDir).GenerateModule(assembly);
        return 0;
    }
}

class Generator
{
    readonly Assembly thisAssembly;
    readonly String outputDir;
    readonly Dictionary<Assembly, ExtraAssemblyInfo> assemblyInfoMap;
    readonly Dictionary<Type, ExtraTypeInfo> typeInfoMap;
    readonly Dictionary<String,DModule> moduleMap;
    readonly String thisAssemblyPackageName; // cached version of GetExtraAssemblyInfo(thisAssembly).packageName
    // bool lowercaseModules;

    public Generator(Assembly thisAssembly, String outputDir)
    {
        this.thisAssembly = thisAssembly;
        this.outputDir = outputDir;
        this.assemblyInfoMap = new Dictionary<Assembly,ExtraAssemblyInfo>();
        this.typeInfoMap = new Dictionary<Type,ExtraTypeInfo>();
        this.moduleMap = new Dictionary<String,DModule>();
        this.thisAssemblyPackageName = GetExtraAssemblyInfo(thisAssembly).packageName;
    }

    ExtraAssemblyInfo GetExtraAssemblyInfo(Assembly assembly)
    {
        ExtraAssemblyInfo info;
        if (!assemblyInfoMap.TryGetValue(assembly, out info))
        {
            info = new ExtraAssemblyInfo(
                assembly.GetName().Name.Replace(".", "_")
            );
            assemblyInfoMap[assembly] = info;
        }
        return info;
    }
    ExtraTypeInfo GetExtraTypeInfo(Type type)
    {
        ExtraTypeInfo info;
        if (!typeInfoMap.TryGetValue(type, out info))
        {
            info = new ExtraTypeInfo();
            typeInfoMap[type] = info;
        }
        return info;
    }

    public void GenerateModule(Assembly assembly)
    {
        // on the first pass we identify types that need to be defined inside other types
        // so that when we generate code, we can generate all the subtypes for each type
        Type[] allTypes = assembly.GetTypes();
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
                // TODO: make directories
                String outputDFilename = Path.Combine(outputDir,
                    Path.Combine(thisAssemblyPackageName, Util.NamespaceToModulePath(type.Namespace)));
                Console.WriteLine("[DEBUG] NewDModule '{0}'", outputDFilename);
                Directory.CreateDirectory(Path.GetDirectoryName(outputDFilename));
                StreamWriter writer = new StreamWriter(new FileStream(outputDFilename, FileMode.Create, FileAccess.Write, FileShare.Read));
                // TODO: modify if lowercaseModules
                String moduleFullName = thisAssemblyPackageName;
                if (type.Namespace.NullToEmpty().Length > 0)
                    moduleFullName = String.Format("{0}.{1}", thisAssemblyPackageName, type.Namespace);
                module = new DModule(moduleFullName, writer);
                writer.WriteLine("module {0};", moduleFullName);
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
            }
            GenerateType(module, type, 0);
        }
        foreach (DModule module in moduleMap.Values)
        {
            module.writer.Close();
        }
    }

    // TODO: depth should affect the tab depth
    void GenerateType(DModule module, Type type, UInt16 depth)
    {
        if (type.IsValueType)
        {
            if (type.IsEnum)
            {
                Debug.Assert(!type.IsGenericType, "enum types can be generic?");
                GenerateEnum(module, type);
            }
            else
            {
                if (type.IsGenericType)
                {
                    Message(module, "skipping type {0} because generics structs aren't implemented", type.Name);
                    return;
                }
                GenerateStruct(module, type, depth);
            }
        }
        else if (type.IsInterface)
        {
            if (type.IsGenericType)
            {
                Message(module, "skipping type {0} because generics interfaces aren't implemented", type.Name);
                return;
            }
            GenerateInterface(module, type, depth);
        }
        else
        {
            Debug.Assert(type.IsClass);
            if (typeof(Delegate).IsAssignableFrom(type))
            {
                if (type.IsGenericType)
                {
                    Message(module, "skipping type {0} because generics delegates aren't implemented", type.Name);
                    return;
                }
                GenerateDelegate(module, type);
            }
            else
            {
                GenerateClass(module, type, depth);
            }
        }
    }

    void Message(DModule module, String fmt, params Object[] args)
    {
        String message = String.Format(fmt, args);
        Console.WriteLine(message);
        module.writer.WriteLine("// {0}", message);
    }

    void GenerateEnum(DModule module, Type type)
    {
        const String EnumValueFieldName = "value__";
        module.writer.WriteLine("/* .NET Enum */ static struct {0}", Util.GetUnqualifiedTypeName(type));
        module.writer.WriteLine("{");
        Type[] genericArgs = type.GetGenericArguments();
        Debug.Assert(genericArgs.IsEmpty(), "enums can have generic arguments???");
        GenerateMetadata(module, type, genericArgs);
        String baseTypeDName = ToDType(type.BaseType);
        module.writer.WriteLine("    private {0} {1}; // .NET BasteType is actually {2}", baseTypeDName, EnumValueFieldName, type.BaseType);
        module.writer.WriteLine("    enum : typeof(this)");
        module.writer.WriteLine("    {");
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
            module.writer.WriteLine("        {0} = typeof(this)({1}({2})),", Util.ToDIdentifier(field.Name), baseTypeDName, field.GetRawConstantValue());
        }
        module.writer.WriteLine("    }");
        Debug.Assert(nonStaticFieldCount == 1);

        // Commenting out for now because of a conflict with TypeNameKind ToString
        // It looks like C# might allow field names and method names to have the same symbol?
        // I'll need to see in which cases C# allows this, maybe only with static fields?
        // If so, the right solution would probably be to modify the field name that conflicts.
        //GenerateMethods(module, type);
        /*
        foreach (var method in type.GetMethods())
        {
            module.writer.WriteLine("    // TODO: generate something for enum method {0}", method);
        }
        */

        // Generate opMethods so this behaves like an enum
        module.writer.WriteLine("    typeof(this) opBinary(string op)(const typeof(this) right) const");
        module.writer.WriteLine("    { return typeof(this)(mixin(\"this.value__ \" ~ op ~ \" right.value__\")); }");
        // TODO: there's probably more (or less) to generate to get the behavior right

        module.writer.WriteLine("}");
    }

    void GenerateStruct(DModule module, Type type, UInt16 depth)
    {
        module.writer.WriteLine("static struct {0}", Util.GetUnqualifiedTypeName(type));
        module.writer.WriteLine("{");
        Type[] genericArgs = type.GetGenericArguments();
        GenerateMetadata(module, type, genericArgs);
        GenerateFields(module, type);
        GenerateMethods(module, type);
        GenerateSubTypes(module, type, depth);
        module.writer.WriteLine("}");
    }
    void GenerateInterface(DModule module, Type type, UInt16 depth)
    {
        module.writer.WriteLine("interface {0}", Util.GetUnqualifiedTypeName(type));
        module.writer.WriteLine("{");
        Debug.Assert(type.GetFields().Length == 0);
        //??? GenerateMetadata(module, type);
        GenerateMethods(module, type);
        GenerateSubTypes(module, type, depth);
        module.writer.WriteLine("}");
    }
    void GenerateDelegate(DModule module, Type type)
    {
        module.writer.WriteLine("// TODO: generate delegate '{0}'", Util.GetUnqualifiedTypeName(type));
    }
    void GenerateClass(DModule module, Type type, UInt16 depth)
    {
        module.writer.Write("/* .NET class */ static struct {0}", Util.GetUnqualifiedTypeName(type));
        Type[] genericArgs = type.GetGenericArguments();
        GenerateGenericParameters(module, genericArgs);
        module.writer.WriteLine();
        module.writer.WriteLine("{");
        module.writer.WriteLine("    // TODO: mixin the base class rather than DotNetObject");
        module.writer.WriteLine("    mixin __d.clrbridge.DotNetObjectMixin!\"__d.clr.DotNetObject\";");
        // generate metadata, one reason for this is so that when this type is used as a template parameter, we can
        // get the .NET name for this type
        GenerateMetadata(module, type, genericArgs);
        GenerateFields(module, type);
        GenerateMethods(module, type);
        GenerateSubTypes(module, type, depth);
        module.writer.WriteLine("}");
    }

    // generates a multi-line expression that creates a TypeSpec
    // assumes code starts in the middle of a line where the expression starts,
    // linePrefix is the prefix for new line of the expression
    void GenerateTypeSpecExpression(DModule module, String linePrefix, Type type)
    {
        GenerateTypeSpecExpression(module, linePrefix, type, type.GetGenericArguments());
    }
    void GenerateTypeSpecExpression(DModule module, String linePrefix, Type type, Type[] genericArgs)
    {
        if (type.IsGenericParameter)
        {
            Debug.Assert(genericArgs.IsEmpty(), "you can have a generic parameter type with generic args??");
            module.writer.Write("__d.clrbridge.GetTypeSpec!({0})", ToDType(type));
            return;
        }
        module.writer.WriteLine("__d.clr.TypeSpec(");
        module.writer.WriteLine("{0}\"{1}\",", linePrefix, type.Assembly.FullName);
        bool hasGenerics = !genericArgs.IsEmpty();
        module.writer.Write("{0}\"{1}\"{2}", linePrefix, type.FullName, hasGenerics ? ", [" : ")", type.Name);
        if (hasGenerics)
        {
            module.writer.WriteLine();
            foreach (Type genericArg in genericArgs)
            {
                module.writer.WriteLine("{0}    __d.clrbridge.GetTypeSpec!({1}),", linePrefix, ToDType(genericArg));
            }
            module.writer.Write("{0}])", linePrefix);
        }
    }

    // TODO: remove this?
    void GenerateGenericTypeSpecsExpression(DModule module, String linePrefix, Type[] genericArgs)
    {
        if (genericArgs.IsEmpty())
            module.writer.Write("null");
        else
        {
            module.writer.WriteLine("[");
            foreach (Type genericArg in genericArgs)
            {
                module.writer.WriteLine("{0}    __d.clrbridge.GetTypeSpec!({1}),", linePrefix, ToDType(genericArg));
            }
            module.writer.Write("{0}]", linePrefix);
        }
    }
    void GenerateParameterTypeSpecExpression(DModule module, String linePrefix, ParameterInfo[] paramInfos)
    {
        if (paramInfos.IsEmpty())
            module.writer.Write("null");
        else
        {
            module.writer.WriteLine("[");
            String subTypePrefix = linePrefix + "        ";
            foreach (ParameterInfo paramInfo in paramInfos)
            {
                //module.writer.WriteLine("{0}   {1},", linePrefix, TypeSpecReference(paramInfo.ParameterType));
                module.writer.Write("{0}    /* param '{1}' */", linePrefix, paramInfo.Name);
                GenerateTypeSpecExpression(module, subTypePrefix, paramInfo.ParameterType);
                module.writer.WriteLine(",");
            }
            module.writer.Write("{0}]", linePrefix);
        }
    }

    void GenerateMetadata(DModule module, Type type, Type[] genericArgs)
    {
        module.writer.WriteLine("    static struct __clrmetadata");
        module.writer.WriteLine("    {");
        module.writer.Write("        enum typeSpec = ");
        GenerateTypeSpecExpression(module, "            ", type, genericArgs);
        module.writer.WriteLine(";");
        module.writer.WriteLine("    }");
    }

    void GenerateFields(DModule module, Type type)
    {
        foreach (FieldInfo field in type.GetFields())
        {
            Type fieldType = field.FieldType;
            String fromDll = (fieldType.Assembly == thisAssembly) ? "" :
                GetExtraAssemblyInfo(fieldType.Assembly).fromDllPrefix;
            // fields are represented as D @property functions
            module.writer.WriteLine("    @property {0} {1}() {{ return typeof(return).init; }}; // fromPrefix '{2}' {3} {4}",
                ToDType(fieldType),
                field.Name.ToDIdentifier(),
                fromDll,
                field.FieldType, field.FieldType.AssemblyQualifiedName);
        }
    }

    void GenerateMethods(DModule module, Type type)
    {
        foreach (ConstructorInfo constructor in type.GetConstructors())
        {
            if (type.IsValueType)
                continue; // script structs for now
            module.writer.Write("    {0} static typeof(this) New", constructor.IsPrivate ? "private" : "public");
            ParameterInfo[] parameters = constructor.GetParameters();
            GenerateParameterList(module, parameters);
            module.writer.WriteLine();
            module.writer.WriteLine("    {");
            GenerateMethodBody(module, type, constructor, type, parameters);
            module.writer.WriteLine("    }");
        }
        foreach (MethodInfo method in type.GetMethods())
        {
            //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            // skip virtual methods for now so we don't get linker errors
            if (method.IsVirtual)
                continue;

            module.writer.Write("    {0}", method.IsPrivate ? "private" : "public");
            if (method.IsStatic)
            {
                module.writer.Write(" static");
            }
            else if (method.IsFinal)
            {
                module.writer.Write(" final");
            }

            Type[] genericArguments = method.GetGenericArguments();
            Debug.Assert(method.ReturnType != null);
            if (method.ReturnType == typeof(void))
                module.writer.Write(" void");
            else
                module.writer.Write(" {0}", ToDType(method.ReturnType));
            module.writer.Write(" {0}", Util.ToDIdentifier(method.Name));
            //
            // TODO: generate generic parameters
            //
            ParameterInfo[] parameters = method.GetParameters();
            GenerateGenericParameters(module, genericArguments);
            GenerateParameterList(module, parameters);
            if (method.IsVirtual)
            {
                module.writer.WriteLine(";");
                continue;
            }
            module.writer.WriteLine();
            module.writer.WriteLine("    {");
            GenerateMethodBody(module, type, method, method.ReturnType, parameters);
            module.writer.WriteLine("    }");
        }
    }

    void GenerateGenericParameters(DModule module, Type[] genericTypes)
    {
        if (genericTypes != null && genericTypes.Length > 0)
        {
            module.writer.Write("(");
            string prefix = "";
            foreach (Type t in genericTypes)
            {
                module.writer.Write("{0}{1}", prefix, t.Name);
                prefix = ", ";
            }
            module.writer.Write(")");
        }
    }

    void GenerateParameterList(DModule module, ParameterInfo[] parameters)
    {
        module.writer.Write("(");
        {
            string prefix = "";
            foreach (ParameterInfo parameter in parameters)
            {
                module.writer.Write("{0}{1} {2}", prefix, ToDType(parameter.ParameterType), Util.ToDIdentifier(parameter.Name));
                prefix = ", ";
            }
        }
        module.writer.Write(")");
    }

    void GenerateMethodBody(DModule module, Type type,
        MethodBase method, Type returnType, ParameterInfo[] parameters)
    {
        // skip non-static methods for now, they just take too long right now
        if (!method.IsStatic && !method.IsConstructor)
        {
            if (returnType != typeof(void))
                module.writer.WriteLine("        return typeof(return).init;");
            return;
        }
        // TODO: we may want to cache some of this stuff, but for now we'll just get it
        Type[] genericArgs = method.IsGenericMethod ? method.GetGenericArguments() : null;
        module.writer.WriteLine("        enum __method_spec__ = __d.clrbridge.MethodSpec(__clrmetadata.typeSpec, \"{0}\",", method.Name);
        module.writer.Write    ("            /* generic args */ ");
        GenerateGenericTypeSpecsExpression(module, "            ", genericArgs);
        module.writer.Write(", /* parameter types */ ");
        GenerateParameterTypeSpecExpression(module, "            ", parameters);
        module.writer.WriteLine(");");

        String methodTypeString = method.IsConstructor ? "Constructor" : "Method";

        // Get Assembly so we can get Type then Method (TODO: cache this somehow?)
        module.writer.WriteLine("        auto  __this_type__ = __d.globalClrBridge.getClosedType!(__clrmetadata.typeSpec);");
        module.writer.WriteLine("        scope (exit) __this_type__.release(__d.globalClrBridge);");
        module.writer.WriteLine("        assert(__method_spec__.genericTypes.length == 0, \"methods with generic args not implemented\");");
        module.writer.WriteLine("        const __method__ = __d.globalClrBridge.get{0}(__this_type__.type,", methodTypeString);
        if (!method.IsConstructor)
            module.writer.WriteLine("            __d.CStringLiteral!\"{0}\",", method.Name);
        module.writer.WriteLine("            __d.globalClrBridge.getTypesArray!(__method_spec__.paramTypes)());");
        module.writer.WriteLine("        scope (exit) { __d.globalClrBridge.release(__method__); }");

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
                else
                {
                    String boxType = TryGetBoxType(parameter.ParameterType);
                    if (boxType != null)
                    {
                        module.writer.WriteLine("        auto  __param{0}__ = __d.globalClrBridge.box!(__d.clr.PrimitiveType.{1})({2}); // actual type is {3}",
                            paramIndex, boxType, Util.ToDIdentifier(parameter.Name), Util.GetQualifiedTypeName(parameter.ParameterType));
                        module.writer.WriteLine("        scope (exit) __d.globalClrBridge.release(__param{0}__);", paramIndex);
                    }
                }
                paramIndex++;
            }
        }
        if (parameters.Length == 0)
        {
            module.writer.WriteLine("        __d.ObjectArray __param_values__ = __d.ObjectArray.nullObject;");
        }
        else
        {
            module.writer.WriteLine("        __d.ObjectArray __param_values__ = __d.globalClrBridge.makeObjectArray(");
            {
                uint paramIndex = 0;
                string prefix = " ";
                foreach (ParameterInfo parameter in parameters)
                {
                    if (TryGetBoxType(parameter.ParameterType) != null)
                        module.writer.WriteLine("            {0}__param{1}__", prefix, paramIndex);
                    else
                        module.writer.WriteLine("            {0}{1}", prefix, Util.ToDIdentifier(parameter.Name));
                    prefix = ",";
                    paramIndex++;
                }
            }
            module.writer.WriteLine("        );");
            module.writer.WriteLine("        scope (exit) { __d.globalClrBridge.release(__param_values__); }");
        }
        String returnValueAddrString;
        if (returnType == typeof(void))
            returnValueAddrString = "null";
        else
        {
            module.writer.WriteLine("        typeof(return) __return_value__;");
            returnValueAddrString = "cast(void**)&__return_value__";
        }

        if (method.IsConstructor)
        {
            module.writer.WriteLine("        __return_value__ = cast(typeof(return))__d.globalClrBridge.callConstructor(__method__, __param_values__);");
        }
        else
        {
            module.writer.WriteLine("        __d.globalClrBridge.funcs.CallGeneric(__method__, __d.clr.DotNetObject.nullObject, __param_values__, {0});", returnValueAddrString);
        }

        if (returnType != typeof(void))
            module.writer.WriteLine("        return __return_value__;");
    }

    void GenerateSubTypes(DModule module, Type type, UInt16 depth)
    {
        ExtraTypeInfo typeInfo;
        if (!typeInfoMap.TryGetValue(type, out typeInfo))
            return;
        depth++;
        foreach (Type subType in typeInfo.subTypes)
        {
            GenerateType(module, subType, depth);
        }
    }

    public String TypeSpecRef(Type type)
    {
        return String.Format("__d.clrbridge.GetTypeSpec!({0})", ToDType(type));
    }

    // TODO: add TypeContext?  like fieldDecl?  Might change const(char)* to string in some cases?
    static String ToDType(Type type)
    {
        if (type.IsGenericParameter)
            return type.Name;

        Debug.Assert(type != typeof(void)); // not handled yet
        if (type == typeof(Boolean)) return "bool";
        if (type == typeof(Byte))    return "ubyte";
        if (type == typeof(SByte))   return "byte";
        if (type == typeof(UInt16))  return "ushort";
        if (type == typeof(Int16))   return "short";
        if (type == typeof(UInt32))  return "uint";
        if (type == typeof(Int32))   return "int";
        if (type == typeof(UInt64))  return "ulong";
        if (type == typeof(Int64))   return "long";
        if (type == typeof(Char))    return "char";
        if (type == typeof(String))  return "__d.CString";
        if (type == typeof(Single))  return "float";
        if (type == typeof(Double))  return "double";
        if (type == typeof(Decimal)) return "__d.clr.Decimal";
        if (type == typeof(Object))  return "__d.clr.DotNetObject";

        // non primitive types
        if (type == typeof(Enum)) return "__d.clrbridge.Enum"; // I think System.Enum is always 32 bits, verify this

        //String fromDll = (fieldType.Assembly == thisAssembly) ? "" :
        //    GetExtraAssemblyInfo(fieldType.Assembly).fromDllPrefix;
        return "__d.clr.DotNetObject";
    }
    static String TryGetBoxType(Type type)
    {
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
        if (type == typeof(Object))  return null;
        return null;
    }
}

class DModule
{
    public readonly String fullName;
    public readonly StreamWriter writer;
    public DModule(String fullName, StreamWriter writer)
    {
        this.fullName = fullName;
        this.writer = writer;
    }
}

class ExtraAssemblyInfo
{
    public readonly string packageName;
    public readonly string fromDllPrefix;
    public ExtraAssemblyInfo(string packageName)
    {
        this.packageName = packageName;
        this.fromDllPrefix = String.Format("fromDll!\"{0}\".", packageName);
    }
}

class ExtraTypeInfo
{
    public readonly List<Type> subTypes; // types that are declared inside this type
    public ExtraTypeInfo()
    {
        this.subTypes = new List<Type>();
    }
}

static class Util
{
    public static String NamespaceToModulePath(String @namespace)
    {
        String path = "";
        if (@namespace != null)
        {
            foreach (String part in @namespace.Split('.'))
            {
                path = Path.Combine(path, part);
            }
        }
        return Path.Combine(path, "package.d");
    }
    // add a trailing '_' to keywords
    public static String ToDIdentifier(this String s)
    {
        if (s == "align") return "align_";
        if (s == "module") return "module_";
        if (s == "version") return "version_";
        if (s == "function") return "function_";
        if (s == "scope") return "scope_";
        if (s == "asm") return "asm_";
        if (s == "lazy") return "lazy_";
        return s
            .Replace("$", "_")
            .Replace("<", "_")
            .Replace(">", "_")
            .Replace("=", "_")
            .Replace("`", "_");
    }
    // rename types that conflict with standard D types
    public static String GetQualifiedTypeName(Type type)
    {
        String prefix = (type.DeclaringType == null) ? "" : GetQualifiedTypeName(type.DeclaringType) + ".";
        return prefix + GetUnqualifiedTypeName(type);
    }
    public static String GetUnqualifiedTypeName(Type type)
    {
        if (type.Name == "Object")
            return "DotNetObject";
        if (type.Name == "Exception")
            return "DotNetException";
        if (type.Name == "TypeInfo")
            return "DotNetTypeInfo";
        return type.Name
            .Replace("$", "_")
            .Replace("<", "_")
            .Replace(">", "_")
            .Replace("=", "_")
            .Replace("`", "_");
    }
}

static class Extensions
{
    public static String NullToEmpty(this String s)
    {
       return (s == null) ? "" : s;
    }
    public static Boolean IsEmpty<T>(this T[] array) { return array == null || array.Length == 0; }
}

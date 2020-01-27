module clrbridge;

import std.traits : Parameters;

import cstring : CString, CStringLiteral;
import hresult;

import core.stdc.stdlib : malloc, free;

static import clr;
import clr : DotNetObject, Enum, Decimal, TypeSpec;

mixin template DotnetPrimitiveWrappers(string funcName)
{
    static foreach (type; clr.primitiveTypes)
    {
        mixin("auto " ~ funcName ~ type.name ~ "(Parameters!(" ~ funcName ~ "!(clr.PrimitiveType." ~ type.name ~ ")) args)" ~
            "{ return " ~ funcName ~ "!(clr.PrimitiveType." ~ type.name ~ ")(args); }");
    }
}

mixin template DotNetObjectMixin(string base)
{
    mixin(base ~ " __base__;");
    alias __base__ this;
    static auto nullObject() { return typeof(this)(mixin(base ~ ".nullObject")); }
}

// A temporary type in order to make sure overloads work during initial development
// even if all types are not supported yet
struct UnsupportedType(string realTypeName) { mixin DotNetObjectMixin!"DotNetObject"; }

struct Assembly     { mixin DotNetObjectMixin!"DotNetObject"; }
struct Type         { mixin DotNetObjectMixin!"DotNetObject"; }
struct ConstructorInfo { mixin DotNetObjectMixin!"DotNetObject"; }
struct MethodInfo   { mixin DotNetObjectMixin!"DotNetObject"; }

struct Array(clr.PrimitiveType T) { mixin DotNetObjectMixin!"DotNetObject"; }
struct ArrayGeneric { mixin DotNetObjectMixin!"DotNetObject"; }

struct ArrayBuilder(clr.PrimitiveType T) { mixin DotNetObjectMixin!"DotNetObject"; }
struct ArrayBuilderGeneric { mixin DotNetObjectMixin!"DotNetObject"; }

// Keep this in sync with the error codes in ClrBridge.cs
enum ClrBridgeErrorCode : ubyte
{
    none = 0,
    fileNotFound = 1,
    typeNotFound = 2,
    methodNotFound = 3,
    ambiguousMethod = 4,
}

auto errorFormatter(uint errorCode)
{
    static struct Formatter
    {
        uint errorCode;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            import std.format : formattedWrite;
            formattedWrite(sink, "%s", cast(ClrBridgeErrorCode)errorCode);
        }
    }
    return Formatter(errorCode);
}

struct ClrBridgeError
{
    enum Type
    {
        none,
        createClrBridgeDelegate,
        forward,
    }
    private static struct TypeStructs
    {
        static struct none { }
        static struct createClrBridgeDelegate { string methodName; HRESULT result; }
        static struct forward { uint code; }
    }

    Type type;
    union Data
    {
        TypeStructs.none none;
        TypeStructs.createClrBridgeDelegate createClrBridgeDelegate;
        TypeStructs.forward forward;
    }
    Data data;
    static ClrBridgeError opDispatch(string name, T...)(T args)
    {
        ClrBridgeError error;
        error.type = __traits(getMember, Type, name);
        __traits(getMember, error.data, name) = __traits(getMember, TypeStructs, name)(args);
        return error;
    }
    bool failed() const nothrow @nogc { return type != Type.none; }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        import std.format : formattedWrite;
        final switch (type)
        {
           case Type.none: sink("NoError"); break;
           case Type.createClrBridgeDelegate:
               formattedWrite(sink, "create_delegate(methodName=%s) failed with error %s",
                   data.createClrBridgeDelegate.methodName, data.createClrBridgeDelegate.result);
               break;
           case Type.forward:
               errorFormatter(data.forward.code).toString(sink);
               break;
        }
    }
}


alias CreateClrBridgeDelegate = HRESULT delegate(CString methodName, void** outFuncAddr);

ClrBridgeError loadClrBridge(CreateClrBridgeDelegate createClrBridgeDelegate, ClrBridge* bridge)
{
    static foreach(method; __traits(allMembers, ClrBridge.Funcs))
    {
        {
            const error = createClrBridgeDelegate(CStringLiteral!method, cast(void**)&__traits(getMember, bridge.funcs, method));
            if (error.failed)
                return ClrBridgeError.createClrBridgeDelegate(method, error);
        }
    }
    {
        const error = bridge.tryLoadAssembly(CStringLiteral!"mscorlib", &bridge.mscorlib);
        if (error.failed) return error;
    }
    {
        const error = bridge.tryGetType(bridge.mscorlib, CStringLiteral!"System.Type", &bridge.typeType);
        if (error.failed) return error;
    }
    static foreach(type; clr.primitiveTypes)
    {{
        const error = bridge.tryGetType(bridge.mscorlib, CStringLiteral!(type.fullName), mixin("&bridge.primitiveTypes." ~ type.name));
        if (error.failed) return error;
    }}
    return ClrBridgeError.none;
}

struct ClrBridge
{
    private mixin template FuncsMixin()
    {
        void function(const DotNetObject obj) nothrow @nogc Release;
        uint function(CString name, Assembly* outAssembly) nothrow @nogc LoadAssembly;
        uint function(const Assembly assembly, CString name, Type* outType) nothrow @nogc GetType;
        uint function(const Type type, const ArrayGeneric types, Type* outType) nothrow @nogc ResolveGenericType;
        uint function(const Type type, const ArrayGeneric paramTypes, ConstructorInfo* outConstructor) nothrow @nogc GetConstructor;
        uint function(const Type type, CString name, const ArrayGeneric paramTypes, MethodInfo* outMethod) nothrow @nogc GetMethod;
        uint function(const ConstructorInfo constructor, const Array!(clr.PrimitiveType.Object) args, DotNetObject* outObjectPtr) nothrow @nogc CallConstructor;
        void function(const MethodInfo method, const DotNetObject obj, const Array!(clr.PrimitiveType.Object) args, void** returnValuePtr) nothrow @nogc CallGeneric;
        uint function(const Type type, uint initialsize, ArrayBuilderGeneric* outBuilder) nothrow @nogc ArrayBuilderNew;
        uint function(const ArrayBuilderGeneric builder, ArrayGeneric* outArray) nothrow @nogc ArrayBuilderFinish;
        size_t function(const ArrayBuilderGeneric builder, const DotNetObject obj) nothrow @nogc ArrayBuilderAddGeneric;

        DotNetObject function(const Type type, const ulong value) nothrow @nogc BoxEnumUInt64;
        static foreach (type; clr.primitiveTypes)
        {
            mixin("DotNetObject function(" ~ type.marshalType ~ ") nothrow @nogc Box" ~ type.name ~ ";");
            mixin("size_t function(const MethodInfo method, " ~ type.marshalType ~ ") nothrow @nogc CallStatic" ~ type.name ~ ";");
            mixin("size_t function(const ArrayBuilder!(clr.PrimitiveType." ~ type.name ~ ") builder, "
                ~ type.marshalType ~ ") nothrow @nogc ArrayBuilderAdd" ~ type.name ~ ";");
        }
        void function(const DotNetObject obj) nothrow @nogc DebugWriteObject;
    }
    struct Funcs
    {
        version (Windows)
        {
            extern (Windows):
            mixin FuncsMixin;
        }
        else
        {
            extern (C):
            mixin FuncsMixin;
        }
    }
    Funcs funcs;
    union PrimitiveTypes
    {
        struct
        {
            static foreach(type; clr.primitiveTypes)
            {
                mixin("Type " ~ type.name ~ ";");
            }
        }
        Type[clr.PrimitiveType.max + 1] array;
    }
    Assembly mscorlib;
    PrimitiveTypes primitiveTypes;
    Type typeType; // even though this isn't a primitive type,
                   // we cache this because it is used so commonly

    void debugWriteObject(const DotNetObject obj) { funcs.DebugWriteObject(obj); }

    void release(const DotNetObject obj) const nothrow @nogc
    {
        funcs.Release(obj);
    }

    DotNetObject boxEnum(T)(const Type enumType, Enum!T enumValue)
    {
        // TODO: will this handle signed types correct?  Maybe I need to cast to long first for singed types?
        return funcs.BoxEnumUInt64(enumType, cast(ulong)enumValue.integerValue);
    }
    ClrBridgeError tryBox(string typeName)(clr.DlangType!typeName value, DotNetObject *outObject) nothrow @nogc
    {
        *outObject = mixin("funcs.Box" ~ typeName ~ "(value)");
        return ClrBridgeError.none;
    }
    DotNetObject box(string typeName)(clr.DlangType!typeName value)
    {
        import std.format : format;

        DotNetObject obj;
        const result = tryBox!typeName(value, &obj);
        if (result.failed)
            throw new Exception(format("failed to box a value: %s", result));
        return obj;
    }

    ClrBridgeError tryLoadAssembly(CString name, Assembly* outAssembly) nothrow @nogc
    {
        const errorCode = funcs.LoadAssembly(name, outAssembly);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    Assembly loadAssembly(CString name)
    {
        import std.format : format;

        Assembly assembly;
        const result = tryLoadAssembly(name, &assembly);
        if (result.failed)
            throw new Exception(format("failed to load assembly '%s': %s", name, result));
        return assembly;
    }

    ClrBridgeError tryGetType(const Assembly assembly, CString name, Type* outType) nothrow @nogc
    {
        const errorCode = funcs.GetType(assembly, name, outType);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    Type getType(const Assembly assembly, CString name)
    {
        import std.format : format;

        Type type;
        const result = tryGetType(assembly, name, &type);
        if (result.failed)
            throw new Exception(format("failed to get type '%s': %s", name, result));
        return type;
    }

    ClrBridgeError tryResolveGenericType(const Type type, const ArrayGeneric types, Type* outType) nothrow @nogc
    {
        const errorCode = funcs.ResolveGenericType(type, types, outType);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    Type resolveGenericType(const Type type, const ArrayGeneric types)
    {
        import std.format : format;
        Type closedType;
        const result = tryResolveGenericType(type, types, &closedType);
        if (result.failed)
            throw new Exception(format("failed to resolve generic type: %s", result));
        return closedType;
    }

    ClrBridgeError tryGetConstructor(const Type type, const ArrayGeneric paramTypes, ConstructorInfo* outConstructor) nothrow @nogc
    {
        const errorCode = funcs.GetConstructor(type, paramTypes, outConstructor);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    ConstructorInfo getConstructor(const Type type, const ArrayGeneric paramTypes)
    {
        import std.format : format;

        ConstructorInfo constructor;
        const result = tryGetConstructor(type, paramTypes, &constructor);
        if (result.failed)
            throw new Exception(format("failed to get constructor: %s", result));
        return constructor;
    }

    ClrBridgeError tryGetMethod(const Type type, CString name, const ArrayGeneric paramTypes, MethodInfo* outMethod) nothrow @nogc
    {
        const errorCode = funcs.GetMethod(type, name, paramTypes, outMethod);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    MethodInfo getMethod(const Type type, CString name, const ArrayGeneric paramTypes)
    {
        import std.format : format;

        MethodInfo method;
        const result = tryGetMethod(type, name, paramTypes, &method);
        if (result.failed)
            throw new Exception(format("failed to get method '%s': %s", name, result));
        return method;
    }

    ClrBridgeError tryCallConstructor(const ConstructorInfo constructor, const Array!(clr.PrimitiveType.Object) args, DotNetObject* outObjectPtr) nothrow @nogc
    {
        const errorCode = funcs.CallConstructor(constructor, args, outObjectPtr);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    DotNetObject callConstructor(const ConstructorInfo constructor, const Array!(clr.PrimitiveType.Object) args)
    {
        import std.format : format;
        DotNetObject obj;
        const result = tryCallConstructor(constructor, args, &obj);
        if (result.failed)
            throw new Exception(format("failed to call constructor: %s", result));
        return obj;
    }

    ClrBridgeError tryArrayBuilderNewGeneric(const Type type, uint initialSize, ArrayBuilderGeneric* outBuilder) nothrow @nogc
    {
        const errorCode = funcs.ArrayBuilderNew(type, initialSize, outBuilder);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    ClrBridgeError tryArrayBuilderNew(clr.PrimitiveType T)(uint initialSize, ArrayBuilder!T* outBuilder) nothrow @nogc
    {
        return tryArrayBuilderNewGeneric(primitiveTypes.array[T], initialSize, cast(ArrayBuilderGeneric*)outBuilder);
    }
    ArrayBuilderGeneric arrayBuilderNewGeneric(const Type type, uint initialSize)
    {
        import std.format : format;

        ArrayBuilderGeneric builder;
        const result = tryArrayBuilderNewGeneric(type, initialSize, &builder);
        if (result.failed)
            throw new Exception(format("failed to create arraybuilder: %s", result));
        return builder;
    }
    ArrayBuilder!T arrayBuilderNew(clr.PrimitiveType T)(uint initialSize)
    {
        import std.format : format;

        ArrayBuilder!T builder;
        const result = tryArrayBuilderNew!T(initialSize, &builder);
        if (result.failed)
            throw new Exception(format("failed to create arraybuilder: %s", result));
        return builder;
    }
    mixin DotnetPrimitiveWrappers!("arrayBuilderNew");

    void arrayBuilderAddGeneric(const ArrayBuilderGeneric ab, const DotNetObject obj) nothrow @nogc
    {
        funcs.ArrayBuilderAddGeneric(ab, obj);
    }
    void arrayBuilderAdd(clr.PrimitiveType T)(const ArrayBuilder!T ab, clr.DlangType!T value) nothrow @nogc
    {
        mixin("funcs.ArrayBuilderAdd" ~ clr.Info!T.name ~ "(ab, value);");
    }
    mixin DotnetPrimitiveWrappers!("arrayBuilderAdd");

    ClrBridgeError tryArrayBuilderFinishGeneric(const ArrayBuilderGeneric ab, ArrayGeneric* outArray) nothrow @nogc
    {
        const errorCode = funcs.ArrayBuilderFinish(ab, outArray);
        if (errorCode != 0)
            return ClrBridgeError.forward(errorCode);
        return ClrBridgeError.none;
    }
    ClrBridgeError tryArrayBuilderFinish(clr.PrimitiveType T)(const ArrayBuilder!T ab, Array!T* outArray) nothrow @nogc
    {
        return tryArrayBuilderFinishGeneric(cast(ArrayBuilderGeneric)ab, cast(ArrayGeneric*)outArray);
    }
    mixin DotnetPrimitiveWrappers!("tryArrayBuilderFinish");

    ArrayGeneric arrayBuilderFinishGeneric(const ArrayBuilderGeneric ab)
    {
        import std.format : format;

        ArrayGeneric array;
        const result = tryArrayBuilderFinishGeneric(ab, &array);
        if (result.failed)
            throw new Exception(format("arrayBuilderFinish failed: %s", result));
        return array;
    }
    Array!T arrayBuilderFinish(clr.PrimitiveType T)(const ArrayBuilder!T ab)
    {
        return cast(Array!T)arrayBuilderFinishGeneric(cast(ArrayBuilderGeneric)ab);
    }
    mixin DotnetPrimitiveWrappers!("arrayBuilderFinish");

    /// Create a .NET array with the given arguments
    ClrBridgeError tryMakeGenericArray(T...)(Type type, ArrayGeneric* outArray, T args) nothrow @nogc
    {
        ArrayBuilderGeneric builder;
        {
            const result = tryArrayBuilderNewGeneric(type, T.length, &builder);
            if (result.failed) return result;
        }
        foreach (arg; args)
        {
            arrayBuilderAddGeneric(builder, arg);
        }
        return tryArrayBuilderFinishGeneric(builder, outArray);
    }
    ArrayGeneric makeGenericArray(T...)(Type type, T args)
    {
        import std.format : format;

        ArrayGeneric array;
        const result = tryMakeGenericArray(type, &array, args);
        if (result.failed)
            throw new Exception(format("makeArray failed: %s", result));
        return array;
    }
    Array!(clr.PrimitiveType.Object) makeObjectArray(T...)(T args)
    {
        import std.format : format;

        ArrayGeneric array;
        const result = tryMakeGenericArray(primitiveTypes.Object, &array, args);
        if (result.failed)
            throw new Exception(format("makeArray failed: %s", result));
        return cast(Array!(clr.PrimitiveType.Object))array;
    }

    //
    // Higher Level API
    //
    ArrayGeneric getTypesArray(TypeSpec[] types)()
    {
        const builder = arrayBuilderNewGeneric(typeType, types.length);
        scope (exit) release(builder);
        ClosedTypeResult[types.length] genericTypes;
        static foreach (i, genericTypeSpec; types)
        {
            genericTypes[i] = getClosedType!genericTypeSpec;
            arrayBuilderAddGeneric(builder, genericTypes[i].type);
            scope (exit) genericTypes[i].finalRelease(this);
        }
        return arrayBuilderFinishGeneric(builder);
    }
    ClosedTypeResult getClosedType(TypeSpec typeSpec)()
    {
        static if (IsMscorlib!(typeSpec.assemblyString))
        {
            static foreach (primitiveType; clr.primitiveTypes)
            {
                static if (typeSpec.typeName == primitiveType.fullName)
                    return ClosedTypeResult(__traits(getMember, primitiveTypes, primitiveType.name), false);
            }
            return getClosedType!typeSpec(mscorlib);
        }
        else
        {
            auto assembly = loadAssembly(CStringLiteral!(typeSpec.assemblyString));
            scope (exit) release(assembly);
            return getClosedType!typeSpec(assembly);
        }
    }
    ClosedTypeResult getClosedType(TypeSpec typeSpec)(const Assembly assembly)
    {
        // should I also handle primitive types in this function?
        static if (typeSpec.genericTypes.length > 0)
        {
            const genericTypesArray = getTypesArray!(typeSpec.genericTypes)();
            scope (exit) release(genericTypesArray);
        }
        Type unresolvedType = getType(assembly, CStringLiteral!(typeSpec.typeName));
        static if (typeSpec.genericTypes.length == 0)
            return ClosedTypeResult(unresolvedType, true);
        else
            return ClosedTypeResult(resolveGenericType(unresolvedType, genericTypesArray), true);
    }

    ConstructorInfo getConstructor(ConstructorSpec constructorSpec)()
    {
        const typeResult = getClosedType!(constructorSpec.typeSpec)();
        scope (exit) typeResult.finalRelease(this);
        return getConstructor!constructorSpec(typeResult.type);
    }
    ConstructorInfo getConstructor(ConstructorSpec constructorSpec)(const Type type)
    {
        const paramTypesArray = getTypesArray!(constructorSpec.paramTypes);
        scope (exit) release(paramTypesArray);
        return getConstructor(type, paramTypesArray);
    }

    MethodInfo getClosedMethod(MethodSpec methodSpec)()
    {
        const typeResult = getClosedType!(methodSpec.typeSpec)();
        scope (exit) typeResult.finalRelease(this);
        return getClosedMethod!methodSpec(typeResult.type);
    }
    MethodInfo getClosedMethod(MethodSpec methodSpec)(const Type type)
    {
        const paramTypesArray = getTypesArray!(methodSpec.paramTypes);
        scope (exit) release(paramTypesArray);
        return getClosedMethod!methodSpec(type, paramTypesArray);
    }
    MethodInfo getClosedMethod(MethodSpec methodSpec)(const Type type, const ArrayGeneric paramTypesArray)
    {
        static if (methodSpec.genericTypes.length > 0)
        {
            const genericTypesArray = getTypesArray!(methodSpec.genericTypes)();
            scope (exit) release(genericTypesArray);
        }
        auto unresolvedMethod = getMethod(type, CStringLiteral!(methodSpec.methodName), paramTypesArray);
        static if (methodSpec.genericTypes.length == 0)
            return unresolvedMethod;
        else
            return resolveGenericMethod(unresolvedMethod, genericTypesArray);
    }
}

/// Result of getClosedtype, abstracts whether or not it should be released
struct ClosedTypeResult
{
    Type type;
    bool canRelease;

    /// Release the object but don't mark that it is released.  The caller must guarantee release won't
    /// be called again, otherwise, it should call `trackedRelease`.
    void finalRelease(const ref ClrBridge bridge) const
    {
        if (canRelease)
            bridge.release(type);
    }

    /// Release the object and mark that it has been released in case release is called again later.
    /// If the caller can guarantee that release won't be called again then you can call finalRelease instead.
    void trackedRelease(const ref ClrBridge bridge)
    {
        if (canRelease)
        {
            bridge.release(type);
            canRelease = false;
        }
    }
}

template IsMscorlib(string assemblyString)
{
    static if (assemblyString == "mscorlib" ||
        (assemblyString.length >= 9 && assemblyString[0..9] == "mscorlib,"))
        enum IsMscorlib = true;
    else
        enum IsMscorlib = false;
}

struct MethodSpec
{
    TypeSpec typeSpec;
    string methodName;
    TypeSpec[] genericTypes;
    TypeSpec[] paramTypes;
}

struct ConstructorSpec
{
    TypeSpec typeSpec;
    TypeSpec[] paramTypes;
}

void castArrayCopy(T, U)(T* dst, U[] src)
{
    foreach (i; 0 .. src.length)
    {
        dst[i] = cast(T)src[i];
    }
}

immutable(wchar)* mallocWchar(const(char)[] s) @nogc
{
    wchar* ws = cast(wchar*)malloc(wchar.sizeof * (s.length + 1));
    assert(ws, "malloc failed");
    castArrayCopy(ws, s);
    ws[s.length] = '\0';
    return cast(immutable(wchar)*)ws;
}

template GetTypeSpec(T)
{
    static if (is(T.__clrmetadata))        enum GetTypeSpec = T.__clrmetadata.typeSpec;
    else static if (is(T == bool))          enum GetTypeSpec = TypeSpec("mscorlib", "System.Boolean");
    else static if (is(T == ubyte))        enum GetTypeSpec = TypeSpec("mscorlib", "System.Byte");
    else static if (is(T == byte))         enum GetTypeSpec = TypeSpec("mscorlib", "System.SByte");
    else static if (is(T == ushort))       enum GetTypeSpec = TypeSpec("mscorlib", "System.UInt16");
    else static if (is(T == short))        enum GetTypeSpec = TypeSpec("mscorlib", "System.Int16");
    else static if (is(T == uint))         enum GetTypeSpec = TypeSpec("mscorlib", "System.UInt32");
    else static if (is(T == int))          enum GetTypeSpec = TypeSpec("mscorlib", "System.Int32");
    else static if (is(T == ulong))        enum GetTypeSpec = TypeSpec("mscorlib", "System.UInt64");
    else static if (is(T == long))         enum GetTypeSpec = TypeSpec("mscorlib", "System.Int64");
    else static if (is(T == char))         enum GetTypeSpec = TypeSpec("mscorlib", "System.Char");
    else static if (is(T == CString))      enum GetTypeSpec = TypeSpec("mscorlib", "System.String");
    else static if (is(T == float))        enum GetTypeSpec = TypeSpec("mscorlib", "System.Single");
    else static if (is(T == double))       enum GetTypeSpec = TypeSpec("mscorlib", "System.Double");
    else static assert(0, "GetTypespec of type " ~ T.stringof ~ " not implemented");
}

/**
Reference a type from another .NET assembly
*/
template from(string name)
{
    mixin("import from = " ~ name ~ ";");
}

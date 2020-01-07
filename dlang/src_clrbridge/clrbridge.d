import std.traits : Parameters;

import cstring : CString, CStringLiteral;
import hresult;

import core.stdc.stdlib : malloc, free;

static import clr;
import clr : DotNetObject, Decimal;

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
    mixin(base ~ " baseObject;");
    alias baseObject this;
    static auto nullObject() { return typeof(this)(mixin(base ~ ".nullObject")); }
}
struct Assembly     { mixin DotNetObjectMixin!"DotNetObject"; }
struct Type         { mixin DotNetObjectMixin!"DotNetObject"; }
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
    struct Funcs
    {
        //extern(C) void function(void** args) nothrow @nogc TestArray;
        //extern(C) void function(size_t a, ...) nothrow @nogc TestVarargs;
        extern(C) void function(const DotNetObject obj) nothrow @nogc DebugWriteObject;
        extern(C) void function(const DotNetObject obj) nothrow @nogc Release;
        extern(C) uint function(CString name, Assembly* outAssembly) nothrow @nogc LoadAssembly;
        extern(C) size_t function(const Assembly assembly, CString name) nothrow @nogc GetType;
        extern(C) size_t function(const Type type, CString name, const ArrayGeneric paramTypes) nothrow @nogc GetMethod;
        extern(C) size_t function(const MethodInfo method, const DotNetObject obj, const Array!(clr.PrimitiveType.Object) paramTypes) nothrow @nogc CallGeneric;
        extern(C) size_t function(const Type type) nothrow @nogc NewObject;
        extern(C) size_t function(const Type type, uint initialsize) nothrow @nogc ArrayBuilderNew;
        extern(C) size_t function(const ArrayBuilderGeneric builder) nothrow @nogc ArrayBuilderFinish;
        extern(C) size_t function(const ArrayBuilderGeneric builder, const DotNetObject obj) nothrow @nogc ArrayBuilderAddGeneric;
        static foreach (type; clr.primitiveTypes)
        {
            mixin("extern(C) size_t function(" ~ type.dlangType ~ ") nothrow @nogc Box" ~ type.name ~ ";");
            mixin("extern(C) size_t function(const MethodInfo method, " ~ type.dlangType ~ ") nothrow @nogc CallStatic" ~ type.name ~ ";");
            mixin("extern(C) size_t function(const ArrayBuilder!(clr.PrimitiveType." ~ type.name ~ ") builder, "
                ~ type.dlangType ~ ") nothrow @nogc ArrayBuilderAdd" ~ type.name ~ ";");
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
    Type typeType; // we cache this because it is used so commonly

    void debugWriteObject(const DotNetObject obj) { funcs.DebugWriteObject(obj); }

    void release(const DotNetObject obj) nothrow @nogc
    {
        funcs.Release(obj);
    }

    ClrBridgeError tryBox(clr.PrimitiveType T)(clr.DlangType!T value, DotNetObject *outObject) nothrow @nogc
    {
        const result = mixin("funcs.Box" ~ clr.Info!T.name ~ "(value)");
        if (result <= 0xFF)
            return ClrBridgeError.forward(cast(ubyte)result);
        *outObject = DotNetObject(cast(void*)result);
        return ClrBridgeError.none;
    }
    DotNetObject box(clr.PrimitiveType T)(clr.DlangType!T value)
    {
        import std.format : format;

        DotNetObject obj;
        const result = tryBox!T(value, &obj);
        if (result.failed)
            throw new Exception(format("failed to box a value: %s", result));
        return obj;
    }

    ClrBridgeError tryLoadAssembly(CString name, Assembly* outAssembly) //nothrow @nogc
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
        const result = funcs.GetType(assembly, name);
        if (result <= 0xFF)
            return ClrBridgeError.forward(cast(ubyte)result);
        *outType = Type(DotNetObject(cast(void*)result));
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

    ClrBridgeError tryGetMethod(const Type type, CString name, const ArrayGeneric paramTypes, MethodInfo* outMethod) nothrow @nogc
    {
        const result = funcs.GetMethod(type, name, paramTypes);
        if (result <= 0xFF)
            return ClrBridgeError.forward(cast(ubyte)result);
        *outMethod = MethodInfo(DotNetObject(cast(void*)result));
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

    ClrBridgeError tryNewObject(const Type type, DotNetObject* outObject) nothrow @nogc
    {
        const result = funcs.NewObject(type);
        if (result <= 0xFF)
            return ClrBridgeError.forward(cast(ubyte)result);
        *outObject = DotNetObject(cast(void*)result);
        return ClrBridgeError.none;
    }
    DotNetObject newObject(const Type type)
    {
        import std.format : format;

        DotNetObject obj;
        const result = tryNewObject(type, &obj);
        if (result.failed)
            throw new Exception(format("failed to create new object: %s", result));
        return obj;
    }

    ClrBridgeError tryArrayBuilderNewGeneric(const Type type, uint initialSize, ArrayBuilderGeneric* outBuilder) nothrow @nogc
    {
        const result = funcs.ArrayBuilderNew(type, initialSize);
        if (result <= 0xFF)
            return ClrBridgeError.forward(cast(ubyte)result);
        *outBuilder = ArrayBuilderGeneric(DotNetObject(cast(void*)result));
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
        const result = funcs.ArrayBuilderFinish(ab);
        if (result <= 0xFF)
            return ClrBridgeError.forward(cast(ubyte)result);
        *outArray = ArrayGeneric(DotNetObject(cast(void*)result));
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

/**
Reference a type from another .NET assembly
*/
template fromDll(string name)
{
    mixin("import fromDll = " ~ name ~ ";");
}

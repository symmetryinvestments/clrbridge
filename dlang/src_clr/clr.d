// Data structures that represent the .NET CLR
module clr;

version (NoPhobos)
{
    alias AliasSeq(T...) = T;
}
else
{
    public import std.meta : AliasSeq;
}

enum PrimitiveType
{
    Boolean,
    
    Byte,
    SByte,
    UInt16,
    Int16,
    UInt32,
    Int32,
    UInt64,
    Int64,
    
    Char,
    String,
    
    Single,
    Double,
    Decimal,

    Object
}

struct PrimitiveTypeInfo
{
    PrimitiveType type;
    string dlangEquivalent;
    string marshalType;
    string name;
    string fullName;
    this(PrimitiveType type, string dlangEquivalent, string marshalType) immutable
    {
        import std.conv : to;
        this.type = type;
        this.dlangEquivalent = dlangEquivalent;
        this.marshalType = marshalType;
        this.name = to!string(type);
        this.fullName = "System." ~ name;
    }
    string toString() const { return name; }
}

enum primitiveTypes = [
    PrimitiveType.Boolean : immutable PrimitiveTypeInfo(PrimitiveType.Boolean, "bool",         "ushort"),
    PrimitiveType.Byte    : immutable PrimitiveTypeInfo(PrimitiveType.Byte   , "ubyte",        "ubyte"),
    PrimitiveType.SByte   : immutable PrimitiveTypeInfo(PrimitiveType.SByte  , "byte",         "byte"),
    PrimitiveType.UInt16  : immutable PrimitiveTypeInfo(PrimitiveType.UInt16 , "ushort",       "ushort"),
    PrimitiveType.Int16   : immutable PrimitiveTypeInfo(PrimitiveType.Int16  , "short",        "short"),
    PrimitiveType.UInt32  : immutable PrimitiveTypeInfo(PrimitiveType.UInt32 , "uint",         "uint"),
    PrimitiveType.Int32   : immutable PrimitiveTypeInfo(PrimitiveType.Int32  , "int",          "int"),
    PrimitiveType.UInt64  : immutable PrimitiveTypeInfo(PrimitiveType.UInt64 , "ulong",        "ulong"),
    PrimitiveType.Int64   : immutable PrimitiveTypeInfo(PrimitiveType.Int64  , "long",         "long"),
    PrimitiveType.Char    : immutable PrimitiveTypeInfo(PrimitiveType.Char   , "char",         "char"),
    PrimitiveType.String  : immutable PrimitiveTypeInfo(PrimitiveType.String , "CString",      "CString"),
    PrimitiveType.Single  : immutable PrimitiveTypeInfo(PrimitiveType.Single , "float",        "float"),
    PrimitiveType.Double  : immutable PrimitiveTypeInfo(PrimitiveType.Double , "double",       "double"),
    PrimitiveType.Decimal : immutable PrimitiveTypeInfo(PrimitiveType.Decimal, "Decimal",      "Decimal"),
    PrimitiveType.Object  : immutable PrimitiveTypeInfo(PrimitiveType.Object , "DotNetObject", "DotNetObject"),
];

template Info(PrimitiveType T)
{
    enum Info = primitiveTypes[T];
}

struct TypeSpec
{
    string assemblyString;
    string typeName;
    TypeSpec[] genericTypes;
}

struct DotNetObject
{
    static struct __clrmetadata
    {
        enum typeSpec = TypeSpec("mscorlib", "System.Object", null);
    }

    private void* _ptr;
    void* ptr() const { return cast(void*)_ptr; }
    static DotNetObject nullObject() { return typeof(this)(null); }
    bool isNull() const { return _ptr is null; }
}

struct Enum(T)
{
    static struct __clrmetadata
    {
        enum typeSpec = TypeSpec("mscorlib", "System.Enum", null);
    }

    T integerValue;
    typeof(this) opBinary(string op)(const typeof(this) right) const
    { return typeof(this)(mixin("this.integerValue " ~ op ~ " right.integerValue")); }
}

struct Decimal
{
    static struct __clrmetadata
    {
        enum typeSpec = TypeSpec("mscorlib", "System.Decimal", null);
    }

  align(1):
    uint flags;
    uint hi;
    uint lo;
    uint mid;
}

template DlangType(PrimitiveType T)
{
    import cstring : CString;

         static if (T == PrimitiveType.Boolean) alias DlangType = bool;
    else static if (T == PrimitiveType.Byte)    alias DlangType = ubyte;
    else static if (T == PrimitiveType.SByte)   alias DlangType = byte;
    else static if (T == PrimitiveType.UInt16)  alias DlangType = ushort;
    else static if (T == PrimitiveType.Int16)   alias DlangType = short;
    else static if (T == PrimitiveType.UInt32)  alias DlangType = uint;
    else static if (T == PrimitiveType.Int32)   alias DlangType = int;
    else static if (T == PrimitiveType.UInt64)  alias DlangType = ulong;
    else static if (T == PrimitiveType.Int64)   alias DlangType = long;
    else static if (T == PrimitiveType.Char)    alias DlangType = char;
    else static if (T == PrimitiveType.String)  alias DlangType = CString;
    else static if (T == PrimitiveType.Single)  alias DlangType = float;
    else static if (T == PrimitiveType.Double)  alias DlangType = double;
    else static if (T == PrimitiveType.Decimal) alias DlangType = Decimal;
    else static if (T == PrimitiveType.Object)  alias DlangType = DotNetObject;
    else static assert(0);
}

template DlangType(string typeName)
{
    import cstring : CString;

         static if (typeName == "Boolean") alias DlangType = bool;
    else static if (typeName == "Byte")    alias DlangType = ubyte;
    else static if (typeName == "SByte")   alias DlangType = byte;
    else static if (typeName == "UInt16")  alias DlangType = ushort;
    else static if (typeName == "Int16")   alias DlangType = short;
    else static if (typeName == "UInt32")  alias DlangType = uint;
    else static if (typeName == "Int32")   alias DlangType = int;
    else static if (typeName == "UInt64")  alias DlangType = ulong;
    else static if (typeName == "Int64")   alias DlangType = long;
    else static if (typeName == "Char")    alias DlangType = char;
    else static if (typeName == "String")  alias DlangType = CString;
    else static if (typeName == "Single")  alias DlangType = float;
    else static if (typeName == "Double")  alias DlangType = double;
    else static if (typeName == "Decimal") alias DlangType = Decimal;
    else static if (typeName == "Object")  alias DlangType = DotNetObject;
    else static if (typeName == "Enum")    alias DlangType = Enum;
    else static assert(0);
}

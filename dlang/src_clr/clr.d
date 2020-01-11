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
    string dlangType;
    string name;
    string fullName;
    this(PrimitiveType type, string dlangType) immutable
    {
        import std.conv : to;
        this.type = type;
        this.dlangType = dlangType;
        this.name = to!string(type);
        this.fullName = "System." ~ name;
    }
    string toString() const { return name; }
}

enum primitiveTypes = [
    PrimitiveType.Boolean : immutable PrimitiveTypeInfo(PrimitiveType.Boolean, "bool"),
    PrimitiveType.Byte    : immutable PrimitiveTypeInfo(PrimitiveType.Byte   , "ubyte"),
    PrimitiveType.SByte   : immutable PrimitiveTypeInfo(PrimitiveType.SByte  , "byte"),
    PrimitiveType.UInt16  : immutable PrimitiveTypeInfo(PrimitiveType.UInt16 , "ushort"),
    PrimitiveType.Int16   : immutable PrimitiveTypeInfo(PrimitiveType.Int16  , "short"),
    PrimitiveType.UInt32  : immutable PrimitiveTypeInfo(PrimitiveType.UInt32 , "uint"),
    PrimitiveType.Int32   : immutable PrimitiveTypeInfo(PrimitiveType.Int32  , "int"),
    PrimitiveType.UInt64  : immutable PrimitiveTypeInfo(PrimitiveType.UInt64 , "ulong"),
    PrimitiveType.Int64   : immutable PrimitiveTypeInfo(PrimitiveType.Int64  , "long"),
    PrimitiveType.Char    : immutable PrimitiveTypeInfo(PrimitiveType.Char   , "char"),
    PrimitiveType.String  : immutable PrimitiveTypeInfo(PrimitiveType.String , "CString"),
    PrimitiveType.Single  : immutable PrimitiveTypeInfo(PrimitiveType.Single , "float"),
    PrimitiveType.Double  : immutable PrimitiveTypeInfo(PrimitiveType.Double , "double"),
    PrimitiveType.Decimal : immutable PrimitiveTypeInfo(PrimitiveType.Decimal, "Decimal"),
    PrimitiveType.Object  : immutable PrimitiveTypeInfo(PrimitiveType.Object , "DotNetObject"),
];

template Info(PrimitiveType T)
{
    enum Info = primitiveTypes[T];
}


struct DotNetObject
{
    static struct __clrmetadata
    {
        enum assembly = "mscorlib"; // todo: full name? Maybe not necessary for mscorlib since you
                                    //       can't have 2 loaded at the same time? but maybe you could
                                    //       have another library with the name mscorlib?
        enum typeName = "System.Object";
        enum genericArgs = AliasSeq!();
    }

    private void* _ptr;
    void* ptr() const { return cast(void*)_ptr; }
    static DotNetObject nullObject() { return typeof(this)(null); }
    bool isNull() const { return _ptr is null; }
}
struct Decimal
{
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

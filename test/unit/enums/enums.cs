using System;

public enum Season { Spring, Summer, Autumn, Winter }

// test enums with different bases
public enum ByteBase : Byte { A, B, C}
public enum UInt64Base : UInt64 { A, B, C}

[Flags]
public enum SeasonFlags
{
    Spring = 0x1,
    Summer = 0x2,
    Autumn = 0x4,
    Winter = 0x8,
}

public static class StaticFuncs
{
    public static void WriteSeason(Season s) { Console.WriteLine("{0}", s); }
    public static Season PassthroughSeason(Season s) { return s; }
    public static ByteEnum PassthroughByteEnum(ByteEnum value) { return value; }
    public static SByteEnum PassthroughSByteEnum(SByteEnum value) { return value; }
}

public enum ByteEnum : Byte { _0 = 0, _1 = 1, _255 = 255 }
public enum SByteEnum : SByte { _neg128 = -128, _neg1 = -1, _0 = 0, _127 = 127 }

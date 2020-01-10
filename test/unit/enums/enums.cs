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

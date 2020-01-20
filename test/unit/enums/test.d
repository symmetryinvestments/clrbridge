import cstring;
import clr : Enum;
import enums;

void test()
{
    StaticFuncs.WriteSeason(Season.Spring);
    StaticFuncs.WriteSeason(Season.Summer);
    StaticFuncs.WriteSeason(Season.Autumn);
    StaticFuncs.WriteSeason(Season.Winter);
    assert(Season.Spring == StaticFuncs.PassthroughSeason(Season.Spring));

    assert(ByteEnum._0 == StaticFuncs.PassthroughByteEnum(ByteEnum._0));
    assert(ByteEnum._1 == StaticFuncs.PassthroughByteEnum(ByteEnum._1));
    assert(ByteEnum._255 == StaticFuncs.PassthroughByteEnum(ByteEnum._255));
    assert(SByteEnum._neg128 == StaticFuncs.PassthroughSByteEnum(SByteEnum._neg128));
    assert(SByteEnum._neg1   == StaticFuncs.PassthroughSByteEnum(SByteEnum._neg1));
    assert(SByteEnum._0      == StaticFuncs.PassthroughSByteEnum(SByteEnum._0));
    assert(SByteEnum._127    == StaticFuncs.PassthroughSByteEnum(SByteEnum._127));

    //assert(CStringLiteral!"Autumn".asSlice == Season.Autumn.ToString());
    //assert(Season.Summer == StaticFuncs.PassthroughSeason(Season.Summer));
    // TODO: test .Format
    // TODO: test .GetName
    // TODO: test .GetNames
    // TODO: test .GetValues
    // TODO: test Parse
    // TODO: test TryParse

    {
        auto season = Season.Summer;
        //assert(CStringLiteral!"Summer".asSlice == sea
    }


    {
        auto flags = SeasonFlags.Spring | SeasonFlags.Winter;
    }
}

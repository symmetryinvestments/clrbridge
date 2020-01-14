import cstring;
import clr : DotNetObject, Decimal;
import generics;

void test()
{
    ClassOneGeneric_1!bool.DumpTypeToConsole();
    ClassOneGeneric_1!ubyte.DumpTypeToConsole();
    ClassOneGeneric_1!byte.DumpTypeToConsole();
    ClassOneGeneric_1!ushort.DumpTypeToConsole();
    ClassOneGeneric_1!short.DumpTypeToConsole();
    ClassOneGeneric_1!uint.DumpTypeToConsole();
    ClassOneGeneric_1!int.DumpTypeToConsole();
    ClassOneGeneric_1!ulong.DumpTypeToConsole();
    ClassOneGeneric_1!long.DumpTypeToConsole();
    ClassOneGeneric_1!char.DumpTypeToConsole();
    ClassOneGeneric_1!CString.DumpTypeToConsole();
    ClassOneGeneric_1!float.DumpTypeToConsole();
    ClassOneGeneric_1!double.DumpTypeToConsole();
    ClassOneGeneric_1!Decimal.DumpTypeToConsole();
    ClassOneGeneric_1!DotNetObject.DumpTypeToConsole();
    {
        //const ClassOneGeneric_1!uint.New();
    }
    //GenericMethods.NoOpOneGeneric!DotNetObject();
    //GenericMethods.NoOpOneGeneric!DotNetObject(DotNetObject.nullObject);
    /*
    {
        auto c = ClassOneGeneric_1.New();
    }
    */
}

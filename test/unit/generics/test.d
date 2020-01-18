import cstring;
import clr : DotNetObject, Decimal, primitiveTypes, DlangType;
import generics;

void test()
{
    static foreach (primitiveType; primitiveTypes)
    {{
        alias C = ClassOneGeneric_1!(DlangType!(primitiveType.type));
        C.DumpTypeToConsole();
        static foreach (primitiveType2; primitiveTypes)
        {
            // TODO: since we are defining the type inside the other type, we don't
            // need to incldue both template types
            //C.SubGeneric_1!(DlangType!(primitiveType2.type)).DumpTypesToConsole();
        }
    }}

    //assert(false == ClassOneGeneric_1!bool.Passthrough(false));
    {
        //const c0 = ClassLevel0Generic!uint.New();
    }
    //GenericMethods.NoOpOneGeneric!DotNetObject();
    //GenericMethods.NoOpOneGeneric!DotNetObject(DotNetObject.nullObject);
    /*
    {
        auto c = ClassOneGeneric_1.New();
    }
    */
}

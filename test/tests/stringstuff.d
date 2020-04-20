import cstring;
import mscorlib.system.text;

void test()
{
    {
        auto builder = StringBuilder.New();
        // assert(builder.Length == 0);
        builder.Append(CStringLiteral!"hello");
        const result = builder.ToString(0, 5);
        assert(builder.ToString(0, 5).asSlice == CStringLiteral!"hello".asSlice);
        builder.Append(CStringLiteral!" world");
        assert(builder.ToString(0, 11).asSlice == CStringLiteral!"hello world".asSlice);

        // ToString not working because reflection is not seeing System.Object.ToString,
        // I think System.Reflection may not be seeing virtual methods?
        //assert(builder.ToString().asSlice == CStringLiteral!"hello");
        // TODO: add more
    }
}
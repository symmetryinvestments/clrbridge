import cstring;
import mscorlib.System.Text;

void test()
{
    {
        auto builder = StringBuilder.New();
        // assert(builder.Length == 0);
        builder.Append(CStringLiteral!"hello");
        // ToString not working because inherited methods aren't working
        //assert(builder.ToString().asSlice == CStringLiteral!"hello");
        // TODO: add more
    }
}
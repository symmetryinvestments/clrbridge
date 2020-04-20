import std.stdio;
import cstring;
import mscorlib.system;

void test()
{
    Environment.SetEnvironmentVariable(CStringLiteral!"FOO", CStringLiteral!"BAR");
    const str = Environment.GetEnvironmentVariable(CStringLiteral!"FOO");
    writefln("str is '%s'", str);
    assert(str.asSlice == "BAR");
}

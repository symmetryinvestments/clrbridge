import std.stdio;

template from(string moduleName)
{
    mixin("import from = " ~ moduleName ~ ";");
}
static import basicconsole;

void runAll()
{
    static foreach (testName; [
        "basicconsole",
        "stringstuff",
    ])
    {
        writeln("--------------------------------------------------------------------------------");
        writefln("test: %s", testName);
        writeln("--------------------------------------------------------------------------------");
        from!testName.test();
    }
}

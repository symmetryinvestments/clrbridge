import std.stdio;

template from(string moduleName)
{
    mixin("import from = " ~ moduleName ~ ";");
}
static import basicconsole;

void runAll()
{
    writeln("--------------------------------------------------------------------------------");
    writefln("test: basicconsole");
    writeln("--------------------------------------------------------------------------------");
    from!"basicconsole".test();
}

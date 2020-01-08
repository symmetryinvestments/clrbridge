import cstring;
import std.stdio;
import fields;
void test()
{
    ClassWithFields c;
    writefln("uint32Field = %s", c.uint32Field);
    writefln("stringField = %s", c.stringField);
}

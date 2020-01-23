import cstring;
import std.stdio;
import fields;
void test()
{
    ClassWithFields c;
    // field subs implemented but don't do anyting yet
    { const f = &c.uint32Field; }
    { const f = &c.stringField; }
    // TODO: call the fields and test them
}

import namespaces_original_case.Foo : InFoo;
import namespaces_original_case.Foo.Bar : InFooBar;
import namespaces_original_case.Foo.Bar.Baz : InFooBarBaz;
void test()
{
    InFoo.NoOp();
    InFooBar.NoOp();
    InFooBarBaz.NoOp();
}

import namespaces_default_case.foo : InFoo;
import namespaces_default_case.foo.bar : InFooBar;
import namespaces_default_case.foo.bar.baz : InFooBarBaz;
void test()
{
    InFoo.NoOp();
    InFooBar.NoOp();
    InFooBarBaz.NoOp();
}

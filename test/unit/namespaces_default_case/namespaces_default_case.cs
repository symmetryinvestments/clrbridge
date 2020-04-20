using System;

namespace Foo
{
    public static class InFoo { public static void NoOp() { } }
    namespace Bar
    {
        public static class InFooBar { public static void NoOp() { } }
        namespace Baz
        {
            public static class InFooBarBaz { public static void NoOp() { } }
        }
    }
}

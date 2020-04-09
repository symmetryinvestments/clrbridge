import filtermethod;
void test()
{
    static assert(!__traits(hasMember, T, "MethodToExclude"));
    T.MethodToKeep();
}

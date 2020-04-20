import cstring;
import mscorlib.system;

void test()
{
    foreach (i; 0 .. 3)
        Console.WriteLine();
    Console.WriteLine(false);
    Console.WriteLine(true);
    Console.WriteLine(CStringLiteral!"hello!");
    foreach (i; 0 .. 3)
        Console.WriteLine();
}

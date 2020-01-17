using System;

public static class ClassOneGeneric<T>
{
    public static void DumpTypeToConsole()
    {
        Console.WriteLine("ClassOneGeneric {0}", typeof(T));
    }
    //public static T Passthrough(T value) { return value; }

    //public T value;
    //public T Value { get { return value; } }
}

public static class GenericMethods
{
    public static void NoOpOneGeneric<T>() { }
    public static T ReturnOneGeneric<T>(T value) { return value; }
}

public class CassLevel0Generic<T>
{
    public T level0Field;
    public class ClassLevel1Generic<U>
    {
        public T level0Field;
        public U level1Field;
        public class ClassLevel2Generic<V>
        {
            public T level0Field;
            public U level1Field;
            public V level2Field;
        }
    }
}

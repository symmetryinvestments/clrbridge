
public static class GenericMethods
{
    public static void NoOpOneGeneric<T>(T value) { }
    public static T ReturnOneGeneric<T>(T value) { return value; }
}

public class ClassOneGeneric<T>
{
    public T value;
    public T Value { get { return value; } }
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

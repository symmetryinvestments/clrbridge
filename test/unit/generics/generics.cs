
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

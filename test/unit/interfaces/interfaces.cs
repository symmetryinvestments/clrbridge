using System;

public interface IEmpty
{
}

public interface IInt32
{
    void SetValue(Int32 value);
    Int32 GetValue();
}

public static class Factory
{
    class EmptyClass : IEmpty { }
    public static IEmpty CreateIEmpty() { return new EmptyClass(); }

    class Int32Class : IInt32
    {
        Int32 value;
        void IInt32.SetValue(Int32 value) { this.value = value; }
        Int32 IInt32.GetValue() { return value; }
    }
    public static IInt32 CreateIInt32() { return new Int32Class(); }
}

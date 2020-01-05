using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

public static partial class ClrBridge
{
    const Byte ErrorFileNotFound = 1;
    const Byte ErrorTypeNotFound = 2;
    const Byte ErrorMethodNotFound = 3;
    const Byte ErrorAmbiguousMethod = 4;

    /*
    // libcorclr doesn't seem to support marshalling arrays
    static void TestArray(Object[] array)
    {
        Console.WriteLine("TestArray");
        Console.WriteLine("array.Length={0}", array.Length);
    }

    // libcorclr doesn't seem to support varargs
    static void TestVarargs(params Object[] args)
    {
        Console.WriteLine("TestVarargs");
        Console.WriteLine("args.Length={0}", args.Length);
    }
    */

    static void DebugWriteObject(IntPtr objPtr)
    {
        object obj = GCHandle.FromIntPtr(objPtr).Target;
        {
            Array arr = obj as Array;
            if (arr != null)
            {
                Console.WriteLine("DebugWriteObject: array of length {0}", arr.Length);
                for (uint i = 0; i < arr.Length; i++)
                {
                    Console.WriteLine("DebugWriteObject: [{0}] '{1}'", i, arr.GetValue(i));
                }
                return;
            }
        }
        Console.WriteLine("DebugWriteObject: '{0}'", obj);
    }

    // Most objects created by this class use GC.Alloc to pin them.
    // Call this to unpin them.
    static void Release(IntPtr ptr)
    {
        GCHandle.FromIntPtr(ptr).Free();
    }

    static IntPtr LoadAssembly(string name)
    {
        Assembly assembly;
        try { assembly = Assembly.Load(name); }
        catch (FileNotFoundException) { return new IntPtr(ErrorFileNotFound); }
        return GCHandle.ToIntPtr(GCHandle.Alloc(assembly));
    }
    // TODO: add LoadAssemblyFile to call Assembly.LoadFile
    //static IntPtr LoadAssemblyFile(string

    static IntPtr GetType(IntPtr assemblyPtr, string typeName)
    {
        Assembly assembly = (Assembly)GCHandle.FromIntPtr(assemblyPtr).Target;
        Type type = assembly.GetType(typeName, false);
        if (type == null)
            return new IntPtr(ErrorTypeNotFound);
        return GCHandle.ToIntPtr(GCHandle.Alloc(type));
    }

    static IntPtr GetMethod(IntPtr typePtr, string methodName, IntPtr paramTypesArrayPtr)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        Type[] paramTypes = null;
        if (paramTypesArrayPtr != IntPtr.Zero)
            paramTypes = (Type[])GCHandle.FromIntPtr(paramTypesArrayPtr).Target;

        MethodInfo methodInfo;
        try
        {
            if (paramTypes == null)
                methodInfo = type.GetMethod(methodName);
            else
                methodInfo = type.GetMethod(methodName, paramTypes);
        }
        catch(AmbiguousMatchException) { return new IntPtr(ErrorAmbiguousMethod); }
        if (methodInfo == null)
            return new IntPtr(ErrorMethodNotFound);
        return GCHandle.ToIntPtr(GCHandle.Alloc(methodInfo));
    }

    static void CallGeneric(IntPtr methodPtr, IntPtr objPtr, IntPtr argsArrayPtr)
    {
        MethodInfo method = (MethodInfo)GCHandle.FromIntPtr(methodPtr).Target;
        Object obj = null;
        if (objPtr != IntPtr.Zero)
            obj = GCHandle.FromIntPtr(objPtr).Target;
        Object[] args = (Object[])GCHandle.FromIntPtr(argsArrayPtr).Target;
        method.Invoke(obj, args);
    }

    static IntPtr NewObject(IntPtr typePtr)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        return GCHandle.ToIntPtr(GCHandle.Alloc(Activator.CreateInstance(type)));
    }

    static IntPtr ArrayBuilderNew(IntPtr typePtr, UInt32 initialSize)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        Type arrayType = typeof(ArrayBuilder<>).MakeGenericType(type);
        return GCHandle.ToIntPtr(GCHandle.Alloc(Activator.CreateInstance(arrayType, initialSize)));
    }
    static IntPtr ArrayBuilderFinish(IntPtr arrayBuilderPtr)
    {
        Object arrayBuilder = GCHandle.FromIntPtr(arrayBuilderPtr).Target;
        return GCHandle.ToIntPtr(GCHandle.Alloc(
            arrayBuilder.GetType().GetMethod("Finish").Invoke(arrayBuilder, null)));
    }
    static void ArrayBuilderAddGeneric(IntPtr arrayBuilderPtr, IntPtr objPtr)
    {
        Object arrayBuilder = GCHandle.FromIntPtr(arrayBuilderPtr).Target;
        Object obj = GCHandle.FromIntPtr(objPtr).Target;
        arrayBuilder.GetType().GetMethod("Add").Invoke(arrayBuilder, new Object[] {obj});
    }
}

public class ArrayBuilder<T>
{
    const Int32 DefaultInitialSize = 16;

    T[] array;
    Int32 count;

    public ArrayBuilder(UInt32 initialSize)
        : this(new T[initialSize], 0)
    {
    }
    public ArrayBuilder(T[] array, Int32 count)
    {
        this.array = array;
        this.count = count;
    }

    public void Add(T obj)
    {
        if (this.count >= array.Length)
        {
            T[] newArray = new T[this.array.Length * 2];
            Array.Copy(this.array, newArray, this.count);
            this.array = newArray;
        }
        this.array[this.count++] = obj;
    }
    public T[] Finish()
    {
        if (array.Length != count)
        {
            T[] newArray = new T[this.count];
            Array.Copy(this.array, newArray, this.count);
            this.array = newArray;
        }
        return this.array;
    }
}

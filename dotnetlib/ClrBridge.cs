using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

static class ResultCode
{
    public const UInt32 Success = 0;
    public const UInt32 ErrorFileNotFound = 1;
    public const UInt32 ErrorTypeNotFound = 2;
    public const UInt32 ErrorMethodNotFound = 3;
    public const UInt32 ErrorAmbiguousMethod = 4;
}

public static partial class ClrBridge
{
    // Most objects created by this class use GC.Alloc to pin them.
    // Call this to unpin them.
    public static void Release(IntPtr ptr)
    {
        GCHandle.FromIntPtr(ptr).Free();
    }

    public static UInt32 LoadAssembly(string name, ref IntPtr outAssembly)
    {
        Assembly assembly;
        try { assembly = Assembly.Load(name); }
        catch (FileNotFoundException) { return ResultCode.ErrorFileNotFound; }
        outAssembly =  GCHandle.ToIntPtr(GCHandle.Alloc(assembly));
        return ResultCode.Success;
    }
    // TODO: add LoadAssemblyFile to call Assembly.LoadFile
    //static IntPtr LoadAssemblyFile(string

    public static UInt32 GetType(IntPtr assemblyPtr, string typeName, ref IntPtr outType)
    {
        Assembly assembly = (Assembly)GCHandle.FromIntPtr(assemblyPtr).Target;
        Type type = assembly.GetType(typeName, false);
        if (type == null)
            return ResultCode.ErrorTypeNotFound;
        outType = GCHandle.ToIntPtr(GCHandle.Alloc(type));
        return ResultCode.Success;
    }

    public static UInt32 GetMethod(IntPtr typePtr, string methodName, IntPtr paramTypesArrayPtr, ref IntPtr outMethod)
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
        catch(AmbiguousMatchException) { return ResultCode.ErrorAmbiguousMethod; }
        if (methodInfo == null)
            return ResultCode.ErrorMethodNotFound;
        outMethod = GCHandle.ToIntPtr(GCHandle.Alloc(methodInfo));
        return ResultCode.Success;
    }

    // TODO: add IntPtr for return value
    public static void CallGeneric(IntPtr methodPtr, IntPtr objPtr, IntPtr argsArrayPtr)
    {
        MethodInfo method = (MethodInfo)GCHandle.FromIntPtr(methodPtr).Target;
        Object obj = null;
        if (objPtr != IntPtr.Zero)
            obj = GCHandle.FromIntPtr(objPtr).Target;
        Object[] args = (Object[])GCHandle.FromIntPtr(argsArrayPtr).Target;
        method.Invoke(obj, args);
    }

    public static UInt32 NewObject(IntPtr typePtr, ref IntPtr outObject)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        outObject = GCHandle.ToIntPtr(GCHandle.Alloc(Activator.CreateInstance(type)));
        return ResultCode.Success;
    }

    public static UInt32 ArrayBuilderNew(IntPtr typePtr, UInt32 initialSize, ref IntPtr outBuilder)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        Type arrayType = typeof(ArrayBuilder<>).MakeGenericType(type);
        outBuilder = GCHandle.ToIntPtr(GCHandle.Alloc(Activator.CreateInstance(arrayType, initialSize)));
        return ResultCode.Success;
    }
    public static UInt32 ArrayBuilderFinish(IntPtr arrayBuilderPtr, ref IntPtr outArray)
    {
        Object arrayBuilder = GCHandle.FromIntPtr(arrayBuilderPtr).Target;
        outArray = GCHandle.ToIntPtr(GCHandle.Alloc(
            arrayBuilder.GetType().GetMethod("Finish").Invoke(arrayBuilder, null)));
        return ResultCode.Success;
    }
    public static void ArrayBuilderAddGeneric(IntPtr arrayBuilderPtr, IntPtr objPtr)
    {
        Object arrayBuilder = GCHandle.FromIntPtr(arrayBuilderPtr).Target;
        Object obj = GCHandle.FromIntPtr(objPtr).Target;
        arrayBuilder.GetType().GetMethod("Add").Invoke(arrayBuilder, new Object[] {obj});
    }

    public static void DebugWriteObject(IntPtr objPtr)
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

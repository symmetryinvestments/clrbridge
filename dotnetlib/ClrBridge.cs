using System;
using System.Diagnostics;
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

static class EmptyArray<T>
{
    public static readonly T[] Instance = new T[] { };
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

    // Take an "open" generic type (has unresolved type parameters), and resolve it to a "closed" type using the give array of types
    public static UInt32 ResolveGenericType(IntPtr typePtr, IntPtr typesArrayPtr, ref IntPtr outType)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        Type[] types = null;
        if (typesArrayPtr != IntPtr.Zero)
            types = (Type[])GCHandle.FromIntPtr(typesArrayPtr).Target;
        Type closedType = type.MakeGenericType(types);
        Debug.Assert(closedType != null, "did not expect MakeGenericType to return null");
        outType = GCHandle.ToIntPtr(GCHandle.Alloc(closedType));
        return ResultCode.Success;
    }

    public static UInt32 GetConstructor(IntPtr typePtr, IntPtr paramTypesArrayPtr, ref IntPtr outConstructor)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        Type[] paramTypes = null;
        if (paramTypesArrayPtr != IntPtr.Zero)
            paramTypes = (Type[])GCHandle.FromIntPtr(paramTypesArrayPtr).Target;

        ConstructorInfo constructor;
        if (paramTypes == null)
            constructor = type.GetConstructor(EmptyArray<Type>.Instance);
        else
            constructor = type.GetConstructor(paramTypes);
        if (constructor == null)
            return ResultCode.ErrorMethodNotFound;
        outConstructor = GCHandle.ToIntPtr(GCHandle.Alloc(constructor));
        return ResultCode.Success;
    }

    public static UInt32 GetMethod(IntPtr typePtr, string methodName, IntPtr paramTypesArrayPtr, ref IntPtr outMethod)
    {
        Type type = (Type)GCHandle.FromIntPtr(typePtr).Target;
        Type[] paramTypes = null;
        if (paramTypesArrayPtr != IntPtr.Zero)
            paramTypes = (Type[])GCHandle.FromIntPtr(paramTypesArrayPtr).Target;

        MethodInfo method;
        try
        {
            if (paramTypes == null)
                method = type.GetMethod(methodName);
            else
                method = type.GetMethod(methodName, paramTypes);
        }
        catch(AmbiguousMatchException) { return ResultCode.ErrorAmbiguousMethod; }
        if (method == null)
            return ResultCode.ErrorMethodNotFound;
        outMethod = GCHandle.ToIntPtr(GCHandle.Alloc(method));
        return ResultCode.Success;
    }

    public static UInt32 CallConstructor(IntPtr constructorPtr, IntPtr argsArrayPtr, ref IntPtr outObjectPtr)
    {
        ConstructorInfo ctor = (ConstructorInfo)GCHandle.FromIntPtr(constructorPtr).Target;
        Object[] args = (argsArrayPtr == IntPtr.Zero) ? EmptyArray<Object>.Instance :
            (Object[])GCHandle.FromIntPtr(argsArrayPtr).Target;
        outObjectPtr = GCHandle.ToIntPtr(GCHandle.Alloc(ctor.Invoke(args)));
        return ResultCode.Success;
    }

    public static void CallGeneric(IntPtr methodPtr, IntPtr objPtr, IntPtr argsArrayPtr, IntPtr returnValuePtr)
    {
        MethodInfo method = (MethodInfo)GCHandle.FromIntPtr(methodPtr).Target;
        Object obj = null;
        if (objPtr != IntPtr.Zero)
            obj = GCHandle.FromIntPtr(objPtr).Target;
        Object[] args = null;
        if (argsArrayPtr != IntPtr.Zero)
            args = (Object[])GCHandle.FromIntPtr(argsArrayPtr).Target;
        MarshalReturnValue(method.ReturnType, method.Invoke(obj, args), returnValuePtr);
    }

    private unsafe static void MarshalReturnValue(Type type, Object obj, IntPtr returnValuePtr)
    {
        if (type == typeof(void)) {
            // nothing to marshall
        } else if (type == typeof(Boolean)) {
            *(UInt16*)returnValuePtr = ((Boolean)obj) ? (UInt16)1 : (UInt16)0;
        } else if (type == typeof(Byte)) {
            *(Byte*)returnValuePtr = (Byte)obj;
        } else if (type == typeof(SByte)) {
            *(SByte*)returnValuePtr = (SByte)obj;
        } else if (type == typeof(UInt16)) {
            *(UInt16*)returnValuePtr = (UInt16)obj;
        } else if (type == typeof(Int16)) {
            *(Int16*)returnValuePtr = (Int16)obj;
        } else if (type == typeof(UInt32)) {
            *(UInt32*)returnValuePtr = (UInt32)obj;
        } else if (type == typeof(Int32)) {
            *(Int32*)returnValuePtr = (Int32)obj;
        } else if (type == typeof(UInt64)) {
            *(UInt64*)returnValuePtr = (UInt64)obj;
        } else if (type == typeof(Int64)) {
            *(Int64*)returnValuePtr = (Int64)obj;
        } else if (type == typeof(String)) {
            *(IntPtr*)returnValuePtr = Marshal.StringToHGlobalAnsi((String)obj);
        } else if (type == typeof(Single)) {
            *(Single*)returnValuePtr = (Single)obj;
        } else if (type == typeof(Double)) {
            *(Double*)returnValuePtr = (Double)obj;
        } else if (type == typeof(Decimal)) {
            *(Decimal*)returnValuePtr = (Decimal)obj;
        } else {
            Console.WriteLine("WARNING: cannot marshal return type '{0}' to native yet", type.Name);
        }
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

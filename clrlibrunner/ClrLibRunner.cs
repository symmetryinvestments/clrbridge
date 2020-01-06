using System;
using System.Reflection;
using System.Runtime.InteropServices;

class ClrLibRunner
{
    const String EntryName = "mainClr";
    delegate Int32 EntryDelegate(IntPtr createDelegateFuncPtr, Int32 argc/*, Char** argv*/);

    // TODO: format these as correct HRESULTs
    const UInt32 ErrorRequestedNonStaticMethod = 0x80000001;

    //Int32 delegate(/*Delegate dg, */Int32 argc, Char** argv/*, Char** envp*/);
    public static Int32 Main(String[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Usage: ClrLibRunner.exe <NativeSharedLibrary> <Args>...");
            return 1;
        }
        string sharedLibrary = args[0];

        // TODO: detect which platform we are on to know how to load a shared library correctly
        bool onLinux = true;

        EntryDelegate entry;
        if (onLinux)
        {
            const uint RTLD_NOW = 2;
            IntPtr moduleHandle = LinuxNativeMethods.dlopen(sharedLibrary, RTLD_NOW);
            if (moduleHandle == IntPtr.Zero)
            {
                Console.WriteLine("Error: dlopen '{0}' failed, errno={1}", sharedLibrary, Marshal.GetLastWin32Error());
                return 1;
            }
            IntPtr funcPtr = LinuxNativeMethods.dlsym(moduleHandle, EntryName);
            if (funcPtr == IntPtr.Zero)
            {
                Console.WriteLine("Error: dlsym '{0}' failed (TODO: get error code/message)", EntryName);
                return 1;
            }
            entry = (EntryDelegate)Marshal.GetDelegateForFunctionPointer(funcPtr, typeof(EntryDelegate));
        }
        else
        {
            Console.WriteLine("Error: unsupported platform");
            return 1;
        }
        IntPtr createDelegateFuncPtr = Marshal.GetFunctionPointerForDelegate(new CreateDelegateDelegate(CreateDelegate));
        return entry(createDelegateFuncPtr, args.Length/*, args*/);
    }

    delegate uint CreateDelegateDelegate(String assemblyName, String typeName, String methodName, ref IntPtr outFuncAddr);

    // Returns: HRESULT on error
    static uint CreateDelegate(String assemblyName, String typeName, String methodName, ref IntPtr outFuncAddr)
    {
        Console.WriteLine("[DEBUG] CreateDelegate called");
        Console.WriteLine("[DEBUG] assemblyName={0} typeName={1} methodName={2}", assemblyName, typeName, methodName);
        Assembly assembly = Assembly.Load(assemblyName);
        Type type = assembly.GetType(typeName);
        MethodInfo method = type.GetMethod(methodName);
        // we purposefully disallow this to keep this interface the same with the coreclr interfacen
        if (!method.IsStatic)
            return ErrorRequestedNonStaticMethod;
        // TODO: why do I pass 'type' here? Is this right?
        Delegate dg = method.CreateDelegate(type);
        outFuncAddr = GCHandle.ToIntPtr(GCHandle.Alloc(dg));
        return 0;
    }
}


static class LinuxNativeMethods
{
    [DllImport("libdl.so")]
    public static extern IntPtr dlopen(String filename, uint flags);

    [DllImport("libdl.so")]
    public static extern IntPtr dlsym(IntPtr handle, String symbol);
}


/*
TODO: support for windows
static class WindowsNativeMethods
{
     [DllImport("kernel32.dll", SetLastError = true)]
     public static extern IntPtr LoadLibrary(String dllToLoad);

     [DllImport("kernel32.dll", SetLastError = true)]
     public static extern IntPtr GetProcAddress(IntPtr hModule, String procedureName);

     [DllImport("kernel32.dll", SetLastError = true)]
     public static extern bool FreeLibrary(IntPtr hModule);
}
The unmanaged library should be loaded by calling LoadLibrary:

IntPtr moduleHandle = LoadLibrary("path/to/library.dll");
Get a pointer to a function in the dll by calling GetProcAddress:

IntPtr ptr = GetProcAddress(moduleHandle, methodName);
Cast this ptr to a delegate of type TDelegate:

TDelegate func = Marshal.GetDelegateForFunctionPointer(
    ptr, typeof(TDelegate)) as TDelegate;

*/

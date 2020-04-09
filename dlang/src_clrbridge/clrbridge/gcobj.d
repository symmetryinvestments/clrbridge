/// Provide an object that will automaticlaly release C# objects
/// when they are garbage-collected by the D GC.
module clrbridge.gcobj;

GCObj!T newGcObj(T)(T handleObj)
{
    return new GCObj!T(handleObj);
}

// Wrap a C# Handle Object with a D GC object that
// will automatically release the underlying Handle Object
// when D cleans up this object.
class GCObj(T)
{
    T obj;
    alias obj this;
    this(T obj) { this.obj = obj; }
    ~this()
    {
        import clrbridge.global: globalClrBridge;
        globalClrBridge.release(obj);
    }
}

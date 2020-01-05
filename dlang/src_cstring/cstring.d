module cstring;

struct CString
{
    private const(char)* _ptr;
    const(char)* ptr() const nothrow @nogc { return cast(const(char)*)_ptr; }
    alias ptr this;
    const(char)[] asSlice() const nothrow @nogc
    {
        import core.stdc.string : strlen;
        if (_ptr is null) return null;
        return cast(string)_ptr[0 .. strlen(_ptr)];
    }
    void toString(Sink)(Sink sink) const
    {
        const s = asSlice();
        sink((s is null) ? "<null>" : s);
    }
}

enum CStringLiteral(string s) = CString(s.ptr);

immutable(CString) toCString(scope const(char)[] s) pure nothrow @trusted
{
    import std.string : toStringz;
    return immutable CString(toStringz(s));
}
immutable(CString) toCString(scope return string s) pure nothrow @trusted
{
    import std.string : toStringz;
    return immutable CString(toStringz(s));
}

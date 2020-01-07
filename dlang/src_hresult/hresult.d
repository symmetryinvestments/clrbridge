// TODO: this should come from another library, like druntime
module hresult;

struct HRESULT
{
    private uint value;
    bool passed() const { return value == 0; }
    bool failed() const { return value != 0; }
    uint rawValue() const { return value; }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        import std.format: formattedWrite;
        formattedWrite(sink, "0x%x", value);
    }
}

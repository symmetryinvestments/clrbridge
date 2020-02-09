// A special unit test just for booleans because booleans are special.  Since they are marshaled as 16-bit integers,
// they are the only dlang type where the marshal type is different from the dlang equivalent type.
import cstring;
import clr : PrimitiveType, Decimal, TypeSpec, DotNetObject;
import clrbridge : MethodSpec;
import clrbridge.global : globalClrBridge;
import booleans;
import std.stdio;

void test()
{
    testBool(0, false);
    // booleans should be marshalled as 16-bit values, this tests that's the case
    for (ushort value = 1; value != 0; value <<= 1)
    {
        testBool(value, true);        
    }
}

void testBool(ushort value, bool expected)
{
    writefln("testing %s (0x%x) resolves to %s", value, value, expected);
    enum typeSpec = TypeSpec("booleans", "Funcs");
    enum methodSpec = MethodSpec(typeSpec, "Passthrough", null, [TypeSpec("mscorlib", "System.Boolean")]);

    const method = globalClrBridge.getClosedMethod!(methodSpec);
    scope (exit) globalClrBridge.release(method);

    const arg = globalClrBridge.funcs.BoxBoolean(value);
    scope (exit) globalClrBridge.release(arg);
    const args = globalClrBridge.makeObjectArray(arg);
    scope (exit) globalClrBridge.release(args);

    ushort returnValue = expected ? 0 : 0xFFFF;
    // TODO: no error return code?
    globalClrBridge.funcs.CallGeneric(method, DotNetObject.nullObject, args, cast(void**)&returnValue);
    assert(returnValue == expected ? 1 : 0);
}

#!/usr/bin/env rund
//!importPath dlang/src_hresult
//!importPath dlang/src_cstring
//!importPath out/DerelictUtil/source
//!importPath dlang/src_coreclr
//!importPath dlang/src_clr
//!importPath dlang/src_clrbridge

import std.file : thisExePath;
import std.path : buildPath, dirName;
import std.stdio;

import cstring;
import coreclr;
import coreclr.host;
import clrbridge;
import clrbridge.global;
import clrbridge.coreclr;

static import clr;

int main()
{
    initGlobalClrBridgeWithCoreclr(buildPath(__FILE_FULL_PATH__.dirName, "out", "ClrBridge.dll"));

    // test failure
    {
        writefln("checking that error handling works...");
        Assembly assembly;
        const result = globalClrBridge.tryLoadAssembly(CStringLiteral!"WillFail", &assembly);
        writefln("got expected error: %s", result);
    }
    //loadAssembly("System, Version=2.0.3600.0, Culture=neutral, PublicKeyToken=b77a5c561934e089");

    //globalClrBridge.funcs.TestArray([mscorlib.ptr, console.ptr, null].ptr);
    //globalClrBridge.funcs.TestVarargs(42);

    {
        const arr = globalClrBridge.arrayBuilderNewGeneric(globalClrBridge.primitiveTypes.Object, 10);
        scope(exit) globalClrBridge.release(arr);

        globalClrBridge.arrayBuilderAddGeneric(arr, globalClrBridge.primitiveTypes.Object);
        //globalClrBridge.arrayAdd(arr, 100);
    }

    const stringBuilderType = globalClrBridge.getType(globalClrBridge.mscorlib, CStringLiteral!"System.Text.StringBuilder");
    {
        enum size = 10;
        const arr = globalClrBridge.arrayBuilderNewGeneric(stringBuilderType, size);
        scope(exit) globalClrBridge.release(arr);

        static foreach (i; 0 .. size)
        {{
            const stringBuilderCtor = globalClrBridge.getConstructor(stringBuilderType, ArrayGeneric.nullObject);
            const sb = globalClrBridge.callConstructor(stringBuilderCtor, Array!(clr.PrimitiveType.Object).nullObject);
            scope(exit) globalClrBridge.release(sb);
            globalClrBridge.arrayBuilderAddGeneric(arr, sb);
        }}
    }

    // test value type array
    {
        enum size = 10;
        const arrayBuilder = globalClrBridge.arrayBuilderNewUInt32(size);
        scope(exit) globalClrBridge.release(arrayBuilder);
        foreach (i; 0 .. size)
        {
            globalClrBridge.arrayBuilderAddUInt32(arrayBuilder, i);
        }
        const array = globalClrBridge.arrayBuilderFinishUInt32(arrayBuilder);
        scope(exit) globalClrBridge.release(array);
        globalClrBridge.debugWriteObject(array);
    }

    const consoleType = globalClrBridge.getType(globalClrBridge.mscorlib, CStringLiteral!"System.Console");

    // demonstrate how to create an array manually
    {
        const builder = globalClrBridge.arrayBuilderNewGeneric(globalClrBridge.typeType, 1);
        scope (exit) globalClrBridge.release(builder);
        globalClrBridge.arrayBuilderAddGeneric(builder, globalClrBridge.primitiveTypes.String);
        const manualStringTypeArray = globalClrBridge.arrayBuilderFinishGeneric(builder);
        globalClrBridge.release(manualStringTypeArray);
    }
    const stringTypeArray = globalClrBridge.makeGenericArray(globalClrBridge.typeType, globalClrBridge.primitiveTypes.String);

    // test ambiguous method error
    {
        MethodInfo methodInfo;
        const result = globalClrBridge.tryGetMethod(consoleType, CStringLiteral!"WriteLine", ArrayGeneric.nullObject, &methodInfo);
        assert(result.type == ClrBridgeError.Type.forward);
        assert(result.data.forward.code == ClrBridgeErrorCode.ambiguousMethod);
        writefln("got expected error: %s",  result);
    }
    const consoleWriteLine = globalClrBridge.getMethod(consoleType, CStringLiteral!"WriteLine", stringTypeArray);
    globalClrBridge.funcs.CallStaticString(consoleWriteLine, CStringLiteral!"calling Console.WriteLine from D!");

    // call using object array
    {
        const msg = globalClrBridge.box!"String"(CStringLiteral!"calling Console.WriteLine from D with Object Array!");
        scope(exit) globalClrBridge.release(msg);
        const args = globalClrBridge.makeObjectArray(msg);
        scope(exit) globalClrBridge.release(args);
        globalClrBridge.funcs.CallGeneric(consoleWriteLine, clr.DotNetObject.nullObject, args, null);
    }
    {
        const consoleType3 = globalClrBridge.getClosedType!(clr.TypeSpec("mscorlib", "System.Console"));
        const listType = globalClrBridge.getClosedType!(clr.TypeSpec("mscorlib", "System.Collections.Generic.List`1"));
        const listType2 = globalClrBridge.getClosedType!(
            clr.TypeSpec("mscorlib", "System.Collections.Generic.List`1",[
                 clr.TypeSpec("mscorlib", "System.String"),
            ]));
    }

    writeln("success");
    return 0;
}

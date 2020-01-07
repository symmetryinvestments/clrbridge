import cstring; // REMOVE THIS LATER
import clrbridge.global; // REMOVE THIS LATER
import mscorlib.System.Text;

void test()
{
    // TODO: generate a method to new up a StringBuilder object instead of doing this!!!
    const stringBuilderType = globalClrBridge.getType(globalClrBridge.mscorlib, CStringLiteral!"System.Text.StringBuilder");
    const b = globalClrBridge.newObject(stringBuilderType);
}
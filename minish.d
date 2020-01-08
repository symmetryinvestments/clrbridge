#!/usr/bin/env rund
//
// A small quick and dirty script interpreter made so we can run the same
// scripts on Windows and Posix.
//
// I should find a replacement for this.
//
import core.stdc.stdlib : exit;
import std.array, std.file, std.format, std.path, std.process, std.stdio, std.string;

int main(string[] args)
{
    args = args[1..$];

    string scriptFilename = null;
    string[string] vars;

    foreach (arg; args)
    {
        const equalIndex = arg.indexOf('=');
        if (equalIndex == -1)
        {
            if (scriptFilename !is null)
            {
                writefln("ERROR: too may command-line arguments");
                return 1;
            }
            scriptFilename = arg;
        }
        else
        {
            vars[arg[0 .. equalIndex]] = arg[equalIndex+1 .. $];
        }
    }
    if (scriptFilename is null)
    {
        writefln("Usage: minish [VAR=VALUE]... SCRIPT_FILE");
        return 1;
    }
    return Interpreter(scriptFilename, 1).run(vars);
}

class Block
{
    enum Type { script, foreach_ }
    Type type;
    string[string] vars;
    union
    {
        struct LoopData
        {
            string varName;
            string[] varValues;
            Appender!(string[]) lines;
        }
        LoopData loopData = void;
    }
    this(Type type, string[string] vars = string[string].init)
    {
        this.type = type;
        this.vars = vars;
        if (type == Type.foreach_)
            loopData = LoopData.init;
    }
}

static struct VarRef
{
    string value;
    Block block;
}

struct Interpreter
{
    string scriptFilename;
    int lineNumber;
    Appender!(Block[]) blockStack;

    void errorExit(string msg)
    {
        writefln("%s(%s) ERROR: %s", scriptFilename, lineNumber, msg);
        exit(1);
    }

    VarRef tryGetVar(const(char)[] name)
    {
        foreach_reverse(block; blockStack.data)
        {
            const value = block.vars.get(cast(string)name, null);
            if (value !is null)
                return VarRef(value, block);
        }
        return VarRef(null);
    }

    string substitute(const(char)[] str)
    {
        auto result = appender!(char[])();
        for (int i = 0; i < str.length; i++)
        {
            if (str[i] == '$')
            {
                i++;
                if (i >= str.length || str[i] != '{') errorExit("$ not followed by '{'");
                const start = i + 1;
                do
                {
                    i++;
                    if (i >= str.length) errorExit("'${' not terminated with '}'");
                } while (str[i] != '}');
                const varName = str[start .. i];
                const valueRef = tryGetVar(varName);
                if (valueRef.value is null) errorExit(format("unknown variable ${%s}", varName));
                result.put(valueRef.value);
            }
            else
            {
                result.put(str[i]);
            }
        }
        return cast(string)result.data;
    }

    string[] splitHandleQuoted(string s)
    {
        const quoteIndex = s.indexOf(`"`);
        if (quoteIndex == -1)
            return s.split();
        auto nextQuoteIndex = s[quoteIndex+1 .. $].indexOf(`"`);
        if (nextQuoteIndex == -1)
            errorExit("got an open quote without a closing quote");
        nextQuoteIndex += quoteIndex + 1;
        return s[0 .. quoteIndex].split()
            ~ [s[quoteIndex+1 .. nextQuoteIndex]]
            ~ splitHandleQuoted(s[nextQuoteIndex + 1 .. $]);
    }

    int run(string[string] commandLineVars)
    {
        blockStack.put(new Block(Block.Type.script, commandLineVars));
        foreach (lineTmp; File(scriptFilename, "r").byLine)
        {
            lineNumber++;
            if (lineTmp.startsWith("#"))
                continue;
            auto block = blockStack.data[$-1];
            if (block.type == Block.Type.foreach_)
            {
                if (lineTmp != "@end")
                    block.loopData.lines.put(lineTmp.idup);
                else
                {
                    foreach (varValue; block.loopData.varValues)
                    {
                        block.vars[block.loopData.varName] = varValue;
                        foreach (loopLine; block.loopData.lines.data)
                        {
                            const result = runLine(substitute(loopLine));
                            if (result != 0) return result;
                        }
                    }
                    blockStack.shrinkTo(blockStack.data.length - 1);
                }
            }
            else
            {
                const result = runLine(substitute(lineTmp));
                if (result != 0) return result;
            }
        }
        return 0;
    }

    int runLine(string processedLine)
    {
        auto lineParts = splitHandleQuoted(processedLine);
        if (lineParts.length == 0) return 0;
        const cmd = lineParts[0];
        writefln("+ %s", escapeShellCommand(lineParts));
        stdout.flush();
        if (cmd.startsWith("@"))
            runBuiltin(cmd, lineParts[1..$]);
        else
            runProgram(lineParts);
        return 0;
    }


    void enforceArgCount(string cmd, string[] args, size_t expected)
    {
        if (args.length != expected)
            errorExit(format("the '%s' builtin requires %s arguments but got %s", cmd, expected, args.length));
    }

    void runBuiltin(string cmd, string[] args)
    {
        if (false) { }
        else if (cmd == "@echo")
        {
            string prefix = "";
            foreach (arg; args)
            {
                writef("%s%s", prefix, arg);
                prefix = " ";
            }
            writeln();
        }
        else if (cmd == "@set")
        {
            enforceArgCount(cmd, args, 2);
            blockStack.data[$-1].vars[args[0]] = args[1];
        }
        else if (cmd == "@default")
        {
            enforceArgCount(cmd, args, 2);
            auto vars = &blockStack.data[$-1].vars;
            if (args[0] !in *vars)
                (*vars)[args[0]] = args[1];
        }
        else if (cmd == "@rm")
        {
            foreach (arg; args)
            {
                if (exists(arg))
                {
                    if (isFile(arg))
                        remove(arg);
                    else
                        rmdirRecurse(arg);
                }
            }
        }
        else if (cmd == "@mkdir")
        {
            foreach (arg; args)
            {
                mkdirRecurse(arg);
            }
        }
        else if (cmd == "@mv")
        {
            enforceArgCount(cmd, args, 2);
            rename(args[0], args[1]);
        }
        else if (cmd == "@cp")
        {
            enforceArgCount(cmd, args, 2);
            copy(args[0], args[1]);
        }
        else if (cmd == "@foreach")
        {
            auto block = new Block(Block.Type.foreach_);
            if (args.length > 0)
            {
                block.loopData.varName = args[0];
                block.loopData.varValues = args[1..$];
            }
            blockStack.put(block);
        }
        else if (cmd == "@end")
        {
            errorExit("got '@end' outside of any block");
        }
        else errorExit(format("unknown builtin command '%s'", cmd));
    }

    void runProgram(string[] args)
    {
        string outputFile = null;
        if (args.length >= 2 && args[$-2] == ">")
        {
            outputFile = args[$-1];
        }
        const result = execute(args);
        if (outputFile !is null)
            std.file.write(outputFile, result.output);
        else
            writeln(result.output.stripRight);
        if (result.status != 0)
        {
            writefln("ERROR: last command exited with code %s", result.status);
            exit(1);
        }
    }
}

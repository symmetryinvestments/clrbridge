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
    string[string] varsFromCommandLine;

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
            varsFromCommandLine[arg[0 .. equalIndex]] = arg[equalIndex+1 .. $];
        }
    }
    if (scriptFilename is null)
    {
        writefln("Usage: minish [VAR=VALUE]... SCRIPT_FILE");
        return 1;
    }
    auto lines = File(scriptFilename, "r").byLineCopy.array;
    return Interpreter(scriptFilename, lines, 0).runScript(varsFromCommandLine);
}

class Scope
{
    Scope parent;
    string[string] vars;
    this(Scope parent, string[string] vars = string[string].init)
    {
        this.parent = parent;
        this.vars = vars;
    }
    string get(const(char)[] name)
    {
        const value = vars.get(cast(string)name, null);
        if (value !is null)
            return value;
        return (parent is null) ? null : parent.get(name);
    }
}

struct Interpreter
{
    string scriptFilename;
    string[] lines;
    size_t currentLineIndex;
    Scope currentScope;
    bool disabled;

    void errorExit(string msg)
    {
        writefln("%s(%s) ERROR: %s", scriptFilename, currentLineIndex + 1, msg);
        exit(1);
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
                const value = currentScope.get(varName);
                if (value is null) errorExit(format("unknown variable ${%s}", varName));
                result.put(value);
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

    int runScript(string[string] commandLineVars)
    {
        currentScope = new Scope(null, commandLineVars);
        runLines(0, false);
        if (currentLineIndex != lines.length)
            errorExit(format("too many '@end' directives (expected %s got %s)", lines.length, currentLineIndex));
        assert(currentScope.parent is null);
        return 0;
    }

    // check currentLineIndex after this returns
    void runLines(size_t startLineIndex, bool disable)
    {
        const saveDisabled = this.disabled;
        this.disabled = disable;
        scope(exit) this.disabled = saveDisabled;

        for (size_t nextLineIndex = startLineIndex; nextLineIndex < lines.length; nextLineIndex++)
        {
            this.currentLineIndex = nextLineIndex; // save the current line
            const line = lines[nextLineIndex];
            if (line.startsWith("#"))
                continue;
            auto lineParts = splitHandleQuoted(substitute(line));
            if (lineParts.length == 0) continue;
            if (lineParts[0] == "@windows")
            {
                version (Windows)
                    lineParts = lineParts[1..$];
                else
                    continue;
            }
            else if (lineParts[0] == "@notwindows")
            {
                version (Windows)
                    continue;
                else
                    lineParts = lineParts[1..$];
            }
            if (lineParts.length == 0) continue;
            string cmd = lineParts[0];
            writefln("+ %s", escapeShellCommand(lineParts));
            stdout.flush();
            if (!cmd.startsWith("@"))
            {
                if (!disabled)
                    runProgram(lineParts);
                continue;
            }
            string[] args = lineParts[1..$];
            //
            // Handle special builtins that affect control flow
            //
            if (false) { }
            else if (cmd == "@end")
            {
                enforceArgCount(cmd, args, 0);
                break;
            }
            else if (cmd == "@foreach")
            {
                nextLineIndex = foreachBuiltin(args);
            }
            else if (cmd == "@scope")
            {
                currentScope = new Scope(currentScope);
                scope (exit) currentScope = currentScope.parent;
                if (args.length == 0)
                {
                    runLines(currentLineIndex + 1, disabled);
                    nextLineIndex = currentLineIndex - 1;
                }
                else if (args[0] == "@foreach")
                    nextLineIndex = foreachBuiltin(args[1..$]);
                else
                    errorExit(format("invalid argument to @scope '%s'", args[0]));
            }
            else
            {
                if (!disabled)
                    runSimpleBuiltin(cmd, args);
            }
        }
        currentLineIndex++;
    }

    size_t foreachBuiltin(string[] args)
    {
        if (disabled || args.length == 0)
            runLines(currentLineIndex + 1, true);
        else
        {
            const varName = args[0];
            const loopStartLineIndex = currentLineIndex + 1;
            foreach (varValue; args[1..$])
            {
                currentScope.vars[varName] = varValue;
                runLines(loopStartLineIndex, false);
            }
        }
        return currentLineIndex - 1;
    }

    void enforceArgCount(string cmd, string[] args, size_t expected)
    {
        if (args.length != expected)
            errorExit(format("the '%s' builtin requires %s arguments but got %s", cmd, expected, args.length));
    }

    void runSimpleBuiltin(string cmd, string[] args)
    {
        if (false) { }
        else if (cmd == "@note")
        {
            // does nothing, just causes a line/message to get printed
        }
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
            currentScope.vars[args[0]] = args[1];
        }
        else if (cmd == "@default")
        {
            enforceArgCount(cmd, args, 2);
            if (args[0] !in currentScope.vars)
                currentScope.vars[args[0]] = args[1];
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

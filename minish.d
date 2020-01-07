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
    return Interpreter(scriptFilename, 1, vars).run();
}

struct Interpreter
{
    string scriptFilename;
    int lineNumber;
    string[string] vars;

    void errorExit(string msg)
    {
        writefln("%s(%s) ERROR: %s", scriptFilename, lineNumber, msg);
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
                const varname = str[start .. i];
                const value = vars.get(cast(string)varname, null);
                if (value is null) errorExit(format("unknown variable ${%s}", varname));
                result.put(vars[str[start..i]]);
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

    int run()
    {
        foreach (lineTmp; File(scriptFilename, "r").byLine)
        {
            lineNumber++;
            if (lineTmp.startsWith("#"))
                continue;
            const line = substitute(lineTmp);
            auto lineParts = splitHandleQuoted(line);
            if (lineParts.length == 0) continue;
            const cmd = lineParts[0];
            writefln("+ %s", escapeShellCommand(lineParts));
            stdout.flush();
            if (cmd.startsWith("@"))
                runBuiltin(cmd, lineParts[1..$]);
            else
                runProgram(lineParts);
        }
        return 0;
    }

    void runBuiltin(string cmd, string[] args)
    {
        if (false) { }
        else if (cmd == "@set")
        {
            if (args.length != 2)
                errorExit(format("@set requires 2 arguments (dest, src), but got %s", args.length));
            vars[args[0]] = args[1];
        }
        else if (cmd == "@default")
        {
            if (args.length != 2)
                errorExit(format("@default requires 2 arguments (dest, src), but got %s", args.length));
            if (args[0] !in vars)
                vars[args[0]] = args[1];
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
            if (args.length != 2)
                errorExit(format("@mv requires 2 arguments (from, to), but got %s", args.length));
            rename(args[0], args[1]);
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

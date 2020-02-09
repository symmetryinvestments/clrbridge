#!/usr/bin/env rund
//!debug
//!debugSymbols
//
// A small quick and dirty script interpreter made so we can run the same
// scripts on Windows and Posix.
//
// I should find a replacement for this.
//
import core.stdc.stdlib : exit;
import std.algorithm, std.array, std.file, std.format, std.path, std.process, std.stdio, std.string;

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
    // default directory is the directory of the script
    const scriptPath = scriptFilename.absolutePath.dirName.buildNormalizedPath;
    if (getcwd.buildNormalizedPath != scriptPath)
    {
        writefln("cd '%s'", scriptPath);
        chdir(scriptPath);
    }
    return Interpreter(scriptFilename, lines).runScript(varsFromCommandLine);
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
    Scope currentScope;

    void errorExit(size_t lineIndex, string msg)
    {
        writefln("%s(%s) ERROR: %s", scriptFilename, lineIndex + 1, msg);
        exit(1);
    }

    string substitute(size_t lineIndex, const(char)[] str)
    {
        auto result = appender!(char[])();
        for (int i = 0; i < str.length; i++)
        {
            if (str[i] == '$')
            {
                i++;
                if (i >= str.length || str[i] != '{') errorExit(lineIndex, "$ not followed by '{'");
                const start = i + 1;
                do
                {
                    i++;
                    if (i >= str.length) errorExit(lineIndex, "'${' not terminated with '}'");
                } while (str[i] != '}');
                const varName = str[start .. i];
                const value = currentScope.get(varName);
                if (value is null) errorExit(lineIndex, format("unknown variable ${%s}", varName));
                result.put(value);
            }
            else
            {
                result.put(str[i]);
            }
        }
        return cast(string)result.data;
    }

    string[] splitHandleQuoted(size_t lineIndex, string s)
    {
        const quoteIndex = s.indexOf(`"`);
        if (quoteIndex == -1)
            return s.split();
        auto nextQuoteIndex = s[quoteIndex+1 .. $].indexOf(`"`);
        if (nextQuoteIndex == -1)
            errorExit(lineIndex, "got an open quote without a closing quote");
        nextQuoteIndex += quoteIndex + 1;
        return s[0 .. quoteIndex].split()
            ~ [s[quoteIndex+1 .. nextQuoteIndex]]
            ~ splitHandleQuoted(lineIndex, s[nextQuoteIndex + 1 .. $]);
    }

    int runScript(string[string] commandLineVars)
    {
        currentScope = new Scope(null, commandLineVars);
        const endLineIndex = runLines(0, true);
        if (endLineIndex != lines.length)
            errorExit(endLineIndex, "unexpected '@end' directive");
        assert(currentScope.parent is null);
        return 0;
    }

    // returns the index of the '@end' directive if encountered, or lines.length
    size_t runLines(size_t startLineIndex, bool enabled)
    {
        uint blockLevel = 1;

        size_t lineIndex = startLineIndex;
        while (true)
        {
            if (lineIndex == lines.length)
            {
                if (blockLevel != 1)
                    errorExit((lineIndex == 0) ? 0 : lineIndex - 1, "missing '@end'");
                return lineIndex;
            }
            auto line = lines[lineIndex].stripLeft();
            if (line.startsWith("#")) {lineIndex++;continue;}
            if (line == "@end")
            {
                blockLevel--;
                if (blockLevel == 0)
                    return lineIndex;
                lineIndex++;
                continue;
            }
            if (!enabled)
            {
                if (line.startsWith("@foreach") || line.startsWith("@scope"))
                    blockLevel++;
                lineIndex++;
                continue;
            }
            if (line.startsWith("@windows"))
            {
                version (Windows) { line = line[9..$].stripLeft(); }
                else              { lineIndex++; continue; }
            }
            else if (line.startsWith("@notwindows"))
            {
                version (Windows) { lineIndex++; continue; }
                else              { line = line[12..$].stripLeft(); }
            }
            auto lineParts = splitHandleQuoted(lineIndex, substitute(lineIndex, line));
            if (lineParts.length == 0) { lineIndex++; continue; }
            string cmd = lineParts[0];
            writefln("+ %s", escapeShellCommand(lineParts));
            stdout.flush();
            if (!cmd.startsWith("@"))
            {
                runProgram(lineIndex, lineParts);
                lineIndex++;
                continue;
            }
            string[] args = lineParts[1..$];
            //
            // Handle special builtins that affect control flow
            //
            if (false) { }
            else if (cmd == "@foreach")
                lineIndex = foreachBuiltin(lineIndex, args);
            else if (cmd == "@scope")
            {
                currentScope = new Scope(currentScope);
                scope (exit) currentScope = currentScope.parent;
                const scopeLineIndex = lineIndex;
                if (args.length == 0)
                {
                    lineIndex = runLines(scopeLineIndex + 1, enabled);
                    if (lineIndex == lines.length)
                        errorExit(scopeLineIndex, "@scope without an @end");
                    lineIndex++;
                }
                else if (args[0] == "@foreach")
                    lineIndex = foreachBuiltin(lineIndex, args[1..$]);
                else
                    errorExit(scopeLineIndex, format("invalid argument to @scope '%s'", args[0]));
            }
            else
            {
                runSimpleBuiltin(lineIndex, cmd, args);
                lineIndex++;
            }
        }
    }

    size_t foreachBuiltin(size_t lineIndex, string[] args)
    {
        size_t endLineIndex;
        if (args.length <= 1)
        {
            endLineIndex = runLines(lineIndex + 1, false);
            if (endLineIndex == lines.length)
                errorExit(endLineIndex - 1, "@foreach without and @end");
        }
        else
        {
            const varName = args[0];
            foreach (varValue; args[1..$])
            {
                currentScope.vars[varName] = varValue;
                endLineIndex = runLines(lineIndex + 1, true);
                if (endLineIndex == lines.length)
                    errorExit(endLineIndex - 1, "@foreach without and @end");
            }
        }
        return endLineIndex + 1;
    }

    void enforceArgCount(size_t lineIndex, string cmd, string[] args, size_t expected)
    {
        if (args.length != expected)
            errorExit(lineIndex, format("the '%s' builtin requires %s arguments but got %s", cmd, expected, args.length));
    }

    void runSimpleBuiltin(size_t lineIndex, string cmd, string[] args)
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
            enforceArgCount(lineIndex, cmd, args, 2);
            currentScope.vars[args[0]] = args[1];
        }
        else if (cmd == "@default")
        {
            enforceArgCount(lineIndex, cmd, args, 2);
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
            enforceArgCount(lineIndex, cmd, args, 2);
            rename(args[0], args[1]);
        }
        else if (cmd == "@cp")
        {
            enforceArgCount(lineIndex, cmd, args, 2);
            copy(args[0], args[1]);
        }
        else errorExit(lineIndex, format("unknown builtin command '%s'", cmd));
    }

    void runProgram(size_t lineIndex, string[] args)
    {
        File outFile;
        if (args.length >= 2 && args[$-2] == ">")
            outFile = File(args[$-1], "w");
        else
            outFile = std.stdio.stdout;
        version (Windows)
            args[0] = workaroundWindowsNotFindingBatFiles(args[0]);

        auto process = spawnProcess(args, std.stdio.stdin, outFile);
        const result = wait(process);
        if (result != 0)
        {
            writefln("ERROR: last command exited with code %s", result);
            exit(1);
        }
    }
}

// WORKAROUND: on windows, spawnProcess doesn't seem to find .bat programs
// https://issues.dlang.org/show_bug.cgi?id=20571
string workaroundWindowsNotFindingBatFiles(string arg0)
{
    if (!arg0.canFind("/", "\\"))
    {
        const result = execute(["where", arg0]);
        if (result.status == 0)
        {
            const progFile = result.output.lineSplitter.front;
            if (progFile != arg0 && !progFile.endsWith(".exe"))
            {
                writefln("[WORKAROUND] where '%s' resolved to '%s'", arg0, progFile);
                return progFile;
            }
        }
    }
    return arg0;
}

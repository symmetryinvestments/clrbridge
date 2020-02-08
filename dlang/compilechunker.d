#!/usr/bin/env rund
// Because mscorlib is so large, some machines run out of memory when trying to compile it
// all at once.  This tool makes it easy to compile a D program/library in groups of smaller
// files.
import core.stdc.stdlib : exit;
import std.array : appender, array;
import std.string : startsWith, endsWith, replace;
import std.range : chunks;
import std.algorithm : filter, map;
import std.conv : to;
import std.format : format;
import std.path : setExtension, buildPath;
import std.file : dirEntries, SpanMode;
import std.stdio;
import std.process : spawnShell, wait, escapeShellCommand;
static import std.file;

void usage()
{
    writeln("Usage: dcomp <chunk_size> <src_dir> <obj_dir> <common-args> -- <compile-args> -- <link-args>");
}

int main(string[] args)
{
    args = args[1..$];
    if (args.length < 4)
    {
       usage();
       return 1;
    }
    auto chunkSize = args[0].to!size_t();
    auto srcDir = args[1];
    auto objDir = args[2];
    const firstDashDash = args.indexOf("--", 3);
    if (firstDashDash == -1)
    {
        writefln("Error: missing first '--' argument");
        return 1;
    }
    auto commonArgs = args[3 .. firstDashDash];
    const secondDashDash = args.indexOf("--", firstDashDash + 1);
    if (secondDashDash == -1)
    {
        writefln("Error: missing second '--' argument");
        return 1;
    }
    auto compileArgs = args[firstDashDash + 1 .. secondDashDash];
    auto linkArgs = args[secondDashDash + 1 .. $];
    return go(srcDir, objDir, chunkSize, commonArgs, compileArgs, linkArgs);
}

int go(string srcDir, string objDir, size_t chunkSize, string[] commonArgs, string[] compileArgs, string[] linkArgs)
{
    auto files = dirEntries(srcDir, SpanMode.depth)
        .filter!(e => e.name.endsWith(".d"))
        .map!(e => e.name)
        .array;
    static struct CompileGroup
    {
        string[] sources;
        string objFile;
    }
    auto groups = appender!(CompileGroup[])();
    {
        size_t fileIndex = 0;
        for (size_t nextGroupIndex = 0;; nextGroupIndex++)
        {
            const startFileIndex = fileIndex;
            size_t combinedSize = 0;
            while (fileIndex < files.length && combinedSize < chunkSize)
            {
                combinedSize += std.file.getSize(files[fileIndex]);
                fileIndex++;
            }
            if (startFileIndex == fileIndex)
                break;
            if (fileIndex > startFileIndex + 1) // remove last file if there is more than 1
                fileIndex--;
            groups.put(CompileGroup(files[startFileIndex..fileIndex],
                buildPath(objDir, ("group%s" ~ objExt).format(nextGroupIndex))));
        }
    }
    // note: we don't compile each group in parallel because that defeats the entire purpose of this
    //       tool which is to reduce the memory requirements to compile large libraries.
    foreach (group; groups.data)
    {
        run(commonArgs ~ compileArgs ~ ["-c", "-of=" ~ group.objFile] ~ group.sources);
    }
    run(commonArgs ~ linkArgs ~ groups.data.map!(e => e.objFile).array);

    return 0;
}

version (Windows)
    enum objExt = ".obj";
else
    enum objExt = ".o";

void run(string[] cmd)
{
    const shellCommand = escapeShellCommand(cmd);
    writefln("[SPAWN] %s", shellCommand);
    auto process = spawnShell(shellCommand);
    const result = wait(process);
    if (result != 0)
    {
        writefln("ERROR: last command exited with code %s", result);
        exit(1);
    }
}

ptrdiff_t indexOf(string[] strings, string s, size_t i)
{
    for (; i < strings.length; i++)
    {
        if (strings[i] == s) return i;
    }
    return -1;
}
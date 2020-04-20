
# Why convert all Clr Namespace to lowercase D modules?

This is because D modules are stored in a file tree, and on windows, path/file names ignore case.  So if you have 2 Clr Namespaces that have the same characters but different casing, then there's no straightforward way to differential the two. It's important to make the translation from a C# namespace to a D module stateless, meaning, it will always be the same regardless of what else is in the assembly.  So this means we don't want to change the translation if one namespace if there happens to be another namespace that has the same characters with a different casing.  So by default, we just normalize all Clr namespaces to lowercase so we can avoid this issue alltogether.

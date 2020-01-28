import reggae;
alias app = executable!(
    ExeName("example"),
    Sources!(cast(string[])null, Files("../example.d")),
    Flags("-g -debug"),
    ImportPaths(["src_hresult",
        "src_cstring",
        "../out/DerelictUtil/source",
        "src_coreclr",
        "src_clr",
        "src_clrbridge",
        "../out/dlibs/src",
    ])
);
mixin build!app;

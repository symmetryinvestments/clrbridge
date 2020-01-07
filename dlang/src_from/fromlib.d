module fromlib;

template from(string moduleName)
{
    mixin("import from = " ~ moduleName ~ ";");
}

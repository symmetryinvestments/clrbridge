import cstring;
import clr : Decimal;
import clrbridge.global;
import properties;

void test()
{
    assert(0 == properties.Static.UInt32Value);
    properties.Static.UInt32Value = 1234;
    assert(1234 == properties.Static.UInt32Value);

    {
        auto dur = properties.Duration.FromSeconds(3600);
        assert(dur.Seconds == 3600);
        assert(dur.Hours == 1);
        dur.Hours = 2;
        assert(dur.Seconds == 7200);
        assert(dur.Hours == 2);
    }
}

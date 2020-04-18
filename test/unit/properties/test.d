import cstring;
import clr : Decimal;
import clrbridge.global;
import properties;

void test()
{
    assert(0 == properties.Static.get_UInt32Value());
    properties.Static.set_UInt32Value(1234);
    assert(1234 == properties.Static.get_UInt32Value());

    {
        auto dur = properties.Duration.FromSeconds(3600);
        assert(dur.get_Seconds() == 3600);
        assert(dur.get_Hours() == 1);
        dur.set_Hours(2);
        assert(dur.get_Seconds() == 7200);
        assert(dur.get_Hours() == 2);
    }
}

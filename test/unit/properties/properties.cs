using System;

public static class Static
{
    static UInt32 uint32Value = 0;
    public static UInt32 UInt32Value
    {
        get { return uint32Value; }
        set { uint32Value = value; }
    }
}

public class Duration
{
    private UInt32 seconds;
    public static Duration FromSeconds(UInt32 seconds)
    {
        return new Duration(seconds);
    }
    private Duration(UInt32 seconds)
    {
        this.seconds = seconds;
    }

    public UInt32 Seconds
    {
        get { return seconds; }
        set { seconds = value; }
    }
    public UInt32 Hours
    {
        get { return seconds / 3600; }
        set { seconds = value * 3600; }
    }
}

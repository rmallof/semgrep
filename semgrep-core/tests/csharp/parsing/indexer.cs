using System;

class HelloWorldIndexer
{
    public static void Main()
    {
        var instance = new HelloWorldIndexer();
        Console.WriteLine(instance[0]);
        Console.WriteLine(instance[1]);
    }

    private string this[int i]
    {
        get
        {
            switch (i)
            {
                case 0: return "hello";
                case 1: return "world";
                default: throw new IndexOutOfRangeException();
            }
        }
        set => throw new NotImplementedException();
    }
}
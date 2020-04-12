namespace LayoutingTester
{
    public class TestLayoutInput
    {
        public string Name { get; }
        public string Json { get; }

        public TestLayoutInput(string name, string json)
        {
            Name = name;
            Json = json;
        }
    }
}
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices.ComTypes;

namespace LayoutingTester
{
    public static class TestInputProvider
    {
        public static IEnumerable<TestLayoutInput> All()
        {
            var files = Directory.EnumerateFiles("../../../../TestInputs").ToList();

            return files.Select(fileName =>
                new TestLayoutInput(Path.GetFileNameWithoutExtension(fileName), File.ReadAllText(fileName)));
        }
    }
}
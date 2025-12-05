using System.Collections.Generic;

namespace LayoutingTester
{
    public class LayoutResult
    {
        public Dictionary<float, TestLayoutColumn> Columns { get; set; } = new();

        public BoundingBox ExtractorBoundingBox { get; set; }
        public BoundingBox BeaconBoundingBox { get; set; }
    }

}

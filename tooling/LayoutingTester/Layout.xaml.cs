using System.Windows;
using System.Windows.Controls;

namespace LayoutingTester
{
    /// <summary>
    /// Interaction logic for Layout.xaml
    /// </summary>
    public partial class Layout : UserControl
    {
        public Layout()
        {
            InitializeComponent();
        }

        public static readonly DependencyProperty PropertyTypeProperty = DependencyProperty.Register(
            "TestLayout", typeof(TestLayout), typeof(Layout));
        
        public TestLayout TestLayout
        {
            get { return (TestLayout) GetValue(PropertyTypeProperty); }
            set { SetValue(PropertyTypeProperty, value); }
        }
    }
}

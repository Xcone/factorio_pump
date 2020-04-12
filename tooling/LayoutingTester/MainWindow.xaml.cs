using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;

namespace LayoutingTester
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        public ObservableCollection<TestLayoutInput> TestItems { get; } = new ObservableCollection<TestLayoutInput>();

        public MainWindow()
        {
            InitializeComponent();

            TestItems.Add(new TestLayoutInput(nameof(Properties.Resources.Oilfield1), Properties.Resources.Oilfield1));
            TestItems.Add(new TestLayoutInput(nameof(Properties.Resources.OilfieldWithFactories), Properties.Resources.OilfieldWithFactories));

            TestLayouts.ItemsSource = TestItems;
        }

        private void TestLayouts_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            this.TestLayoutRunner.TestLayoutInput = TestLayouts.SelectedItem as TestLayoutInput;
        }
    }
}

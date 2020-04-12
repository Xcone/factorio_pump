using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace LayoutingTester
{
    /// <summary>
    /// Interaction logic for TestLayoutRunner.xaml
    /// </summary>
    public partial class TestLayoutRunner : UserControl
    {
        private FileSystemWatcher watcher;

        public static readonly DependencyProperty TestLayoutInputDependencyProperty = DependencyProperty.Register(
            "TestLayoutInput", typeof(TestLayoutInput), typeof(TestLayoutRunner));

        public TestLayoutInput TestLayoutInput
        {
            get { return (TestLayoutInput)GetValue(TestLayoutInputDependencyProperty); }
            set
            {
                SetValue(TestLayoutInputDependencyProperty, value);
                Refresh();
            }
        }

        public TestLayoutRunner()
        {
            InitializeComponent();

            watcher = new FileSystemWatcher("../../../../../mod/");
            watcher.Filter = "planner.lua";
            watcher.IncludeSubdirectories = false;
            watcher.Changed += Watcher_Changed;
            watcher.EnableRaisingEvents = true;
        }

        private void Watcher_Changed(object sender, FileSystemEventArgs e)
        {
            Refresh();
        }

        private void Refresh()
        {
            string json = null;
            Dispatcher.Invoke(() => json = TestLayoutInput.Json);

            if (json != null)
            {
                var testLayout = new TestLayout(json);
                Dispatcher.Invoke(() => TestLayoutResultVisualizer.TestLayout = testLayout);
            }
        }
    }
}

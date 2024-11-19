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

        public static readonly DependencyProperty ProModeDependencyProperty = DependencyProperty.Register(
            "ProMode", typeof(bool), typeof(TestLayoutRunner));

        public TestLayoutInput TestLayoutInput
        {
            get { return (TestLayoutInput)GetValue(TestLayoutInputDependencyProperty); }
            set
            {
                SetValue(TestLayoutInputDependencyProperty, value);
                Refresh();
            }
        }

        public bool ProMode { 
            get { return (bool)GetValue(ProModeDependencyProperty); }
            set
            {
                SetValue(ProModeDependencyProperty, value);
                Refresh();
            }
        }

        public TestLayoutRunner()
        {
            InitializeComponent();

            watcher = new FileSystemWatcher("../../../../../mod/");
            watcher.Filter = "*.lua";
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
            Dispatcher.Invoke(() => TestLayoutResultVisualizer.TestLayout = null);

            string json = null;
            var proMode = false;
            Dispatcher.Invoke(() =>
            {
                json = TestLayoutInput?.Json;
                proMode = ProMode;
            });
            

            if (json != null)
            {
                var testLayout = new TestLayout(json, proMode);
                Dispatcher.Invoke(() => TestLayoutResultVisualizer.TestLayout = testLayout);
            }
        }
    }
}

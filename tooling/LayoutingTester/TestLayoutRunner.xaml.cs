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
        public static readonly DependencyProperty PlanBeaconsProperty = DependencyProperty.Register(
            "PlanBeacons", typeof(bool), typeof(TestLayoutRunner), new PropertyMetadata(true));

        public static readonly DependencyProperty PlanHeatPipesProperty = DependencyProperty.Register(
            "PlanHeatPipes", typeof(bool), typeof(TestLayoutRunner), new PropertyMetadata(true));

        public static readonly DependencyProperty PlanPowerPolesProperty = DependencyProperty.Register(
            "PlanPowerPoles", typeof(bool), typeof(TestLayoutRunner), new PropertyMetadata(true));

        public bool PlanBeacons
        {
            get => (bool)GetValue(PlanBeaconsProperty);
            set => SetValue(PlanBeaconsProperty, value);
        }

        public bool PlanHeatPipes
        {
            get => (bool)GetValue(PlanHeatPipesProperty);
            set => SetValue(PlanHeatPipesProperty, value);
        }

        public bool PlanPowerPoles
        {
            get => (bool)GetValue(PlanPowerPolesProperty);
            set => SetValue(PlanPowerPolesProperty, value);
        }

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
            Dispatcher.Invoke(() =>
            {
                json = TestLayoutInput?.Json;
            });
            

            if (json != null)
            {
                // Read dependency properties on the UI thread to avoid cross-thread access
                bool planBeacons = true, planHeatPipes = true, planPowerPoles = true;
                Dispatcher.Invoke(() =>
                {
                    planBeacons = PlanBeacons;
                    planHeatPipes = PlanHeatPipes;
                    planPowerPoles = PlanPowerPoles;
                });

                var testLayout = new TestLayout(json, planBeacons, planHeatPipes, planPowerPoles);
                Dispatcher.Invoke(() => TestLayoutResultVisualizer.TestLayout = testLayout);
            }
        }
    }
}

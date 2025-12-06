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

        public static readonly DependencyProperty MaxBeaconsPerExtractorProperty = DependencyProperty.Register(
            "MaxBeaconsPerExtractor", typeof(int), typeof(TestLayoutRunner), new PropertyMetadata(4, OnOptionChanged));

        public static readonly DependencyProperty MinExtractorsPerBeaconProperty = DependencyProperty.Register(
            "MinExtractorsPerBeacon", typeof(int), typeof(TestLayoutRunner), new PropertyMetadata(1, OnOptionChanged));

        public static readonly DependencyProperty PreferredBeaconsPerExtractorProperty = DependencyProperty.Register(
            "PreferredBeaconsPerExtractor", typeof(int), typeof(TestLayoutRunner), new PropertyMetadata(1, OnOptionChanged));

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

        public int MaxBeaconsPerExtractor
        {
            get => (int)GetValue(MaxBeaconsPerExtractorProperty);
            set => SetValue(MaxBeaconsPerExtractorProperty, value);
        }

        public int MinExtractorsPerBeacon
        {
            get => (int)GetValue(MinExtractorsPerBeaconProperty);
            set => SetValue(MinExtractorsPerBeaconProperty, value);
        }

        public int PreferredBeaconsPerExtractor
        {
            get => (int)GetValue(PreferredBeaconsPerExtractorProperty);
            set => SetValue(PreferredBeaconsPerExtractorProperty, value);
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

        private static void OnOptionChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is TestLayoutRunner runner)
            {
                // Ensure refresh runs on UI thread
                runner.Dispatcher.Invoke(() => runner.Refresh());
            }
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
                int maxBeacons = 4, minExtractors = 1, preferredBeacons = 1;
                Dispatcher.Invoke(() =>
                {
                    planBeacons = PlanBeacons;
                    planHeatPipes = PlanHeatPipes;
                    planPowerPoles = PlanPowerPoles;
                    maxBeacons = MaxBeaconsPerExtractor;
                    minExtractors = MinExtractorsPerBeacon;
                    preferredBeacons = PreferredBeaconsPerExtractor;
                });

                var testLayout = new TestLayout(json, planBeacons, planHeatPipes, planPowerPoles, maxBeacons, minExtractors, preferredBeacons);
                Dispatcher.Invoke(() => TestLayoutResultVisualizer.TestLayout = testLayout);
            }
        }
    }
}

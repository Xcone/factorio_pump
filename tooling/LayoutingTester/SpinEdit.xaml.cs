using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace LayoutingTester
{
    public partial class SpinEdit : UserControl
    {
        private static readonly Regex _nonDigitRegex = new Regex("[^0-9]+", RegexOptions.Compiled);

        public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
            "Value", typeof(int), typeof(SpinEdit), new PropertyMetadata(0, OnValueChanged));

        public static readonly DependencyProperty MinimumProperty = DependencyProperty.Register(
            "Minimum", typeof(int), typeof(SpinEdit), new PropertyMetadata(0));

        public static readonly DependencyProperty MaximumProperty = DependencyProperty.Register(
            "Maximum", typeof(int), typeof(SpinEdit), new PropertyMetadata(int.MaxValue));

        public static readonly DependencyProperty StepProperty = DependencyProperty.Register(
            "Step", typeof(int), typeof(SpinEdit), new PropertyMetadata(1));

        public int Value
        {
            get => (int)GetValue(ValueProperty);
            set => SetValue(ValueProperty, value);
        }

        public int Minimum
        {
            get => (int)GetValue(MinimumProperty);
            set => SetValue(MinimumProperty, value);
        }

        public int Maximum
        {
            get => (int)GetValue(MaximumProperty);
            set => SetValue(MaximumProperty, value);
        }

        public int Step
        {
            get => (int)GetValue(StepProperty);
            set => SetValue(StepProperty, value);
        }

        public SpinEdit()
        {
            InitializeComponent();
            PART_TextBox.PreviewTextInput += PART_TextBox_PreviewTextInput;
            DataObject.AddPastingHandler(PART_TextBox, PART_TextBox_Pasting);
            PART_TextBox.TextChanged += PART_TextBox_TextChanged;
            Loaded += (s, e) => PART_TextBox.Text = Value.ToString();
        }

        private static void OnValueChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is SpinEdit se)
            {
                var v = (int)e.NewValue;
                if (v < se.Minimum) se.Value = se.Minimum;
                else if (v > se.Maximum) se.Value = se.Maximum;
                else se.PART_TextBox.Text = v.ToString();
            }
        }

        private void PART_TextBox_PreviewTextInput(object sender, TextCompositionEventArgs e)
        {
            e.Handled = _nonDigitRegex.IsMatch(e.Text);
        }

        private void PART_TextBox_Pasting(object sender, DataObjectPastingEventArgs e)
        {
            if (e.DataObject.GetDataPresent(typeof(string)))
            {
                var text = (string)e.DataObject.GetData(typeof(string));
                if (_nonDigitRegex.IsMatch(text))
                    e.CancelCommand();
            }
            else
            {
                e.CancelCommand();
            }
        }

        private void PART_TextBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (int.TryParse(PART_TextBox.Text, out var v))
            {
                if (v < Minimum) v = Minimum;
                if (v > Maximum) v = Maximum;
                if (v != Value) Value = v;
            }
        }

        private void Increase_Click(object sender, RoutedEventArgs e)
        {
            var nv = Value + Step;
            if (nv > Maximum) nv = Maximum;
            Value = nv;
        }

        private void Decrease_Click(object sender, RoutedEventArgs e)
        {
            var nv = Value - Step;
            if (nv < Minimum) nv = Minimum;
            Value = nv;
        }
    }
}

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace LayoutingTester
{
    public class TestLayoutGridVisual : FrameworkElement
    {
        public Dictionary<float, TestLayoutColumn> Columns
        {
            get { return (Dictionary<float, TestLayoutColumn>)GetValue(ColumnsProperty); }
            set { SetValue(ColumnsProperty, value); }
        }
        public static readonly DependencyProperty ColumnsProperty =
            DependencyProperty.Register("Columns", typeof(Dictionary<float, TestLayoutColumn>), typeof(TestLayoutGridVisual),
                new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

        private Popup _cellPopup = new Popup();
        private TextBlock _popupText = new TextBlock { Background = Brushes.LightYellow, Foreground = Brushes.Black, Padding = new Thickness(4), FontSize = 14 };

        public TestLayoutGridVisual()
        {
            _cellPopup.AllowsTransparency = true;
            _cellPopup.Placement = PlacementMode.Absolute;
            _cellPopup.StaysOpen = true;
            _cellPopup.Child = _popupText;
            this.MouseMove += TestLayoutGridVisual_MouseMove;
            this.MouseLeave += TestLayoutGridVisual_MouseLeave;
        }

        private void TestLayoutGridVisual_MouseLeave(object sender, MouseEventArgs e)
        {
            _cellPopup.IsOpen = false;
        }

        private void TestLayoutGridVisual_MouseMove(object sender, MouseEventArgs e)
        {
            if (Columns == null || Columns.Count == 0)
            {
                _cellPopup.IsOpen = false;
                return;
            }
            var xKeys = Columns.Keys.OrderBy(x => x).ToList();
            var yKeys = Columns.Values.SelectMany(col => col.Cells.Keys).Distinct().OrderBy(y => y).ToList();
            int columnCount = xKeys.Count;
            int rowCount = yKeys.Count;
            double cellSize = Math.Min(ActualWidth / columnCount, ActualHeight / rowCount);
            double gridWidth = cellSize * columnCount;
            double gridHeight = cellSize * rowCount;
            double offsetX = (ActualWidth - gridWidth) / 2;
            double offsetY = (ActualHeight - gridHeight) / 2;
            Point mouse = e.GetPosition(this);
            int colIdx = (int)((mouse.X - offsetX) / cellSize);
            int rowIdx = (int)((mouse.Y - offsetY) / cellSize);
            if (colIdx >= 0 && colIdx < columnCount && rowIdx >= 0 && rowIdx < rowCount)
            {
                var col = Columns[xKeys[colIdx]];
                var y = yKeys[rowIdx];
                TestLayoutCell cell = null;
                col.Cells.TryGetValue(y, out cell);
                if (cell != null && !string.IsNullOrEmpty(cell.Content))
                {
                    _popupText.Text = $"World: X={cell.X}, Y={cell.Y}";
                    var screenPos = PointToScreen(mouse);
                    _cellPopup.HorizontalOffset = screenPos.X + 16;
                    _cellPopup.VerticalOffset = screenPos.Y + 16;
                    if (!_cellPopup.IsOpen)
                        _cellPopup.IsOpen = true;
                    return;
                }
            }
            _cellPopup.IsOpen = false;
        }

        private SolidColorBrush Brighten(SolidColorBrush brush, float step)
        {
            byte b = 0;

            step = step - 1;
            if (step > 0)
                b = 64;

            b = (byte)(b + Math.Min(64, (step * 2)));

            var newColor = Color.Add(brush.Color, Color.FromArgb(b, b, b, b));
            return new SolidColorBrush(newColor);
        }

        protected override void OnRender(DrawingContext dc)
        {
            base.OnRender(dc);
            if (Columns == null || Columns.Count == 0)
                return;

            // Sort X and Y keys
            var xKeys = Columns.Keys.OrderBy(x => x).ToList();
            var yKeys = Columns.Values.SelectMany(col => col.Cells.Keys).Distinct().OrderBy(y => y).ToList();
            int columnCount = xKeys.Count;
            int rowCount = yKeys.Count;

            // Calculate square cell size and center the grid
            var cellSize = Math.Min(ActualWidth / columnCount, ActualHeight / rowCount);
            double gridWidth = cellSize * columnCount;
            double gridHeight = cellSize * rowCount;
            double offsetX = (ActualWidth - gridWidth) / 2;
            double offsetY = (ActualHeight - gridHeight) / 2;

            for (int colIdx = 0; colIdx < columnCount; colIdx++)
            {
                var col = Columns[xKeys[colIdx]];
                for (int rowIdx = 0; rowIdx < rowCount; rowIdx++)
                {
                    var y = yKeys[rowIdx];
                    TestLayoutCell cell = null;
                    col.Cells.TryGetValue(y, out cell);
                    if (cell == null)
                        cell = new TestLayoutCell(xKeys[colIdx].ToString(CultureInfo.InvariantCulture), y.ToString(CultureInfo.InvariantCulture), "");

                    double x = offsetX + colIdx * cellSize;
                    double yPos = offsetY + rowIdx * cellSize;

                    // Choose color based on Content (simplified, expand as needed)
                    Brush background = Brushes.Blue;
                    if (cell.Content == "can-build") background = Brushes.Green;
                    else if (cell.Content == "oil-well") background = Brushes.DarkGray;
                    else if (cell.Content == "can-not-build") background = Brushes.DarkRed;
                    else if (cell.Content == "reserved-for-pump") background = Brushes.DarkOrange;
                    else if (cell.Content == "power_pole") background = (Brush)new BrushConverter().ConvertFrom("#FF5151B3");
                    else if (cell.Content == "heat-pipe") background = Brighten(Brushes.Red, int.Parse(cell.EntityToConstruct));
                    else if (cell.Content == "pipe") background = Brushes.Lavender;
                    else if (cell.Content == "beacon") background = Brushes.Magenta;

                    var rect = new Rect(x, yPos, cellSize, cellSize);
                    dc.DrawRectangle(background, new Pen(Brushes.White, 0.5), rect);

                    // Draw text (EntityToConstruct)
                    if (!string.IsNullOrEmpty(cell.EntityToConstruct))
                    {
                        double fontSize = Math.Max(6, Math.Min(24, cellSize * 0.6));
                        var formattedText = new FormattedText(
                            cell.EntityToConstruct,
                            CultureInfo.InvariantCulture,
                            FlowDirection.LeftToRight,
                            new Typeface("Segoe UI"),
                            fontSize,
                            Brushes.Black,
                            VisualTreeHelper.GetDpi(this).PixelsPerDip);

                        dc.DrawText(formattedText, new Point(x + cellSize / 2 - formattedText.Width / 2, yPos + cellSize / 2 - formattedText.Height / 2));
                    }
                }
            }
        }
    }
}
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
        public LayoutResult LayoutResult
        {
            get { return (LayoutResult)GetValue(LayoutResultProperty); }
            set { SetValue(LayoutResultProperty, value); }
        }

        public static readonly DependencyProperty LayoutResultProperty =
            DependencyProperty.Register("LayoutResult", typeof(LayoutResult), typeof(TestLayoutGridVisual),
                new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

        private Popup _cellPopup = new Popup();
        private TextBlock _popupText = new TextBlock { Background = Brushes.LightYellow, Foreground = Brushes.Black, Padding = new Thickness(4), FontSize = 14 };

        private record GridInfo(List<float> XKeys, List<float> YKeys, int ColumnCount, int RowCount, double CellSize, double GridWidth, double GridHeight, double OffsetX, double OffsetY, double MinX, double MinY);

        private record LargeCell(Rect WorldRect, TestLayoutCell Cell);

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
            var g = ComputeGridInfo();
            if (g == null)
            {
                _cellPopup.IsOpen = false;
                return;
            }

            Point mouse = e.GetPosition(this);
            int colIdx = (int)((mouse.X - g.OffsetX) / g.CellSize);
            int rowIdx = (int)((mouse.Y - g.OffsetY) / g.CellSize);
            if (colIdx >= 0 && colIdx < g.ColumnCount && rowIdx >= 0 && rowIdx < g.RowCount)
            {
                var cell = GetCellAt(colIdx, rowIdx, g);

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

        private GridInfo? ComputeGridInfo()
        {
            if (LayoutResult == null || LayoutResult.Columns == null || LayoutResult.Columns.Count == 0)
                return null;

            var xKeys = LayoutResult.Columns.Keys.OrderBy(x => x).ToList();
            var yKeys = LayoutResult.Columns.Values.SelectMany(col => col.Cells.Keys).Distinct().OrderBy(y => y).ToList();
            int columnCount = xKeys.Count;
            int rowCount = yKeys.Count;
            if (columnCount == 0 || rowCount == 0) return null;
            double cellSize = Math.Min(ActualWidth / columnCount, ActualHeight / rowCount);
            double gridWidth = cellSize * columnCount;
            double gridHeight = cellSize * rowCount;
            double offsetX = (ActualWidth - gridWidth) / 2;
            double offsetY = (ActualHeight - gridHeight) / 2;
            double minX = xKeys.Min();
            double minY = yKeys.Min();

            return new GridInfo(xKeys, yKeys, columnCount, rowCount, cellSize, gridWidth, gridHeight, offsetX, offsetY, minX, minY);
        }

        private TestLayoutCell GetCellAt(int colIdx, int rowIdx, GridInfo g)
        {
            var col = LayoutResult.Columns[g.XKeys[colIdx]];
            var y = g.YKeys[rowIdx];
            col.Cells.TryGetValue(y, out var cell);

            return cell;
        }

        private void DrawCell(DrawingContext dc, TestLayoutCell cell, Rect worldRect, GridInfo g)
        {
            // convert world-space rect to pixel rect using GridInfo.
            // Align top-left world coordinate (MinX/MinY) to the render area's top-left (OffsetX/OffsetY).
            var pixelRect = new Rect(
                g.OffsetX + (worldRect.X - g.MinX) * g.CellSize,
                g.OffsetY + (worldRect.Y - g.MinY) * g.CellSize,
                worldRect.Width * g.CellSize,
                worldRect.Height * g.CellSize);

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
            else if (cell.Content == "extractor") background = Brushes.DarkCyan;

            dc.DrawRectangle(background, new Pen(Brushes.White, 0.5), pixelRect);

            if (!string.IsNullOrEmpty(cell.EntityToConstruct))
            {
                DrawCenteredText(dc, cell.EntityToConstruct, pixelRect.X, pixelRect.Y, pixelRect.Width, pixelRect.Height);
            }
        }

        private void DrawCenteredText(DrawingContext dc, string text, double x, double y, double width, double height)
        {
            double fontSize = Math.Max(6, Math.Min(24, Math.Min(width, height) * 0.6));
            var formattedText = new FormattedText(
                text,
                CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI"),
                fontSize,
                Brushes.Black,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);

            dc.DrawText(formattedText, new Point(x + width / 2 - formattedText.Width / 2, y + height / 2 - formattedText.Height / 2));
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
            if (LayoutResult == null || LayoutResult.Columns == null || LayoutResult.Columns.Count == 0)
                return;

            // Sort X and Y keys
            var xKeys = LayoutResult.Columns.Keys.OrderBy(x => x).ToList();
            var yKeys = LayoutResult.Columns.Values.SelectMany(col => col.Cells.Keys).Distinct().OrderBy(y => y).ToList();
            int columnCount = xKeys.Count;
            int rowCount = yKeys.Count;

            // Calculate square cell size and center the grid
            var cellSize = Math.Min(ActualWidth / columnCount, ActualHeight / rowCount);
            double gridWidth = cellSize * columnCount;
            double gridHeight = cellSize * rowCount;
            double offsetX = (ActualWidth - gridWidth) / 2;
            double offsetY = (ActualHeight - gridHeight) / 2;

            var g = ComputeGridInfo();
            if (g == null) return;

            // First pass: draw all 1x1 cells (skip beacons and extractors) and collect large objects
            var largeObjects = new List<LargeCell>();
            foreach (var (worldX, row) in LayoutResult.Columns)
            {
                foreach (var (worldY, cell) in row.Cells)
                {
                    var worldRect = new Rect(worldX, worldY, 1, 1);

                    if (cell.Content == "beacon" || cell.Content == "extractor")
                    {
                        var box = cell.Content == "beacon" ? LayoutResult.BeaconBoundingBox : LayoutResult.ExtractorBoundingBox;
                        worldRect.X += box.LeftTop.X;
                        worldRect.Y += box.LeftTop.Y;
                        worldRect.Width += Math.Abs(box.LeftTop.X) + Math.Abs(box.RightBottom.X);
                        worldRect.Height += Math.Abs(box.LeftTop.Y) + Math.Abs(box.RightBottom.Y);

                        largeObjects.Add(new LargeCell(worldRect, cell));
                        continue;
                    }

                    // pass world-space rect to DrawCell; it will convert to pixels using MinX/MinY
                    DrawCell(dc, cell, worldRect, g);
                }
            }

            // Second pass: draw collected large objects
            foreach (var lo in largeObjects)
            {
                DrawCell(dc, lo.Cell, lo.WorldRect, g);
            }
        }
    }
}
using CoreGraphics;
using Foundation;
using System.Text.Json;
using UIKit;

namespace Pencil.Maui;

public sealed class PencilCanvas : UIView
{
    private sealed record Stroke(CGPoint Start, CGPoint End, nfloat Width);
    private readonly List<Stroke> strokes = [];
    private readonly List<object> observations = [];
    private readonly UILabel title = new();
    private readonly UILabel status = new();
    private CGPoint? lastPoint;
    private int pencilSamples;
    private int fingerSamples;
    private int hoverSamples;

    public PencilCanvas()
    {
        AccessibilityIdentifier = "pencil-canvas";
        BackgroundColor = UIColor.FromRGB(10, 18, 31);
        MultipleTouchEnabled = true;
        title.Text = "PENCIL / MAUI / PRECOMPILED";
        title.TextColor = UIColor.White;
        title.Font = UIFont.MonospacedDigitSystemFontOfSize(24, UIFontWeight.Bold);
        status.TextColor = UIColor.SystemMint;
        status.Font = UIFont.MonospacedDigitSystemFontOfSize(16, UIFontWeight.Medium);
        status.Lines = 0;
        status.AccessibilityIdentifier = "pencil-received-status";
        AddSubview(title);
        AddSubview(status);
        var hover = new UIHoverGestureRecognizer(Hovered)
        {
            Name = "pencil-hover",
            AllowedTouchTypes = [NSNumber.FromInt32((int)UITouchType.Stylus)]
        };
        AddGestureRecognizer(hover);
        UpdateStatus("Waiting for input");
    }

    public override void LayoutSubviews()
    {
        base.LayoutSubviews();
        title.Frame = new CGRect(35, 45, Bounds.Width - 70, 45);
        status.Frame = new CGRect(35, 95, Bounds.Width - 70, 125);
    }

    public override void Draw(CGRect rect)
    {
        base.Draw(rect);
        UIColor.SystemMint.SetStroke();
        foreach (var stroke in strokes)
        {
            using var path = new UIBezierPath { LineWidth = stroke.Width, LineCapStyle = CGLineCap.Round };
            path.MoveTo(stroke.Start);
            path.AddLineTo(stroke.End);
            path.Stroke();
        }
    }

    public override void TouchesBegan(NSSet touches, UIEvent? evt) => Receive(touches, evt, "down");
    public override void TouchesMoved(NSSet touches, UIEvent? evt) => Receive(touches, evt, "move");
    public override void TouchesEnded(NSSet touches, UIEvent? evt) { Receive(touches, evt, "up"); lastPoint = null; }
    public override void TouchesCancelled(NSSet touches, UIEvent? evt) { Receive(touches, evt, "cancel"); lastPoint = null; }

    private void Receive(NSSet touches, UIEvent? evt, string phase)
    {
        foreach (var touch in touches.ToArray<UITouch>())
        foreach (var sample in evt?.GetCoalescedTouches(touch) ?? [touch])
        {
            var point = sample.LocationInView(this);
            var pencil = sample.Type == UITouchType.Stylus;
            if (pencil) pencilSamples++; else fingerSamples++;
            var pressure = sample.MaximumPossibleForce > 0 ? sample.Force / sample.MaximumPossibleForce : 0;
            observations.Add(new
            {
                phase, tool = pencil ? "stylus" : "finger", x = (double)point.X, y = (double)point.Y,
                pressure = (double)pressure, altitude = (double)sample.AltitudeAngle,
                azimuth = (double)sample.GetAzimuthAngle(this), roll = (double)sample.RollAngle
            });
            strokes.Add(new Stroke(lastPoint ?? point,
                new CGPoint(point.X + (lastPoint is null ? .1 : 0), point.Y), 2 + pressure * 12));
            lastPoint = point;
            UpdateStatus($"{(pencil ? "PENCIL" : "FINGER")} pressure {pressure:F3}, tilt {sample.AltitudeAngle:F3}\nazimuth {sample.GetAzimuthAngle(this):F3}, roll {sample.RollAngle:F3}");
        }
        SetNeedsDisplay();
        Persist();
    }

    private void Hovered(UIHoverGestureRecognizer recognizer)
    {
        hoverSamples++;
        observations.Add(new { phase = "hover", tool = "stylus", distance = (double)recognizer.ZOffset, roll = (double)recognizer.RollAngle });
        UpdateStatus($"HOVER distance {recognizer.ZOffset:F3}, roll {recognizer.RollAngle:F3}");
        Persist();
    }

    private void UpdateStatus(string detail)
        => status.Text = $"Opt-in: {MauiProgram.PenOptIn} | Release native framework\nPencil: {pencilSamples} Finger: {fingerSamples} Hover: {hoverSamples}\n{detail}";

    private void Persist() => File.WriteAllText(Path.Combine(FileSystem.AppDataDirectory, "pencil-observations.json"), JsonSerializer.Serialize(observations));
}

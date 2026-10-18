namespace Ansight.ScreenshotGeometryHarness;

public sealed class GeometryPage : ContentPage
{
    internal static GeometryPage? Current { get; private set; }
    internal Label Clock { get; } = new() { AutomationId = "geometry.clock", Text = "12:00:00", FontSize = 32,
        FontFamily = "monospace", TextColor = Colors.White, BackgroundColor = Color.FromArgb("#243047"),
        HeightRequest = 64, HorizontalTextAlignment = TextAlignment.Center, VerticalTextAlignment = TextAlignment.Center };
    private readonly Label connection = new() { AutomationId = "geometry.connection", Text = "Waiting for host", TextColor = Colors.DarkSlateGray };
    private readonly BoxView changedCube = new() { AutomationId = "geometry.cube", Color = Colors.MediumPurple, WidthRequest = 72, HeightRequest = 72 };

    public GeometryPage()
    {
        Current = this;
        Title = "Screenshot geometry"; AutomationId = "geometry.root"; BackgroundColor = Colors.White;
        var advance = new Button { AutomationId = "geometry.advance", Text = "Advance app clock" };
        var change = new Button { AutomationId = "geometry.change", Text = "Change purple cube" };
        var reset = new Button { AutomationId = "geometry.reset", Text = "Reset scene" };
        advance.Clicked += (_, _) => Clock.Text = "12:00:01";
        change.Clicked += (_, _) => changedCube.Color = Colors.OrangeRed;
        reset.Clicked += (_, _) => { Clock.Text = "12:00:00"; changedCube.Color = Colors.MediumPurple; };
        Content = new VerticalStackLayout { Padding = 20, Spacing = 16, Children = {
            new Label { Text = "Screenshot geometry", FontSize = 26, FontAttributes = FontAttributes.Bold, TextColor = Colors.Black },
            connection, Clock,
            new Label { Text = "The clock below the system bars belongs to this app. Only its explicit mask may hide it.", TextColor = Colors.Black },
            new HorizontalStackLayout { Spacing = 18, HorizontalOptions = LayoutOptions.Center, Children = {
                changedCube, new BoxView { Color = Colors.MediumPurple, WidthRequest = 72, HeightRequest = 72 },
                new BoxView { Color = Colors.SteelBlue, WidthRequest = 72, HeightRequest = 72 } } },
            advance, change, reset } };
    }
    protected override void OnAppearing() { base.OnAppearing(); Runtime.HostConnection.StatusChanged += ConnectionChanged; RefreshConnection(); }
    protected override void OnDisappearing() { Runtime.HostConnection.StatusChanged -= ConnectionChanged; base.OnDisappearing(); }
    private void ConnectionChanged(object? sender, HostConnectionChangedEventArgs args) => MainThread.BeginInvokeOnMainThread(RefreshConnection);
    private void RefreshConnection() => connection.Text = Runtime.HostConnection.IsConnected ? "Connected" : "Waiting for host";
}

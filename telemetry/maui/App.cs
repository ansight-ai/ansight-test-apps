namespace Ansight.TelemetryHarness;

public sealed class App : Application
{
    protected override Window CreateWindow(IActivationState? activationState)
        => new(new TelemetryPage());
}

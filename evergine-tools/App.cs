namespace EvergineToolsDemo;

public sealed class App : Microsoft.Maui.Controls.Application
{
    protected override Window CreateWindow(IActivationState? activationState)
        => new(new MainPage());
}

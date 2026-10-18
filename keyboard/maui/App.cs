namespace Ansight.KeyboardHarness;

public sealed class App : Application
{
    // Keep this as the root activity/page. An accidental Back must expose the regression.
    protected override Window CreateWindow(IActivationState? activationState)
        => new(new KeyboardPage());
}

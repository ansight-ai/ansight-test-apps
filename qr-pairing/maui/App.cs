namespace Ansight.QrPairingHarness;

public sealed class App(MainPage mainPage) : Application
{
    protected override Window CreateWindow(IActivationState? activationState)
        => new(new NavigationPage(mainPage));
}

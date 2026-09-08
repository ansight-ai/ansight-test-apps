using Ansight.AudioHarness.ViewModels;
using PropertyChanged;

namespace Ansight.AudioHarness;

[DoNotNotify]
public partial class App : Application
{
    private readonly MainPage page;
    private readonly HarnessViewModel viewModel;

    public App(MainPage page, HarnessViewModel viewModel)
    {
        InitializeComponent();
        AutomationId = "audio-harness-app";
        this.page = page;
        this.viewModel = viewModel;
        UserAppTheme = AppTheme.Light;
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
        var window = new Window(page) { AutomationId = "audio-harness-window" };
        window.Stopped += async (_, _) => await viewModel.CancelAsync();
        window.Destroying += async (_, _) => await viewModel.CancelAsync();
        return window;
    }
}

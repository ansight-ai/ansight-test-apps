using Ansight.AudioHarness.ViewModels;
using PropertyChanged;

namespace Ansight.AudioHarness;

[DoNotNotify]
public partial class MainPage : ContentPage
{
    public MainPage(HarnessViewModel viewModel)
    {
        InitializeComponent();
        BindingContext = viewModel;
    }
}

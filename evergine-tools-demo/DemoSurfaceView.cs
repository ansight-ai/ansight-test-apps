using EvergineApplication = Evergine.Framework.Application;

namespace EvergineToolsDemo;

public sealed class DemoSurfaceView : View
{
    public static readonly BindableProperty ApplicationProperty = BindableProperty.Create(
        nameof(Application), typeof(EvergineApplication), typeof(DemoSurfaceView));

    public EvergineApplication? Application
    {
        get => (EvergineApplication?)GetValue(ApplicationProperty);
        set => SetValue(ApplicationProperty, value);
    }
}

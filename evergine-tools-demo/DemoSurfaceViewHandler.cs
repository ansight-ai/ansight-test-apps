using Microsoft.Maui.Handlers;

namespace EvergineToolsDemo;

public partial class DemoSurfaceViewHandler
{
    public static IPropertyMapper<DemoSurfaceView, DemoSurfaceViewHandler> PropertyMapper =
        new PropertyMapper<DemoSurfaceView, DemoSurfaceViewHandler>(ViewMapper)
        {
            [nameof(DemoSurfaceView.Application)] = MapApplication
        };

    public static CommandMapper<DemoSurfaceView, DemoSurfaceViewHandler> CommandMapper =
        new(ViewCommandMapper);

    public DemoSurfaceViewHandler() : base(PropertyMapper, CommandMapper) { }
}

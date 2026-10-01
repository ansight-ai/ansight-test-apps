using System.Diagnostics;
using Evergine.Android;
using Evergine.Common.Graphics;
using Evergine.Common.Helpers;
using Evergine.Framework.Graphics;
using Evergine.Framework.Services;
using Evergine.Vulkan;
using Microsoft.Maui.Handlers;

namespace EvergineToolsDemo;

public partial class DemoSurfaceViewHandler : ViewHandler<DemoSurfaceView, AndroidSurfaceView>
{
    private AndroidWindowsSystem? windows;
    private AndroidSurface? surface;
    private VKGraphicsContext? graphics;
    private SwapChain? swapChain;
    private bool started;

    public DemoSurfaceViewHandler(IPropertyMapper mapper, CommandMapper commandMapper)
        : base(mapper, commandMapper) { }

    protected override AndroidSurfaceView CreatePlatformView()
    {
        windows = new AndroidWindowsSystem(Context);
        surface = (AndroidSurface)windows.CreateSurface(0, 0);
        return surface.NativeSurface;
    }

    protected override void ConnectHandler(AndroidSurfaceView platformView)
    {
        base.ConnectHandler(platformView);
        surface!.OnSurfaceInfoChanged += OnSurfaceChanged;
        surface.OnScreenSizeChanged += OnScreenSizeChanged;
    }

    protected override void DisconnectHandler(AndroidSurfaceView platformView)
    {
        surface!.OnSurfaceInfoChanged -= OnSurfaceChanged;
        surface.OnScreenSizeChanged -= OnScreenSizeChanged;
        base.DisconnectHandler(platformView);
    }

    public static void MapApplication(DemoSurfaceViewHandler handler, DemoSurfaceView view)
    {
        if (handler.started || view.Application is not DemoEvergineApplication application)
        {
            return;
        }

        handler.started = true;
        application.Container.RegisterInstance(handler.windows!);
        var timer = Stopwatch.StartNew();
        handler.windows!.Run(
            () =>
            {
                handler.ConfigureGraphics(application);
                application.Initialize();
            },
            () =>
            {
                var elapsed = timer.Elapsed;
                timer.Restart();
                application.UpdateFrame(elapsed);
            });
    }

    private void ConfigureGraphics(DemoEvergineApplication application)
    {
        graphics = new VKGraphicsContext();
        graphics.CreateDevice();
        swapChain = graphics.CreateSwapChain(new SwapChainDescription
        {
            SurfaceInfo = surface!.SurfaceInfo,
            Width = surface.Width,
            Height = surface.Height,
            ColorTargetFormat = PixelFormat.B8G8R8A8_UNorm_SRgb,
            ColorTargetFlags = TextureFlags.RenderTarget | TextureFlags.ShaderResource,
            DepthStencilTargetFormat = PixelFormat.D24_UNorm_S8_UInt,
            SampleCount = TextureSampleCount.None,
            IsWindowed = true,
            RefreshRate = 60
        });
        swapChain.VerticalSync = true;
        application.Container.Resolve<GraphicsPresenter>()
            .AddDisplay("DefaultDisplay", new Display(surface, swapChain));
        application.Container.RegisterInstance<GraphicsContext>(graphics);
    }

    private void OnSurfaceChanged(object? sender, SurfaceInfo info)
    {
        if (surface!.NativeSurface.Width > 0 && surface.NativeSurface.Height > 0)
        {
            swapChain?.RefreshSurfaceInfo(info);
            swapChain?.ResizeSwapChain(surface.Width, surface.Height);
        }
    }

    private void OnScreenSizeChanged(object? sender, SizeEventArgs args)
        => swapChain?.ResizeSwapChain(surface!.Width, surface.Height);
}

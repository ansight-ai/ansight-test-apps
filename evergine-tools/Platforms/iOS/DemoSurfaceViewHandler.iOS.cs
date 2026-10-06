using System.Diagnostics;
using Evergine.Common.Graphics;
using Evergine.Framework.Graphics;
using Evergine.Framework.Services;
using Evergine.iOS;
using Microsoft.Maui.Handlers;
using UIKit;
using Surface = Evergine.Common.Graphics.Surface;

namespace EvergineToolsDemo;

public partial class DemoSurfaceViewHandler : ViewHandler<DemoSurfaceView, UIView>
{
    private readonly DemoViewController controller = new();
    private bool started;

    public DemoSurfaceViewHandler(IPropertyMapper mapper, CommandMapper commandMapper)
        : base(mapper, commandMapper) { }

    protected override UIView CreatePlatformView()
    {
        ViewController = controller;
        return controller.View ?? throw new InvalidOperationException("Evergine view is unavailable.");
    }

    protected override void ConnectHandler(UIView platformView)
    {
        base.ConnectHandler(platformView);
        controller.LaidOut += OnLaidOut;
    }

    protected override void DisconnectHandler(UIView platformView)
    {
        controller.LaidOut -= OnLaidOut;
        base.DisconnectHandler(platformView);
    }

    private void OnLaidOut(object? sender, EventArgs args)
        => UpdateValue(nameof(DemoSurfaceView.Application));

    public static void MapApplication(DemoSurfaceViewHandler handler, DemoSurfaceView view)
    {
        var controllerView = handler.controller.View;
        if (handler.started || view.Application is not DemoEvergineApplication application
            || controllerView is null || controllerView.Bounds.Width <= 0)
        {
            return;
        }

        handler.started = true;
        var windows = new IOSWindowsSystem(handler.controller);
        application.Container.RegisterInstance(windows as WindowsSystem);
        var surface = windows.CreateSurface(
            (uint)Math.Ceiling(controllerView.Bounds.Width),
            (uint)Math.Ceiling(controllerView.Bounds.Height));
        ConfigureGraphics(application, surface);

        var timer = Stopwatch.StartNew();
        windows.Run(
            application.Initialize,
            () =>
            {
                var elapsed = timer.Elapsed;
                timer.Restart();
                application.UpdateFrame(elapsed);
                application.DrawFrame(elapsed);
            });
        handler.controller.LoadAction?.Invoke();
    }

    private static void ConfigureGraphics(DemoEvergineApplication application, Surface surface)
    {
        var graphics = new Evergine.Metal.MTLGraphicsContext();
        graphics.CreateDevice();
        var swapChain = graphics.CreateSwapChain(new SwapChainDescription
        {
            SurfaceInfo = surface.SurfaceInfo,
            Width = surface.Width,
            Height = surface.Height,
            ColorTargetFormat = PixelFormat.B8G8R8A8_UNorm,
            ColorTargetFlags = TextureFlags.RenderTarget | TextureFlags.ShaderResource,
            DepthStencilTargetFormat = PixelFormat.D32_Float,
            DepthStencilTargetFlags = TextureFlags.DepthStencil,
            SampleCount = TextureSampleCount.None,
            IsWindowed = true,
            RefreshRate = 60
        });
        swapChain.VerticalSync = true;
        swapChain.FrameBuffer.IntermediateBufferAssociated = true;
        application.Container.Resolve<GraphicsPresenter>()
            .AddDisplay("DefaultDisplay", new Display(surface, swapChain));
        application.Container.RegisterInstance<GraphicsContext>(graphics);
    }

    private sealed class DemoViewController : EvergineViewController
    {
        public event EventHandler? LaidOut;

        public override void LoadView()
        {
            base.LoadView();
            View = new UIView { ClipsToBounds = true };
        }

        public override void ViewDidLayoutSubviews()
        {
            base.ViewDidLayoutSubviews();
            LaidOut?.Invoke(this, EventArgs.Empty);
        }
    }
}

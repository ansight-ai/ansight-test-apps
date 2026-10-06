using Evergine.Common.IO;
using Evergine.Common.Graphics;
using Evergine.Framework;
using Evergine.Framework.Graphics;
using Evergine.Framework.Graphics.Effects;
using Evergine.Framework.Graphics.Materials;
using Evergine.Framework.Runtimes;
using Evergine.Framework.Services;
using Evergine.Runtimes.GLB;
using Random = Evergine.Framework.Services.Random;
using Microsoft.Maui.ApplicationModel;

namespace EvergineToolsDemo;

public sealed class DemoEvergineApplication : Evergine.Framework.Application
{
    private volatile bool ready;
    private string? modelLoadError;

    public DemoEvergineApplication()
    {
        ActiveInstance = this;
        Container.Register<Settings>();
        Container.Register<Clock>();
        Container.Register<TimerFactory>();
        Container.Register<Random>();
        Container.Register<ErrorHandler>();
        Container.Register<ScreenContextManager>();
        Container.Register<GraphicsPresenter>();
        Container.Register<AssetsDirectory>();
        Container.Register<AssetsService>();
        Container.Register<ForegroundTaskSchedulerService>();
        Container.Register<WorkActionScheduler>();
    }

    public static DemoEvergineApplication? ActiveInstance { get; private set; }

    public DemoScene? Scene { get; private set; }

    public string? ModelLoadError => modelLoadError;

    public event Action<string>? ModelLoadCompleted;

    public override void Initialize()
    {
        base.Initialize();
        Scene = new DemoScene();
        Container.Resolve<ScreenContextManager>().To(new ScreenContext(Scene));
#if IOS
        Scene.Initialize();
#endif
        ready = true;
        _ = LoadModelAsync();
    }

    public Task<T> InvokeAsync<T>(Func<DemoScene, T> action)
    {
        ArgumentNullException.ThrowIfNull(action);
        return MainThread.InvokeOnMainThreadAsync(() =>
        {
            if (!ready || Scene?.HasCamera != true)
            {
                throw new InvalidOperationException("The Evergine scene is not ready yet.");
            }

            return action(Scene);
        });
    }

    private async Task LoadModelAsync()
    {
        try
        {
            await using var packageFile = await FileSystem.OpenAppPackageFileAsync("AirJordan.glb");
            using var stream = new MemoryStream();
            await packageFile.CopyToAsync(stream);
            stream.Position = 0;

            var assets = Container.Resolve<AssetsService>();
            var model = await GLBRuntime.Instance.Read(stream, async data =>
            {
                var baseColor = await data.GetBaseColorTextureAndSampler();
                var effect = assets.Load<Evergine.Framework.Graphics.Effects.Effect>(DefaultResourcesIDs.StandardEffectID);
                var layer = assets.Load<RenderLayerDescription>(DefaultResourcesIDs.OpaqueRenderLayerID);
                var material = new StandardMaterial(effect)
                {
                    BaseColor = data.BaseColor,
                    BaseColorTexture = baseColor.Texture,
                    BaseColorSampler = baseColor.Sampler,
                    Metallic = data.MetallicFactor,
                    Roughness = data.RoughnessFactor,
                    LayerDescription = layer,
                    LightingEnabled = false
                };
                return material.Material;
            });

            await MainThread.InvokeOnMainThreadAsync(() =>
            {
                Scene?.AddModel(model.InstantiateModelHierarchy(assets));
                ModelLoadCompleted?.Invoke("Air Jordan 1 GLB loaded into Evergine.");
            });
        }
        catch (Exception exception)
        {
            modelLoadError = exception.ToString();
            System.Diagnostics.Debug.WriteLine(modelLoadError);
            await MainThread.InvokeOnMainThreadAsync(() =>
                ModelLoadCompleted?.Invoke($"GLB load failed: {exception.Message}"));
        }
    }
}

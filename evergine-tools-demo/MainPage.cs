namespace EvergineToolsDemo;

public sealed class MainPage : ContentPage
{
    private readonly DemoEvergineApplication engine = new();
    private readonly Label status = new() { Text = "Loading Air Jordan 1 GLB..." };

    public MainPage()
    {
        engine.ModelLoadCompleted += message => status.Text = message;
        Title = "Evergine Tools Demo";
        var surface = new DemoSurfaceView
        {
            Application = engine,
            BackgroundColor = Microsoft.Maui.Graphics.Colors.CornflowerBlue
        };
        var previousPanX = 0d;
        var previousPanY = 0d;
        var orbitGesture = new PanGestureRecognizer();
        orbitGesture.PanUpdated += async (_, args) =>
        {
            if (args.StatusType != GestureStatus.Running)
            {
                previousPanX = 0;
                previousPanY = 0;
                return;
            }

            var deltaX = args.TotalX - previousPanX;
            var deltaY = args.TotalY - previousPanY;
            previousPanX = args.TotalX;
            previousPanY = args.TotalY;
            try
            {
                await engine.InvokeAsync(scene =>
                {
                    scene.OrbitCamera((float)deltaX, (float)deltaY);
                    return true;
                });
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
        };
        surface.GestureRecognizers.Add(orbitGesture);
        var moveCamera = new Button { Text = "Move camera" };
        moveCamera.Clicked += async (_, _) =>
        {
            try
            {
                await engine.InvokeAsync(scene =>
                {
                    scene.MoveCamera();
                    return true;
                });
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
        };

        var resetCamera = new Button { Text = "Reset view" };
        resetCamera.Clicked += async (_, _) =>
        {
            try
            {
                await engine.InvokeAsync(scene =>
                {
                    scene.ResetCamera();
                    return true;
                });
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
        };

        var layout = new Grid
        {
            RowDefinitions =
            {
                new RowDefinition { Height = GridLength.Auto },
                new RowDefinition { Height = GridLength.Star },
                new RowDefinition { Height = GridLength.Auto }
            },
            Padding = new Thickness(12)
        };
        layout.Add(new Label
        {
            Text = "Evergine GLB scene: Air Jordan 1",
            FontAttributes = FontAttributes.Bold
        }, 0, 0);
        layout.Add(surface, 0, 1);
        layout.Add(new VerticalStackLayout
        {
            Children =
            {
                new HorizontalStackLayout
                {
                    Spacing = 12,
                    Children = { moveCamera, resetCamera }
                },
                new Label { Text = "Drag the model to orbit", FontSize = 12 },
                status,
                new Label { Text = "Model: makoto on Sketchfab · CC BY", FontSize = 12 }
            }
        }, 0, 2);
        Content = layout;
    }
}

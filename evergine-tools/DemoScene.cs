using Evergine.Framework;
using Evergine.Framework.Graphics;
using Evergine.Mathematics;
using Color = Evergine.Common.Graphics.Color;

namespace EvergineToolsDemo;

public sealed class DemoScene : Scene
{
    private static readonly Vector3 initialCameraPosition = new(0, 0, 8);
    private const float orbitRadiansPerPoint = 0.004f;
    private const float maxPitch = 1.3f;
    private Transform3D? cameraTransform;
    private float cameraYaw;
    private float cameraPitch;
    private float cameraDistance = initialCameraPosition.Length();

    public bool HasCamera => cameraTransform is not null;

    public Vector3 CameraPosition => cameraTransform?.Position ?? initialCameraPosition;

    public bool HasModel { get; private set; }

    public void AddModel(Entity model)
    {
        model.Name = "AirJordan1";
        var transform = model.FindComponent<Transform3D>();
        if (transform is not null)
        {
            transform.LocalScale = new Vector3(0.11f, 0.11f, 0.11f);
            transform.LocalRotation = new Vector3(0, 1.22f, 0);
            transform.LocalPosition = new Vector3(0, 0, 0);
        }
        Managers.EntityManager.Add(model);
        HasModel = true;
    }

    protected override void CreateScene()
    {
        var camera = new Entity("DemoCamera")
            .AddComponent(new Transform3D { Position = initialCameraPosition })
            .AddComponent(new Camera3D { BackgroundColor = Color.CornflowerBlue });
        Managers.EntityManager.Add(camera);
        cameraTransform = camera.FindComponent<Transform3D>();

        AddMarker("X marker", new Vector3(2, 0, 0));
        AddMarker("Y marker", new Vector3(0, 2, 0));
        AddMarker("Z marker", new Vector3(0, 0, 2));
    }

    public void MoveCamera()
    {
        var position = new Vector3(2, 1, 8);
        cameraDistance = position.Length();
        cameraYaw = MathF.Atan2(position.X, position.Z);
        cameraPitch = MathF.Asin(position.Y / cameraDistance);
        UpdateCamera();
    }

    public void OrbitCamera(float deltaX, float deltaY)
    {
        cameraYaw -= deltaX * orbitRadiansPerPoint;
        cameraPitch = Math.Clamp(cameraPitch + deltaY * orbitRadiansPerPoint,
            -maxPitch, maxPitch);
        UpdateCamera();
    }

    public void ResetCamera()
    {
        cameraYaw = 0;
        cameraPitch = 0;
        cameraDistance = initialCameraPosition.Length();
        UpdateCamera();
    }

    private void UpdateCamera()
    {
        var transform = cameraTransform
            ?? throw new InvalidOperationException("The demo camera is not ready.");
        var horizontalDistance = cameraDistance * MathF.Cos(cameraPitch);
        transform.Position = new Vector3(
            horizontalDistance * MathF.Sin(cameraYaw),
            cameraDistance * MathF.Sin(cameraPitch),
            horizontalDistance * MathF.Cos(cameraYaw));
        transform.LookAt(Vector3.Zero);
    }

    private void AddMarker(string name, Vector3 position)
    {
        Managers.EntityManager.Add(new Entity(name)
            .AddComponent(new Transform3D { Position = position }));
    }
}

using System.Runtime.InteropServices;
using Microsoft.Maui.ApplicationModel;

namespace BoulderCaptureSpike;

internal static class BoulderCaptureNative
{
    [DllImport("__Internal", EntryPoint = "BoulderCapture_IsSupported")]
    private static extern int IsSupportedNative();

    [DllImport("__Internal", EntryPoint = "BoulderCapture_Present")]
    private static extern int PresentNative(nint hostController);

    [DllImport("__Internal", EntryPoint = "SceneMesh_IsSupported")]
    private static extern int SceneMeshIsSupportedNative();

    [DllImport("__Internal", EntryPoint = "SceneMesh_Present")]
    private static extern int SceneMeshPresentNative(nint hostController);

    [DllImport("__Internal", EntryPoint = "SceneMesh_PresentWithQuality")]
    private static extern int SceneMeshPresentWithQualityNative(nint hostController, int quality);

    [DllImport("__Internal", EntryPoint = "SceneMesh_PresentGlb")]
    private static extern int SceneMeshPresentGlbNative(nint hostController,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("__Internal", EntryPoint = "BoulderCapture_CopyStatus")]
    private static extern nint CopyStatusNative();

    [DllImport("__Internal", EntryPoint = "BoulderCapture_CopyGlbPath")]
    private static extern nint CopyGlbPathNative();

    [DllImport("__Internal", EntryPoint = "BoulderCapture_CopyUsdzPath")]
    private static extern nint CopyUsdzPathNative();

    [DllImport("__Internal", EntryPoint = "BoulderCapture_CopyDiagnosticsPath")]
    private static extern nint CopyDiagnosticsPathNative();

    [DllImport("__Internal", EntryPoint = "BoulderCapture_FreeString")]
    private static extern void FreeStringNative(nint value);

    public static bool IsSupported => IsSupportedNative() != 0;
    public static bool IsSceneMeshSupported => SceneMeshIsSupportedNative() != 0;

    public static bool Present()
    {
        var host = Platform.GetCurrentUIViewController();
        return host != null && PresentNative(host.Handle) != 0;
    }

    public static bool PresentSceneMesh(bool highDetail)
    {
        var host = Platform.GetCurrentUIViewController();
        return host != null && SceneMeshPresentWithQualityNative(host.Handle, highDetail ? 1 : 0) != 0;
    }

    public static bool PresentGlb(string path)
    {
        if (!File.Exists(path)) return false;
        var host = Platform.GetCurrentUIViewController();
        return host != null && SceneMeshPresentGlbNative(host.Handle, path) != 0;
    }

    public static string Status => ReadString(CopyStatusNative());
    public static string GlbPath => ReadString(CopyGlbPathNative());
    public static string UsdzPath => ReadString(CopyUsdzPathNative());
    public static string DiagnosticsPath => ReadString(CopyDiagnosticsPathNative());

    private static string ReadString(nint value)
    {
        if (value == 0)
        {
            return string.Empty;
        }

        try
        {
            return Marshal.PtrToStringUTF8(value) ?? string.Empty;
        }
        finally
        {
            FreeStringNative(value);
        }
    }
}

using Ansight.Tools;

namespace Ansight.QrPairingHarness.Integration;

internal abstract class UserConfirmedAnsightToolBase(ITool innerTool, AnsightRemoteToolConsent consent)
{
    protected ITool InnerTool => innerTool;
    public string Category => innerTool.Category;
    public ToolPolicy Policy => innerTool.Policy;
    public string Id => innerTool.Id;
    public string Name => innerTool.Name;
    public string Description => innerTool.Description;
    public string Keywords => innerTool.Keywords;
    public ToolSchema ArgumentsSchema => innerTool.ArgumentsSchema;
    public ToolSchema ResultSchema => innerTool.ResultSchema;
    public IReadOnlyList<string> PrerequisiteToolIds => innerTool.PrerequisiteToolIds;

    // Discovery never prompts. The SDK's grant and availability checks still run before execution.
    public ValueTask<ToolAvailability> GetAvailabilityAsync(ToolAvailabilityContext context)
        => innerTool.GetAvailabilityAsync(context);

    protected async Task<ToolResult?> GetDeniedResultAsync(CancellationToken cancellationToken = default)
        => await consent.EnsureAllowedAsync(Name, cancellationToken)
            ? null
            : ToolResult.Failure("Access to Ansight remote tools was not allowed by the user.",
                errorCode: "ansight_remote_tools_not_allowed");
}

internal sealed class UserConfirmedAnsightTool(ITool innerTool, AnsightRemoteToolConsent consent)
    : UserConfirmedAnsightToolBase(innerTool, consent), ITool
{
    public async Task<ToolResult> Execute(IReadOnlyDictionary<string, string> arguments)
        => await GetDeniedResultAsync() ?? await InnerTool.Execute(arguments);

    public static ITool Create(ITool tool, AnsightRemoteToolConsent consent)
        => tool is IJsonTool jsonTool
            ? new UserConfirmedAnsightJsonTool(jsonTool, consent)
            : new UserConfirmedAnsightTool(tool, consent);
}

internal sealed class UserConfirmedAnsightJsonTool(IJsonTool innerTool, AnsightRemoteToolConsent consent)
    : UserConfirmedAnsightToolBase(innerTool, consent), IJsonTool
{
    public async Task<ToolResult> ExecuteAsync(ToolInvocation invocation, CancellationToken cancellationToken)
        => await GetDeniedResultAsync(cancellationToken)
            ?? await innerTool.ExecuteAsync(invocation, cancellationToken);
}

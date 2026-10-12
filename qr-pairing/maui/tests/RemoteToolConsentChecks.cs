using System.Text.Json.Nodes;
using Ansight.QrPairingHarness.Integration;
using Ansight.Tools;

internal static class RemoteToolConsentChecks
{
    public static async Task RunAsync()
    {
        var allowed = false;
        var answer = false;
        var prompts = 0;
        var consent = new AnsightRemoteToolConsent(true, () => allowed, value => allowed = value,
            _ => { prompts++; return Task.FromResult(answer); });
        var inner = new RecordingTool();
        var tool = UserConfirmedAnsightTool.Create(inner, consent);
        var arguments = new Dictionary<string, string> { ["value"] = "synthetic" };
        var denied = await tool.Execute(arguments);
        Require(!denied.IsSuccess && denied.ErrorCode == "ansight_remote_tools_not_allowed"
            && inner.Executions == 0 && !allowed, "Denial must block the underlying tool.");
        Require(tool.Policy == ToolPolicy.Write && tool.PrerequisiteToolIds.SequenceEqual(inner.PrerequisiteToolIds),
            "Consent must preserve SDK policy and prerequisite metadata.");
        Require(!(await tool.GetAvailabilityAsync(new(null, null))).IsAvailable && prompts == 1,
            "Discovery must preserve underlying availability without prompting.");

        answer = true;
        Require((await tool.Execute(arguments)).IsSuccess, "Approval must allow execution.");
        Require((await tool.Execute(arguments)).IsSuccess && prompts == 2 && inner.Executions == 2,
            "Remembered consent must avoid another prompt.");
        var restartedConsent = new AnsightRemoteToolConsent(true, () => allowed, value => allowed = value,
            _ => throw new InvalidOperationException("Remembered approval must survive a new helper instance."));
        Require(await restartedConsent.EnsureAllowedAsync(), "Saved consent must survive app restart.");
        consent.Revoke();
        answer = false;
        Require(!(await tool.Execute(arguments)).IsSuccess && inner.Executions == 2 && !allowed,
            "Revocation must apply to the next execution.");

        var pending = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var sharedPrompts = 0;
        var sharedAllowed = false;
        var sharedConsent = new AnsightRemoteToolConsent(true, () => sharedAllowed,
            value => sharedAllowed = value, _ => { sharedPrompts++; return pending.Task; });
        var first = sharedConsent.EnsureAllowedAsync();
        var second = sharedConsent.EnsureAllowedAsync();
        pending.SetResult(true);
        Require(await first && await second && sharedPrompts == 1,
            "Concurrent requests must share remembered approval and show only one prompt.");

        pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        sharedConsent.Revoke();
        var revokedPrompt = sharedConsent.EnsureAllowedAsync();
        sharedConsent.Revoke();
        pending.SetResult(true);
        Require(!await revokedPrompt && !sharedAllowed, "Revocation must invalidate an in-flight approval.");

        pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        using var cancellation = new CancellationTokenSource();
        var cancelledPrompt = sharedConsent.EnsureAllowedAsync(cancellationToken: cancellation.Token);
        cancellation.Cancel();
        pending.SetResult(true);
        try
        {
            await cancelledPrompt;
            throw new InvalidOperationException("Cancelled requests must not grant consent.");
        }
        catch (OperationCanceledException) { }
        Require(!sharedAllowed, "Cancellation must not persist approval.");

        var virtualConsent = new AnsightRemoteToolConsent(false, () => false,
            _ => throw new InvalidOperationException("Virtual targets must not persist consent."),
            _ => throw new InvalidOperationException("Virtual targets must not prompt."));
        var jsonInner = new RecordingJsonTool();
        var jsonTool = UserConfirmedAnsightTool.Create(jsonInner, virtualConsent) as IJsonTool;
        Require(jsonTool is not null, "Structured JSON tools must retain their invocation contract.");
        var invocation = new ToolInvocation(
            new JsonObject { ["nested"] = new JsonArray(1, 2, 3) },
            new ToolInvocationContext("synthetic-request", "synthetic-session", CallId: null));
        Require((await jsonTool!.ExecuteAsync(invocation, CancellationToken.None)).IsSuccess
            && ReferenceEquals(jsonInner.Invocation, invocation),
            "The wrapper must preserve structured arguments and request context.");
        var jsonDenied = (IJsonTool)UserConfirmedAnsightTool.Create(jsonInner, consent);
        Require(!(await jsonDenied.ExecuteAsync(invocation, CancellationToken.None)).IsSuccess
            && jsonInner.Executions == 1, "Consent must gate the JSON execution path too.");
        Console.WriteLine("Passed: remote-tools denial, approval, persistence, revocation, concurrent prompts, cancellation, metadata and JSON dispatch.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private class RecordingTool : ITool
    {
        public int Executions { get; protected set; }
        public string Category => "test";
        public ToolPolicy Policy => ToolPolicy.Write;
        public string Id => "test.record";
        public string Name => "Record synthetic value";
        public string Description => "Test fixture";
        public string Keywords => "test";
        public ToolSchema ArgumentsSchema => ToolSchema.Object();
        public ToolSchema ResultSchema => ToolSchema.Object();
        public IReadOnlyList<string> PrerequisiteToolIds => ["test.prepare"];
        public ValueTask<ToolAvailability> GetAvailabilityAsync(ToolAvailabilityContext context)
            => ValueTask.FromResult(ToolAvailability.Unavailable("fixture_unavailable", "Fixture is unavailable."));
        public Task<ToolResult> Execute(IReadOnlyDictionary<string, string> arguments)
        {
            Executions++;
            return Task.FromResult(ToolResult.Success());
        }
    }

    private sealed class RecordingJsonTool : RecordingTool, IJsonTool
    {
        public ToolInvocation? Invocation { get; private set; }
        public Task<ToolResult> ExecuteAsync(ToolInvocation invocation, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Invocation = invocation;
            Executions++;
            return Task.FromResult(ToolResult.Success());
        }
    }
}

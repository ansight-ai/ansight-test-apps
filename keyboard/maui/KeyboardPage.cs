namespace Ansight.KeyboardHarness;

public sealed class KeyboardPage : ContentPage
{
    private readonly Entry entry;
    private readonly Editor editor;
    private readonly Label response;
    private int responseCount;

    public KeyboardPage()
    {
        Title = "Keyboard regression";
        AutomationId = "keyboard.root";
        BackgroundColor = Color.FromArgb("#F3F7F8");
        entry = new Entry
        {
            AutomationId = "keyboard.entry",
            Placeholder = "Single-line input",
            Text = "Entry text survives",
            TextColor = Colors.Black,
            BackgroundColor = Colors.White
        };
        editor = new Editor
        {
            AutomationId = "keyboard.editor",
            Placeholder = "Multiline input",
            Text = "Editor text survives",
            HeightRequest = 90,
            TextColor = Colors.Black,
            BackgroundColor = Colors.White
        };
        response = new Label { AutomationId = "keyboard.response", TextColor = Colors.Black, Text = "Response count: 0" };
        var verify = new Button { AutomationId = "keyboard.verify", Text = "Verify app responds" };
        verify.Clicked += (_, _) => response.Text = $"Response count: {++responseCount}";
        var reset = new Button { AutomationId = "keyboard.reset", Text = "Reset test" };
        reset.Clicked += (_, _) =>
        {
            entry.Unfocus();
            editor.Unfocus();
            entry.Text = "Entry text survives";
            editor.Text = "Editor text survives";
            responseCount = 0;
            response.Text = "Response count: 0";
        };
        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = 20,
                Spacing = 12,
                Children =
                {
                    new Label { Text = "Keyboard regression", FontSize = 26, TextColor = Colors.Black },
                    new Label { AutomationId = "keyboard.root-marker", Text = "Root page active", TextColor = Colors.Black },
                    new Label { Text = "Dismiss the keyboard with Ansight. This root page must stay open and keep both input values.", TextColor = Colors.Black },
                    entry,
                    editor,
                    response,
                    verify,
                    reset
                }
            }
        };
    }
}

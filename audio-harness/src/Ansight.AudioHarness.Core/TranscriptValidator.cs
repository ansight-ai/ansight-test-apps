using System.Globalization;
using System.Text;

namespace Ansight.AudioHarness.Core;

/// <summary>
/// Compares a completed recognition result with the whole expected phrase.
/// No fuzzy matching, substring matching, or spoken-number conversion is performed.
/// </summary>
public static class TranscriptValidator
{
    public static TranscriptValidation Validate(string? expected, string? transcript, bool isFinal)
    {
        var normalizedExpected = Normalize(expected);
        var normalizedActual = Normalize(transcript);

        if (normalizedExpected.Length == 0)
        {
            return new(TranscriptValidationState.Failed, normalizedExpected, normalizedActual,
                "Enter an expected phrase containing words or numbers.");
        }

        if (!isFinal)
        {
            return new(TranscriptValidationState.Pending, normalizedExpected, normalizedActual,
                "Waiting for a final transcript.");
        }

        if (normalizedActual.Length == 0)
        {
            return new(TranscriptValidationState.Failed, normalizedExpected, normalizedActual,
                "The final transcript is empty.");
        }

        return string.Equals(normalizedExpected, normalizedActual, StringComparison.Ordinal)
            ? new(TranscriptValidationState.Passed, normalizedExpected, normalizedActual,
                "The final transcript matches the expected phrase.")
            : new(TranscriptValidationState.Failed, normalizedExpected, normalizedActual,
                "The final transcript does not match the whole expected phrase.");
    }

    // Canonical Unicode, invariant casing, ordinary punctuation, and whitespace
    // are normalized. Apostrophes inside words do not split contractions.
    // Decimal/group separators and numeric signs remain significant: silently
    // equating 1.5 with 15 or -5 with 5 would make an audio assertion unsafe.
    private static string Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var runes = value.Normalize(NormalizationForm.FormC).EnumerateRunes().ToArray();
        var builder = new StringBuilder();
        var pendingSeparator = false;

        for (var index = 0; index < runes.Length; index++)
        {
            var rune = runes[index];
            var hasPrevious = index > 0;
            var hasNext = index + 1 < runes.Length;
            var previousIsDigit = hasPrevious && Rune.IsDigit(runes[index - 1]);
            var nextIsDigit = hasNext && Rune.IsDigit(runes[index + 1]);
            var isInnerApostrophe = rune.Value is '\'' or 0x2019 or 0x02BC
                && hasPrevious && hasNext
                && Rune.IsLetter(runes[index - 1]) && Rune.IsLetter(runes[index + 1]);

            if (isInnerApostrophe)
            {
                continue;
            }

            var category = Rune.GetUnicodeCategory(rune);
            var isWordRune = Rune.IsLetterOrDigit(rune)
                || category is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark;
            var isNumberSeparator = rune.Value is '.' or ',' && previousIsDigit && nextIsDigit;
            var isNumberSign = rune.Value is '+' or '-' or 0x2212 && nextIsDigit;

            if (isWordRune || isNumberSeparator || isNumberSign)
            {
                if (pendingSeparator && builder.Length > 0)
                {
                    builder.Append(' ');
                }

                builder.Append(rune.Value == 0x2212 ? "-" : Rune.ToUpperInvariant(rune).ToString());
                pendingSeparator = false;
            }
            else
            {
                pendingSeparator = true;
            }
        }

        return builder.ToString().Normalize(NormalizationForm.FormC);
    }
}

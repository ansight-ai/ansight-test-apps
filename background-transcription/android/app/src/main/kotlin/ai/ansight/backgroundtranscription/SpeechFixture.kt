package ai.ansight.backgroundtranscription

enum class RecordingDuration(
    val title: String,
    val durationSeconds: Int,
    val injectedFixtureFileName: String? = null,
) {
    TwentySeconds("20 seconds", 20, "fdr-day-of-infamy-20s.wav"),
    ThirtySeconds("30 seconds", 30, "fdr-day-of-infamy-30s.wav"),
    SixtySeconds("60 seconds", 60, "fdr-day-of-infamy-60s.wav"),
    TwoMinutes("2 minutes", 120),
    FiveMinutes("5 minutes", 300),
    TenMinutes("10 minutes", 600),
    TwentyMinutes("20 minutes", 1_200);

    val supportsInjectedFixture: Boolean
        get() = injectedFixtureFileName != null
}

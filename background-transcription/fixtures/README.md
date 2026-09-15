# Real-world speech fixtures

These fixtures are excerpts from President Franklin D. Roosevelt's original
December 8, 1941 “Day of Infamy” address to a joint session of Congress. They
retain the voice, room acoustics, broadcast noise, cadence, and applause of the
archival recording. Only clipping, mono downmixing, 16 kHz resampling, PCM16
encoding, and short trailing silence were applied.

The source recording is held by the U.S. National Archives and was obtained
from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:FDR%27s_Speech_to_the_Congress_regarding_the_naval_attack_on_Pearl_Harbor.ogg),
where it is identified as a U.S. federal government work in the public domain
in the United States. Source SHA-256:
`ae3cf3888dbebdb0318d6c3e91c7b4355e37912ac1c41ef48cf197dccc85f6ea`.

The historical recording discusses the attack on Pearl Harbor and the United
States' entry into World War II.

| Fixture | Duration | Source range | SHA-256 |
| --- | ---: | ---: | --- |
| `fdr-day-of-infamy-20s.wav` | 20.000 s | 74.00–93.76 s | `51868ad070cff82bd790ab7e16305ef3a138fe2696e9ca0075d1277ed50982e8` |
| `fdr-day-of-infamy-30s.wav` | 30.000 s | 141.76–170.76 s | `11d2cdf3c1d20d2b116dcf5f7f2c76ac69a3c67814d14dc2212ec20d010b923d` |
| `fdr-day-of-infamy-60s.wav` | 60.000 s | 13.60–73.36 s | `846b38f8985c0f0761ae7528607183f176b545895586e5a690605e9d86a4c695` |

## Expected transcripts

### `fdr-day-of-infamy-20s.wav`

Source range: 74.00–93.76 seconds, followed by 0.24 seconds of silence.

> I regret to tell you that very many American lives have been lost. In
> addition, American ships have been reported torpedoed on the high seas
> between San Francisco and Honolulu.

### `fdr-day-of-infamy-30s.wav`

Source range: 141.76–170.76 seconds, followed by 1.00 second of silence.

> I believe that I interpret the will of the Congress and of the people when I
> assert that we will not only defend ourselves to the uttermost, but will
> make it very certain that this form of treachery shall never endanger us
> again.

### `fdr-day-of-infamy-60s.wav`

Source range: 13.60–73.36 seconds, followed by 0.24 seconds of silence.

> Yesterday, December 7th, 1941—a date which will live in infamy—the United
> States of America was suddenly and deliberately attacked by naval and air
> forces of the Empire of Japan. The United States was at peace with that
> nation and, at the solicitation of Japan, was still in conversation with its
> government and its emperor, looking toward the maintenance of peace in the
> Pacific. The attack yesterday on the Hawaiian Islands has caused severe
> damage to American naval and military forces.

Expected transcripts should be compared after case folding and punctuation
normalization. Archival noise means recognition accuracy is intentionally more
challenging than the existing synthetic Hamlet fixture.

## Regeneration

Run the following on macOS with `curl` and `ffmpeg` installed:

```sh
../scripts/make-real-speech-fixtures.sh
```

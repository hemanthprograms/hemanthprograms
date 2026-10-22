# SnoreGuard

SnoreGuard helps you find out **which remedy actually reduces your snoring**. Each night you pick one
remedy (or "No remedy" for a baseline night), leave your iPhone by the bed, and the app measures
snoring on the device. After a few nights it compares the remedies and tells you honestly whether any
of them helped, or that it's too early to say.

> SnoreGuard is a wellness tool, not a medical device. If you're worried about your sleep or
> breathing, talk to a doctor.

- iOS 17+, Swift 5.10+, SwiftUI, SwiftData, Swift Charts, SoundAnalysis, AVFoundation
- No third-party dependencies, no backend, no accounts, no analytics, no network calls

## Running it

You need a Mac with Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(the Xcode project is generated from `project.yml` and isn't checked in).

```sh
brew install xcodegen
cd SnoreGuard
xcodegen generate          # or: make project
open SnoreGuard.xcodeproj  # pick an iPhone simulator and press Run
```

From the command line:

```sh
make build   # xcodegen + xcodebuild build
make test    # xcodegen + xcodebuild test
# Use a different simulator:
make test DESTINATION='platform=iOS Simulator,name=iPhone 15'
```

**Demo mode.** Debug builds running in the Simulator turn demo mode on the first time they launch,
which fills the app with 12 realistic nights, so every screen has something to show without anyone
sleeping. You can switch it on or off at any time in Settings → Demo mode; switching it off removes
only the demo nights.

**Trying detection in the Simulator.** On the Start night screen, "Analyze sample recording" runs the
real detection pipeline over a bundled clip, and "Import an audio file…" runs it over any recording you
choose. Both go through the same code path as the microphone. To test on your own snoring without an
iOS 17 phone, record a night with Voice Memos, AirDrop it to the Mac, drag it onto the Simulator (it
lands in Files) and import it. The Simulator also listens through the Mac's microphone, so Start night
works there too.

**On a device.** Set your team under Signing & Capabilities, run on an iPhone, allow the microphone,
plug the phone in and tap Start night.

## Screens

| Screen | What it does |
| --- | --- |
| Onboarding | Three pages: what the app does (with the disclaimer), microphone permission, pick up to 3 remedies to test. |
| Tonight (home) | Tonight's suggested remedy, plan progress ("Night 5 of 12"), last night's summary, Start night. |
| Start night | Choose exactly one remedy (defaults to the plan's suggestion), bedtime tips, test with an audio file. |
| Recording | Near-black screen with elapsed time, a live "Snoring detected" indicator, event count and a large Stop button. Fades almost to black after 20 s; tap to wake. Prompts you to plug in when on battery. |
| Night detail | Snore minutes per hour, totals, a timeline of events, snore minutes by hour, the event list and clip playback when clips are on. |
| Results | A one-sentence summary, a bar chart (mean ± 1 SD per remedy, dashed baseline line) and a row per remedy with its label. |
| History | Every night, newest first; swipe to delete. |
| Settings | Save snore clips, detection sensitivity, manage remedies, start a new plan, CSV export, delete all data, demo mode, the disclaimer. |

Every list and chart has an empty state that says what to do next. Text uses Dynamic Type styles and
the interactive elements and charts have VoiceOver labels.

## Architecture

MVVM-ish SwiftUI. Views read SwiftData with `@Query`; anything with logic lives in plain types that are
easy to test.

```
SnoreGuard/
├── App/          SnoreGuardApp, RootView + tabs, launch bootstrap, settings keys, Sensitivity
├── Models/       SwiftData: Night, SnoreEvent, Remedy, Plan
├── Detection/    SnoreDetecting protocol, LiveSnoreDetector, FileSnoreDetector,
│                 SoundClassifierPipeline, EventMerger, NightTotals, SnoreClipRecorder, DetectionConfig
├── Analysis/     RemedyAnalyzer, Statistics (permutation test), PlanEngine, ResultsBuilder
├── Services/     RecordingService, DemoData, CSVExporter, RemedyCatalog, NightStore, ClipStore, ClipPlayer
├── Views/        One folder per screen, plus Theme, Format and shared components
└── Resources/    Asset catalog, SampleSnoring.m4a
SnoreGuardTests/  XCTest unit tests
Tools/            Scripts that generate the sample recording and the app icon
```

- **`SnoreDetecting`** is the seam between audio and everything else. `start()` returns an
  `AsyncThrowingStream` of classified windows (plus paused/resumed signals); `stop()` ends it.
  - `LiveSnoreDetector`: `AVAudioEngine` input tap → `SoundClassifierPipeline`. Handles the audio session.
  - `FileSnoreDetector`: reads any audio file in chunks → the same `SoundClassifierPipeline`.
- **`RecordingService`** (`@MainActor @Observable`) owns one night: it consumes the stream, feeds an
  `EventMerger`, drives the live indicator, saves clips if enabled, checkpoints the night to SwiftData
  every 5 minutes and finalizes it on Stop.
- **`EventMerger`**, **`NightTotals`**, **`RemedyAnalyzer`**, **`Statistics`** and **`PlanEngine`** are pure
  value-type logic with no UI or persistence dependencies, and are unit tested.

### Data model

- `Night`: start and end time, remedy, listening time (`recordedDuration`), total snore minutes,
  **snore minutes per hour** (the main metric), event count, the threshold it was recorded with, its
  source (microphone, file, demo) and its events. No audio.
- `SnoreEvent`: start, duration, peak confidence, and an optional clip file name.
- `Remedy`: name, SF Symbol, a summary phrase ("Sleeping on your side"), built-in or custom. Exactly
  one built-in remedy is the baseline ("No remedy").
- `Plan`: the ordered remedies to test (baseline first) and nights per step (3).

## Detection pipeline

```
microphone ─► AVAudioEngine tap (8192 frames) ─┐
                                               ├─► SNAudioStreamAnalyzer + SNClassifySoundRequest(.version1)
audio file ─► AVAudioFile, 16384-frame chunks ─┘          │  1.5 s windows, 50% overlap
                                                          ▼
                                     "snoring" confidence per window (DetectionWindow)
                                                          ▼
                              EventMerger: window counts if confidence ≥ threshold,
                              merge when gap < 10 s, drop events < 3 s
                                                          ▼
                       Night: events, total minutes, minutes per hour of listening
```

All thresholds live in `Detection/DetectionConfig.swift`:

| Constant | Value | Meaning |
| --- | --- | --- |
| `windowDuration` | 1.5 s | Preferred classifier window (clamped to what the classifier allows) |
| `windowOverlap` | 0.5 | 50% overlap, so a new window every 0.75 s |
| `defaultThreshold` | 0.6 | Window counts as snoring at or above this confidence |
| Sensitivity | Low 0.7 / Normal 0.6 / High 0.5 | User-facing threshold (Settings) |
| `mergeGap` | 10 s | Snoring windows closer than this join one event |
| `minimumEventDuration` | 3 s | Shorter events are dropped |
| `minimumNightDuration` | 30 min | Shorter nights are kept but excluded from results and plan progress |
| `maxClipsPerNight` / `clipDuration` | 10 / 10 s | Only when "Save snore clips" is on |
| `checkpointInterval` | 5 min | How often an in-progress night is saved |

**Overnight recording.** The app declares the `audio` background mode and uses an `AVAudioSession`
with category `.record` and mode `.measurement`. On an interruption (a call, Siri) listening pauses and
then resumes automatically when it ends, whether or not the system suggests resuming. Route changes,
engine configuration changes and media-services resets rebuild the engine with the new input format. If
a restart fails it retries every 15 seconds and again when the app returns to the foreground. Time spent
paused is excluded from the listening time, so per-hour numbers stay honest. While the phone is
charging the screen stays on (dark); on battery it may lock as usual and listening continues in the
background.

**Crash safety.** A night in progress is saved every 5 minutes. If the app is killed before Stop, the
next launch keeps everything up to the last save and marks the night "Recovered".

## How remedies are compared

For each remedy with at least one counted night, SnoreGuard shows the mean snore minutes per hour, the
number of nights and the change against the baseline mean. Labels come from `RemedyAnalyzer`:

| Label | Rule |
| --- | --- |
| Not enough data yet | Fewer than 3 nights for the remedy or the baseline (shows how many more are needed) |
| Likely helps | At least 20% less snoring **and** a one-sided permutation test p < 0.1 |
| Might help | At least 10% less snoring |
| Seems worse | At least 10% more snoring |
| No clear effect | Anything else |

The permutation test asks: if remedy and baseline nights were shuffled at random, how often would the
remedy look at least this good? Small groups are enumerated exactly; larger groups use 10,000 seeded
shuffles so results are repeatable. With 3 nights against 3, "Likely helps" needs every remedy night to
beat every baseline night (p = 1/20), which is a deliberately high bar for so little data.

The summary sentence names the clearest winner, for example "Sleeping on your side cut your snoring by
about 40% over 4 nights.", and stays cautious otherwise ("…might help…, but it's too early to be sure",
"None of the remedies you've tried has made a clear difference yet").

**The plan.** 3 baseline nights, then 3 nights each of up to 3 remedies picked in onboarding (up to 12
nights). Nights count toward the step that matches their remedy, so an off-plan night is never wasted.
The home screen always suggests the first unfinished step.

## Privacy

- Sound is classified on the device by Apple's built-in model. Nothing is uploaded; the app makes no
  network calls and has no accounts or analytics.
- Raw audio is never written to disk unless you turn on **Save snore clips**. Then at most 10 clips of
  10 seconds per night are saved in the app's Application Support folder, excluded from iCloud backup.
  Without clips, audio exists only in memory for the moment it takes to classify it.
- Stored data is limited to nights, events and remedies. Export it as CSV (nights and events) from
  Settings, or delete everything there.

## Tests

`SnoreGuardTests` covers:

- `EventMerger`: overlap merging, the 10 s gap rule at its boundary, the 3 s minimum, threshold
  inclusiveness, peak confidence, unsorted input, incremental counting.
- `NightTotals` / `Night`: per-hour normalization, zero-length recordings, the 60 min/h cap, the 30
  minute rule.
- `RemedyAnalyzer` / `Statistics`: every label including both not-enough-data cases, the exact and
  Monte Carlo permutation p-values, and every summary sentence.
- `PlanEngine`: progress, suggestions, off-plan nights, completion, demo vs. real plan.
- `DemoData`: the demo tells the intended story (side sleeping "Likely helps", nasal strip "Might help",
  extra pillow "Not enough data yet", "Night 11 of 12").
- `FileSnoreDetector`: runs the real SoundAnalysis pipeline over the bundled recording and a generated
  tone (which must produce no snore events).
- `CSVExporter`: escaping and contents.

CI (`.github/workflows/snoreguard-ios.yml`) generates the project and fails on any warning or error in
the project's sources. One job builds and runs the tests on an iPhone simulator, using the first Xcode on
the runner that has one installed (Xcode 26.1 at the time of writing); a second job compiles the app and
tests with Xcode 16.

## Known limitations

- **One microphone can't tell whose snoring it hears.** A partner's snoring counts as yours. Sleeping
  alone gives the cleanest results.
- **The phone must stay plugged in.** Listening all night uses a lot of battery, and iOS may end the
  session if the battery runs low.
- **iOS decides what runs in the background.** Recording continues with the screen locked, but if
  another app takes over audio while SnoreGuard is in the background, iOS may not let it resume until
  you return to the app (it retries automatically, and resumes as soon as the app is opened).
- **Apple's classifier isn't perfect.** Breathing, a fan or a TV can occasionally score as snoring, and
  quiet snoring can be missed. Sensitivity trades one for the other.
- **The bundled sample is synthetic.** It was generated by `Tools/make_sample_audio.py` (no real
  recording was available). Apple's model does score it as snoring (peak confidence 0.84, both snoring
  stretches found as events), but a real night is the honest test: import one.
- **Small numbers.** A few nights can't prove much; the labels say so rather than overclaim.
- iPhone only, portrait only, English only.

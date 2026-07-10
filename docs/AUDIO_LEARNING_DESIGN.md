# Audio Learning — Capture · Transcribe · Play (design proposal)

**Status:** draft for Ruby's review. Extends the real-world learning pivot
(PIVOT_PLAN.md) with a second capture modality: **audio**. A recorded
conversation / video soundtrack becomes a *source in the Library*, its
transcript becomes *sentences*, and the entire downstream loop (translate → AI
breakdown → save → review → shadow) is reused unchanged.

## 1. The idea in one line

Book source: **photo → OCR → text → TTS playback**.
Audio source: **recording → on-device transcription → text → real-audio playback**.

Both are the *same* thing to the rest of the app — a `Book` (source) whose
child unit holds the captured media and whose `Sentence`s carry the learnable
text. Only two axes are genuinely new:

1. **Capture is audio**, not a camera frame.
2. **Playback is the original recording seeked by timestamp**, not synthesized
   speech — with karaoke highlighting driven by *real* transcript timings.

Everything else already exists and is reused.

## 2. Reframing "watch YouTube / talk to a person" under the offline rule

The app is **fully offline, no networking ever** (DECISIONS #31, CLAUDE.md).
That rules out downloading YouTube/streaming audio. The workable, offline
capture paths that cover the user's intent:

- **Live microphone recording** — a real conversation, a class, or *holding the
  phone toward a speaker while a video plays*. This is the primary path.
- **Import a local audio/video file** — from Files / the share sheet (e.g. a
  saved voice memo, a downloaded lecture, a video clip). Video → extract the
  audio track locally (AVFoundation). No network.

We set this expectation in the capture UI ("Record what you hear, or import a
clip"). Direct YouTube ingestion is explicitly out of scope while the
no-networking rule stands (revisit only under the DECISIONS #31 cloud opt-in).

## 3. How it maps onto today's model (maximal reuse)

| Concept | Book source (today) | Audio source (new) | Reused? |
|---|---|---|---|
| Library entry | `Book(kind: .book/.sign/…)` | `Book(kind: .conversation)` | ✅ model + shelf |
| Capture unit | `ScanPage(imageData)` | `ScanPage(audioData)` | ✅ same model, new field |
| Learnable text | `Sentence.text` (from OCR) | `Sentence.text` (from transcript) | ✅ `SentenceSplitter` |
| Playback | `SpeechPlayer` (TTS) | `RecordingPlayer` (seek real audio) | 🔶 new impl, shared protocol |
| Translate / breakdown / save / SRS / shadow | — | — | ✅ verbatim |

**Recommendation:** generalize `ScanPage` into "the captured unit" rather than
introduce a parallel model. The pivot already rejected renaming `Book`→`Source`
for cost (DECISIONS #34); the same logic says don't fork `ScanPage`. A unit is
*either* an OCR page (`imageData`) *or* an audio clip (`audioData`). Naming debt
("ScanPage" for audio) is accepted and noted; a future rename to `SourceUnit`
is a separate mechanical migration if it ever earns its keep.

*Alternative considered & rejected:* a new `AudioClip` @Model sibling — cleaner
name, but forks the Book→unit→Sentence loop, the Reader, resume, and ordering
into two code paths for a cosmetic win.

## 4. Schema V5 (freeze V4; all additions optional → lightweight)

Per DECISIONS #35 every @Model change freezes the prior version and adds a
lightweight stage. Current live = V4. Add **V5**:

- `ScanPage.imageData: Data` → **`Data?`** (nil for audio units).
- `ScanPage.audioData: Data?` `@Attribute(.externalStorage)` — the recording.
  (External storage keeps the blob out of the main store file, exactly like
  `imageData` today, so minutes-long clips don't bloat the DB.)
- `ScanPage.audioDuration: Double?` — total clip length (seconds).
- `Sentence.audioStart: Double?`, `Sentence.audioEnd: Double?` — the segment's
  offsets into the parent clip. **`audioStart == nil` ⇒ play via TTS; non-nil ⇒
  play the real recording.** This single flag routes the whole playback choice.
- `SourceKind` gains `.conversation` — a *code* enum case over the existing
  `kindRaw: String`, so it adds **no** schema fingerprint change; only the
  `@Model` field edits above force V5.
- *(deferred to a later version)* compact per-word timings for word-level
  karaoke — see §9.

Migration: freeze `ReadAloudSchemaV4` snapshot, live models become
`ReadAloudSchemaV5`, add `.lightweight(V4→V5)`, and
`MigrationTests.v4StoreMigratesToV5` replays a V4 store (all new fields optional,
so no data written on upgrade).

## 5. New services (UI-free, injectable — CLAUDE.md library rule)

### 5.1 `Transcribing` — audio → timestamped text (offline)
```
protocol Transcribing {
    func transcribe(fileURL: URL, locale: String,
                    progress: (@Sendable (Double) -> Void)?) async throws -> Transcript
}
struct Transcript { let segments: [TranscriptSegment]; let detectedLocale: String? }
struct TranscriptSegment { let text: String; let start: Double; let duration: Double }
```
- Baseline impl `OnDeviceTranscriber` over **`SFSpeechRecognizer` +
  `SFSpeechURLRecognitionRequest`** with **`requiresOnDeviceRecognition = true`**
  (audio never leaves the device — upholds #31). Availability-gated via
  `supportsOnDeviceRecognition`, exactly like the Foundation Models provider.
- **Long-audio chunking:** windowed recognition (~30–60 s slices), offset each
  window's timestamps, stitch — SFSpeech single-utterance limits otherwise
  truncate long clips.
- Language: confirm/auto-set via `NLLanguageRecognizer` over the joined text
  (same trick as OCR's `detectedLanguageCode`).
- **Enhancement path (availability-gated):** iOS 26 `SpeechAnalyzer` /
  `SpeechTranscriber` for robust long-form on-device transcription — same
  protocol, better engine when present.

### 5.2 `RecordingPlayer` — real-audio sentence playback
- Wraps `AVAudioPlayer` on the clip's audio; `play(sentenceAt:)` seeks to
  `audioStart`, plays to `audioEnd` (timer-gated, mirroring `SpeechPlayer`'s
  sentence stepping), auto-advances. `enableRate`/`rate` gives the same
  0.5×–2.0× control; "Slow" works natively.
- **Shared `SentencePlaying` protocol** extracted from `SpeechPlayer`'s surface
  (`load`, `play(at:)`, `stop`, `pause`, `rate`, current-index + highlight
  callbacks). Both `SpeechPlayer` (TTS) and `RecordingPlayer` conform; the
  Reader depends on the protocol and never branches on source kind beyond
  picking the implementation.
- **Shared `AudioSessionCoordinator`** extracted from `SpeechPlayer` (category
  setup + interruption/route-change handling, `isJumping`) so both players and
  `VoiceRecorder` share one audio-session story.

### 5.3 `AudioFileStore` (thin)
Writes captured/imported audio to a managed dir, hands `RecordingPlayer` a URL
(or reads the SwiftData external blob to a temp file). Cascade-deletes with the
`ScanPage`.

## 6. Capture flow (parallel to `ScanFlowView`)
- `AudioCaptureView` — `AVAudioRecorder` to `.m4a`, live level meter/waveform,
  start/stop/cancel. Reuses the **existing mic permission** (already declared
  for shadowing) via a `MicAuthorizer` mirroring `CameraAuthorizer`.
- **Import** — `.fileImporter` for `public.audio` + `public.movie`; video → pull
  the audio track with `AVAssetExportSession`/`AVAssetReader` to `.m4a`. Offline.
- Both hand a file URL to transcription → review.

## 7. Transcribe + review (parallel to `OCRReviewView`)
`TranscriptionReviewView` between transcription and persist:
- Editable transcript (`TextEditor` prefilled), **source-language picker**
  (prefilled from the recognizer/NL detection, correctable), **translate-to**
  picker (incl. None), a **mini scrubber to play the original audio**, Use/Retake.
- On **Use**: `SentenceSplitter` splits the edited text; each sentence maps to a
  `[start,end]` from the segment timings (by segment order); persist a
  `ScanPage(audioData)` + `Sentence`s carrying `audioStart/End`; set
  `Book.kind = .conversation`, `languageCode` = confirmed. Nothing persists
  until Use (matches OCR review contract, DECISIONS #22).
- **Edit-vs-timing caveat:** heavy text edits can drift from timestamps; we keep
  best-effort segment→sentence mapping and document the limit (light edits fine).

## 8. Library + learning-loop integration (mostly free)
- `SourceKind.conversation` gets a `tint` + `systemImage` ("waveform"). The
  **bookshelf we just built** renders audio sources through the existing
  *generated-cover* path automatically (no photo → serif title + waveform icon
  in the kind tint). Only the enum mapping is new.
- Reader plays real audio with karaoke synced to timestamps; speed + "Slow" +
  interruptions reuse §5.2. Translations stay visual-only; a saved word's
  "hear it" still uses TTS (`SpeechPlayer.speakOnce`) since an isolated word may
  lack clean audio — both players coexist.
- **Shadowing gets better:** comparing your take to the *real speaker* (not TTS)
  is the natural payoff of audio sources; `VoiceRecorder` + `ShadowingPracticeView`
  already exist. Sets up PIVOT_PLAN §7 pronunciation-compare.
- Capture-session digest mirrors the scan digest ("Saved this session…").

## 9. Risks & spikes (mirror the OCR/LearnSpike discipline)
1. **Transcription accuracy + timestamp fidelity — the #1 gate.** Build
   `Tools/TranscribeSpike` (macOS CLI): run on-device `SFSpeechRecognizer` over
   real French clips in `Fixtures/audio/`, measure WER + timestamp drift; gate
   implementation on a usable bar, exactly like the OCR accuracy gate.
2. **Long-audio limits** — validate chunking + timestamp stitching; keep the iOS
   26 `SpeechAnalyzer` upgrade path.
3. **Edit↔timing desync** — best-effort mapping; documented.
4. **Diarization** ("another person") — on-device speaker separation is weak;
   **MVP = no speaker labels**; 2-speaker heuristic is an enhancement.
5. **Word-level karaoke** — sentence-level highlight first; word-level from
   stored segment timings is a later schema bump.
6. **Disk** — external-storage blobs + cascade delete; surface total audio size.

## 10. Phasing (gated, PIVOT-style)
- **Phase 0 — Spikes (BLOCKING):** `TranscribeSpike` accuracy/timing gate;
  chunking decision; V5 shape sign-off. *(Same discipline as the OCR gate.)*
- **Phase 1 — Schema V5 + `AudioFileStore`:** freeze V4; optional `imageData`;
  `audioData/audioDuration`; `Sentence.audioStart/End`; `.conversation`;
  migration + `MigrationTests`.
- **Phase 2 — Capture:** `AudioCaptureView` (record) + file/video import + audio
  extraction; `MicAuthorizer`.
- **Phase 3 — Transcribe + Review:** `OnDeviceTranscriber` (gated, chunked) +
  `TranscriptionReviewView` → persist sentences with timings.
- **Phase 4 — Playback:** extract `SentencePlaying` + `AudioSessionCoordinator`;
  build `RecordingPlayer`; wire the Reader (karaoke/speed/interruptions).
- **Phase 5 — Library + loop + digest:** `.conversation` in the shelf; reuse
  learn/translate/save/review; shadowing-vs-real-speaker; capture digest.
- **Phase 6 — Enhancements:** word-level karaoke, diarization, iOS 26
  `SpeechAnalyzer`, pronunciation-compare (PIVOT §7).

Acceptance samples: *a 30 s French clip transcribes on-device offline into ≥1
sentence with a playable time range; the Reader plays the real audio and
karaoke-highlights in sync; a V4 store opens under V5 with no data loss; airplane
mode changes nothing.*

## 11. Permissions / privacy
- Add `NSSpeechRecognitionUsageDescription`; **force on-device recognition**
  (never fall back to Apple's servers — that would break #31). Mic already
  declared. If on-device recognition is unavailable for a locale, block with a
  clear message rather than going online.

## 12. Open questions for Ruby
1. **Capture priority** — live mic *and* file import in the MVP, or mic first?
2. **Speaker labels** in v1, or defer diarization? (proposed: defer)
3. **Karaoke granularity** — sentence-level first, word-level later? (proposed: yes)
4. **One clip per source** vs multi-clip sources like multi-page books?
   (proposed: 1 clip = 1 source for MVP)
5. **Language scope** — French-first like the rest? (proposed: yes)

# ReadAloud — TTS / Audio Subsystem Design (SpeechPlayer evolution)

*Purpose: `SpeechPlayer` already does the hard visible part — word-level highlight via `willSpeakRangeOfSpeechString` driving `ReaderView.SentenceCard` — but it is fragile everywhere the OS touches audio: the session is never deactivated, interruptions and route changes are unhandled, speed changes only apply to the next utterance, voice selection is a blind `AVSpeechSynthesisVoice(language:)`, and the `isJumping` flag is an implicit state machine nobody may break. This doc formalizes that state machine and designs the session lifecycle, interruption/route handling, background audio, lock-screen controls, mid-utterance speed change, and voice selection — building on the existing highlight pipeline, never redesigning it.*

**Reads with:** [PROJECT_PLAN.md](../PROJECT_PLAN.md) §4.3/§5.4 (Reader screen, SpeechPlayer contract) · [ARCHITECTURE.md](ARCHITECTURE.md) §2/§4 (current contracts, gaps 3 and 8).

## 1. Playback state machine (formalizing `isJumping`)

Today three fields (`isSpeaking: Bool`, `currentSentenceIndex: Int?`, `isJumping: Bool`) encode four legal states plus illegal combinations. Latent hazard in current code: `stop()` sets `isJumping = true` unconditionally — if the synthesizer wasn't speaking, no `didCancel` arrives to clear it, and the flag lingers until the next `play(at:)` happens to reset it. Replace the bools with one enum:

```swift
enum PlaybackState: Equatable {
    case idle                      // nothing loaded/queued; session may be deactivated
    case speaking(index: Int)      // utterance in flight, highlight updating
    case paused(index: Int, resume: ResumeMode)     // see ResumeMode below
    case jumping(target: Int, resumeOffset: Int?)   // stopSpeaking issued, waiting for didCancel;
                                                    // non-nil offset = §5 mid-sentence restart point
}
enum ResumeMode: Equatable {
    case `continue`   // user toggle-pause: synthesizer pause state is trustworthy
    case replay       // interruption/route loss/suspension: synth + session unreliable → play(at:)
}
extension PlaybackState {          // the one helper §3–§5 handlers and the v2 surface derive from
    var currentIndex: Int? {
        switch self {
        case .idle: nil
        case .speaking(let i), .paused(let i, _), .jumping(let i, _): i
        }
    }
}
```

```
                      play(at: i)
        ┌────────────────────────────────────┐
        ▼                                    │
   ┌─────────┐  play(at:) [synth idle]  ┌────┴────┐
   │  idle   │ ────────────────────────►│speaking │◄──┐
   └─────────┘                          │  (i)    │   │ didFinish → play(at: i)   [repeatMode]
        ▲                               └─┬─┬─┬───┘   │ didFinish → play(at: i+1) [i+1 < count]
        │ stop() from any state → idle    │ │ └───────┘
        │ (incl. ReaderView.onDisappear;  │ │ toggle → pauseSpeaking(.word) → paused(i, .continue)
        │  stray didFinish/didCancel      │ │ interruption .began / route loss / suspension
        │  arriving in idle: no-op)       │ │   → paused(i, .replay)
        │                                 │ ▼ didFinish [last i, !repeatMode]
        │                               ┌─┴──────────┐   → paused(i, .replay) + deactivate (§2)
        │                               │ paused     │ toggle [.continue] → continueSpeaking → speaking(i)
        │                               │ (i,resume) │ toggle [.replay] → play(at: i)  (reactivates §2)
        │                               └─┬──────────┘ interruption .began [.continue] → paused(i,.replay)
        │                                 │            play(at:)/next()/previous() → jumping
   ┌────┴──────┐                          │
   │ jumping   │◄─────────────────────────┘
   │ (target,  │◄── play(at: j) / next / previous / speed-change while speaking(i)
   │  offset?) │    (stopSpeaking(.immediate) first; interruption while jumping
   └───────────┘     → paused(target, .replay), pending utterance dropped)
        └── didCancel → speak target (tail from resumeOffset if set, §5) → speaking(target)
```

Rules the diagram encodes (the invariants `didFinish` auto-advance depends on):

- `didFinish` performs auto-advance **only** from `speaking`; in `jumping` the terminal callback is `didCancel`, which never advances — it speaks the pending target.
- Every `stopSpeaking` call must first transition to `jumping` (pending target) or `idle` (plain `stop()`), so a stray `didFinish`/`didCancel` can never double-advance. **`didCancel` (and `didFinish`) arriving in `idle` is an explicit no-op** — that's the inevitable trailing callback after stop-while-speaking, not an error.
- `paused` keeps `currentSentenceIndex`; `idle` clears it. `highlightRange` is non-nil only in `speaking`.
- `resume` records *why* we paused. `.continue` (user toggle) resumes mid-word via `continueSpeaking()`. `.replay` (interruption, route loss, app suspension) means the synthesizer's paused state and the audio session are both unreliable, so `togglePlayPause()` **must route through `play(at: i)`** — never `continueSpeaking()`, which would be a silent no-op on a synthesizer that was never truly paused.
- An interruption or route change arriving in `jumping` drops the pending utterance and parks the target: `paused(index: target, resume: .replay)`. An interruption `.began` arriving in `paused(i, .continue)` **demotes it to `paused(i, .replay)`** — pause keeps the session active (§2), so a phone call during a pause tears it down under us, and a later `.continue` resume would be the silent no-op above. `.began` in `paused(_, .replay)` or `idle` is a no-op.
- Natural end of page (`didFinish` on the last sentence, repeat off) lands in **`paused(lastIndex, .replay)`, not `idle`**, and deactivates the session (§2). The last card stays selected and toggle replays the last sentence — exactly today's behavior (`SpeechPlayer.didFinish` keeps `currentSentenceIndex`). `idle` is reached only via `stop()`.

*Trade-off:* single enum vs. keeping the bools — enum chosen; it makes illegal states unrepresentable and turns delegate callbacks into a `switch` the compiler audits. Rejected: keeping `isJumping` with more comments (that's how the `stop()` bug above survived review).

Public surface (v2) — `ReaderView` keeps compiling via derived properties:

```swift
@MainActor   // delegate callbacks arrive on main; §3/§4 notification handlers must hop here too
@Observable final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var state: PlaybackState = .idle
    var currentSentenceIndex: Int? { state.currentIndex }
    var isSpeaking: Bool { if case .speaking = state { true } else { false } }
    private(set) var highlightRange: NSRange?          // full-sentence UTF-16 coords
    private(set) var voice: AVSpeechSynthesisVoice?    // resolved by VoiceCatalog (§6)
    private(set) var audioIssue: AudioIssue?           // .noVoice(String), .sessionFailed
    var speedMultiplier: Float { didSet { applySpeedChange() } }   // §5
    var repeatMode: Bool = false                                   // §9

    func load(sentences: [String], languageCode: String)
    func play(at index: Int)
    func togglePlayPause()
    func next(); func previous(); func stop()
}
```

## 2. AVAudioSession lifecycle

- **Category/mode:** `.playback` + `.spokenAudio`, set once at init (as today). `.playback` so the silent switch doesn't mute a listening app; `.spokenAudio` declares audiobook-like content so the system applies spoken-audio interruption behavior (e.g. other spoken audio pauses rather than ducks us). *Trade-off:* default non-mixing chosen over `.interruptSpokenAudioAndMixWithOthers` — learners need to hear words clearly over silence, not over their music.
- **Activate:** lazily inside `play(at:)` whenever entering `speaking` from a state where the session may be inactive — `idle`, **or `paused(_, .replay)`** (after an interruption/route loss/end-of-page the system or §2 itself has deactivated us; this is exactly why those pauses are `.replay`). Not on every sentence — activation is not free and today's per-utterance `setActive(true)` is wasted work. If `setActive` throws, set `audioIssue = .sessionFailed` and don't change state; `ReaderView` shows an inline warning row (§8) and the next play tap re-attempts activation.
- **Deactivate:** `setActive(false, options: .notifyOthersOnDeactivation)` on `stop()` (incl. `ReaderView.onDisappear`) and on natural end-of-page `didFinish` (which lands in `paused(last, .replay)` per §1). **Not** on user-toggle pause (`.continue`): resume must be instant and we keep audio focus mid-session. Do **not** call `setActive(false)` synchronously inside the `didFinish` callback — the output is often still tailing off and the call can throw or block; hop to a utility queue (or defer ~0.5 s) and treat a throw as non-fatal (log, keep state). *Trade-off:* "never deactivate" (current behavior) rejected — it holds audio focus forever, so the user's podcast never resumes after they leave the Reader. `.notifyOthersOnDeactivation` is what makes the podcast resume.

## 3. Interruptions (phone call, Siri, alarms, other apps)

Observe `AVAudioSession.interruptionNotification` in `SpeechPlayer.init` (paired `NotificationCenter` removal in `deinit`). **Threading:** `AVAudioSession` posts its notifications on a secondary thread, but the handler mutates `@Observable` state that SwiftUI reads and drives the synthesizer — register with `NotificationCenter.default.addObserver(forName:object:queue: .main)` (or wrap the body in `Task { @MainActor in … }`) so every handler runs on the main actor, same as the delegate callbacks. This applies to §4's route-change observer too.

```swift
@MainActor private func handleInterruption(_ note: Notification) {
    switch note.interruptionType {                    // parsed from userInfo
    case .began:
        switch state {                                // system already halted audio
        case .speaking(let i), .jumping(target: let i, _):
            state = .paused(index: i, resume: .replay)
        case .paused(let i, .continue):               // §1: session torn down under the pause
            state = .paused(index: i, resume: .replay)
        default: break                                // idle / already .replay: no-op
        }
    case .ended:
        guard case .paused(let i, .replay) = state,
              note.options.contains(.shouldResume) else { return }
        play(at: i)                                   // replay whole sentence (reactivates §2)
        // no .shouldResume: stay paused; play button resumes manually
    default: break
    }
}
```

No stored `interruptedIndex` field — the index lives in the `paused` case itself, so a `stop()` during the interruption goes to `idle` and a trailing `.ended` finds nothing to resume (a parallel field would go stale here and replay a dead index).

**Explicit resume rules:** auto-resume only when the system passes `.shouldResume` (short interruptions: Siri, calls the user declined); otherwise remain `paused` and let the user resume. On resume, **replay the interrupted sentence from its start** rather than `continueSpeaking()`. *Trade-off:* replay-from-start chosen over mid-word continue — after an interruption the synthesizer's paused state is unreliable (the session was torn down), and for a language learner re-hearing one full sentence is a feature, not a cost. Rejected: resuming at `lastWordStart` (§5 machinery would allow it) — not worth the edge cases for a ≤1-sentence loss.

## 4. Route changes (headphones unplugged)

Observe `AVAudioSession.routeChangeNotification` (main-actor hop per §3); on reason `.oldDeviceUnavailable`, pause (platform convention: never blast a train carriage from the speaker):

```swift
case .oldDeviceUnavailable:
    guard case .speaking(let i) = state else { break }
    synthesizer.pauseSpeaking(at: .immediate)     // .immediate: the output route is already gone
    state = .paused(index: i, resume: .replay)    // §1: route died mid-word → replay, never continue
```

New-device-available (`.newDeviceAvailable`, e.g. AirPods connected) does nothing — auto-starting audio on connect is hostile. No other reasons handled in v1.

## 5. Mid-utterance speed change — restart at last word boundary (DECIDED)

Current gap: `speedMultiplier` is read once when the utterance is built, so moving the picker mid-sentence silently does nothing until the next sentence. **Decision: restart the current utterance at the last spoken word boundary with the new rate.** Rejected alternative: apply-on-next with a "takes effect next sentence" UI hint — the hint explains the bug instead of fixing it, and speed fiddling happens precisely while replaying a hard sentence.

Mechanism (this is also the reason `highlightRange` gets an explicit coordinate rule):

```swift
private var utteranceBaseOffset: Int = 0   // UTF-16 offset of utterance start in full sentence
private var lastWordStart: Int = 0         // full-sentence coords, from willSpeakRange…

func applySpeedChange() {
    switch state {
    case .speaking(let i):
        state = .jumping(target: i, resumeOffset: lastWordStart)  // consumed in didCancel
        synthesizer.stopSpeaking(at: .immediate)                  // → didCancel → speak tail substring
    case .paused(let i, .continue):
        state = .paused(index: i, resume: .replay)  // continueSpeaking() would keep the OLD rate for
                                                    // the rest of the utterance; .replay forces the next
                                                    // toggle through play(at:), rebuilt at the new rate
    default: break                                  // idle / .replay / jumping: next play(at:) picks it up
    }
}
```

`didCancel` for a jump with non-nil `resumeOffset` builds the utterance from `String(sentence[utf16 offset...])`, sets `utteranceBaseOffset = offset`, and speaks at the new rate; `resumeOffset == nil` (every ordinary jump) speaks the full sentence. Because the offset lives **inside** the `jumping` case, a retarget mid-flight (user taps another card, next/previous) replaces the whole state with `.jumping(target: j, resumeOffset: nil)` — a stale offset from an abandoned speed change is unrepresentable. Every incoming `willSpeakRangeOfSpeechString` range is rebased: `highlightRange = NSRange(location: characterRange.location + utteranceBaseOffset, length: characterRange.length)`. Normal `play(at:)` resets `utteranceBaseOffset = 0`. `currentSentenceIndex` never changes during the restart, so the card, star, and auto-scroll are untouched. *Note:* the `paused(_, .continue)` branch trades mid-word resume for rate correctness — resume replays the sentence from the start, consistent with §3's replay trade-off.

## 6. Voice selection

New pure service, `Services/VoiceCatalog.swift` (no state, trivially testable):

```swift
enum VoiceCatalog {
    /// All installed voices for a BCP-47 code, best quality first (premium > enhanced > default).
    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice]
    /// Fallback chain below; nil only if the device has no voice for the 2-letter language at all.
    static func resolve(languageCode: String, preferredIdentifier: String?) -> AVSpeechSynthesisVoice?
}
```

**Fallback chain** (first hit wins):
1. `preferredIdentifier` if that voice is still installed (voices can be deleted in iOS Settings).
2. Exact BCP-47 match, highest `AVSpeechSynthesisVoiceQuality` (top-level enum, not nested in `…Voice`; its raw values already order `.default` < `.enhanced` < `.premium`, so sort by `quality.rawValue` descending).
3. Same 2-letter language prefix, highest quality (a `fr-CA` premium voice beats silence for `fr-FR`).
4. `AVSpeechSynthesisVoice(language: languageCode)` (system pick; today's behavior).
5. `nil` → `SpeechPlayer.audioIssue = .noVoice(languageCode)`; Reader shows the warning row (§8) and speaks with the system-default voice rather than refusing to play.

**Persistence: `@AppStorage("voice.<languageCode>")` storing the voice `identifier`, one key per language.** *Trade-off:* rejected a `Book.preferredVoiceIdentifier` SwiftData attribute — installed voices are a per-device fact, and a device-local identifier inside exportable book data would dangle after restore/JSON export. So: **no SwiftData schema change for audio.** Rate default stays `@AppStorage("defaultSpeed")` per plan §4.6.

Voice picker (Phase 3, lives in Settings; also reachable from Reader's `[⋯]` menu):

```
┌──────────────────────────────┐
│ ← Settings   Voice: French   │
├──────────────────────────────┤
│ ◉ Thomas      Enhanced   ▶︎  │   ▶︎ = preview: speaks one fixed
│ ○ Aurélie     Premium    ▶︎  │       sample sentence via a
│ ○ Compact fr  Default    ▶︎  │       throwaway synthesizer
├──────────────────────────────┤
│ ⓘ Get higher-quality voices  │ → deep link: App-Prefs is private;
│   in iOS Settings → Accessi- │   show instructions text instead
│   bility → Spoken Content    │   (plan §4.6 "link" ≈ instructions)
└──────────────────────────────┘
```

Quality label comes straight from `voice.quality`; the footer row appears only when no `.enhanced`/`.premium` voice exists for the language (plan risk: "system TTS quality varies").

Picker semantics an implementer must not guess:
- **Which language:** opened from a Book/Reader → that Book's `languageCode`; opened from Settings → the target-language setting (`@AppStorage("targetLanguage")`, plan §4.6). One picker per language, never a merged list.
- **Preview vs. Reader playback:** opening the picker from Reader's `[⋯]` menu first pauses playback (`togglePlayPause()` if speaking); the ▶︎ preview stops any in-flight preview before starting. Sample text: one fixed sentence per 2-letter language from a small inline table (fallback: the language's display name spoken by the candidate voice). Never two synthesizers audible at once.
- The §8 missing-voice row navigates to this picker (Settings destination) for the Book's language — "instructions" in the footer are what the row lands on.

## 7. Background audio, Now Playing, remote commands — Phase 4 (DECIDED)

**Today:** no `audio` background mode → when the screen locks mid-sentence the app suspends, `AVSpeechSynthesizer` halts mid-word, and on unlock the state machine is in `speaking` with no audio — a lie. **Interim Phase 2/3 fix — foreground reconciliation:** on return to foreground (`scenePhase == .active`), if `case .speaking(let i) = state` but `synthesizer.isSpeaking` is false, demote to `paused(i, .replay)` — one tap of ▶ then resumes correctly. This is the mechanism, because delegate callbacks and notifications are *not* delivered while suspended and whether a `didCancel` arrives on unlock is unverified (open question 3); if one does arrive, §1 already routes it to `paused(i, .replay)` as an optimization.

**Change:** add the background mode in `project.yml` (never the .xcodeproj — regenerate with `xcodegen generate`):

```yaml
targets:
  ReadAloud:
    info:
      path: ReadAloud/Info.plist
      properties:
        UIBackgroundModes: [audio]
```

(Existing `INFOPLIST_KEY_*` build settings merge into this generated plist; verify camera-usage string survives in the built product.) **After:** with the session active, lock mid-sentence and speech continues; `didFinish` auto-advance keeps firing in the background because `SpeechPlayer` needs no UI to advance — which is exactly what **continuous page playback** (plan Phase 4) needs. `highlightRange` keeps updating invisibly; harmless.

**Now Playing + lock-screen controls ship in the same change:** `MPNowPlayingInfoCenter` (title = current sentence, album = book title, `MPNowPlayingInfoPropertyPlaybackRate` = 1/0 on play/pause) and `MPRemoteCommandCenter` (`playCommand`/`pauseCommand` → `togglePlayPause()`, `nextTrackCommand`/`previousTrackCommand` → `next()`/`previous()`; skip-15s commands disabled — sentences, not time, are the unit).

**Phase decision: all of §7 lands in Phase 4, bundled with continuous page playback.** *Trade-off:* Phase 3 rejected — the core loop is eyes-on-the-physical-book with the phone in view (foreground by definition); background audio only earns its review burden when a whole page can play unattended. Background audio without lock-screen controls is a dead lock screen, and remote commands without background audio never fire — they are one feature, one phase.

## 8. Explicit state / error handling (Reader + audio)

| Condition | Detection | UX |
|---|---|---|
| Empty sentence list | `sentences.isEmpty` on load | Reader shows "Nothing to read" placeholder; playback bar disabled (today: silent no-op) |
| No voice for language | `VoiceCatalog.resolve` → nil at `load` | Amber inline row above playback bar: "No French voice installed — using default" → navigates to the §6 voice picker for the Book's language |
| Session activation failed | `setActive` throws | `audioIssue = .sessionFailed`; same amber inline row pattern: "Audio unavailable — try closing other audio apps". Persistent while `audioIssue != nil`; each play tap re-attempts activation (§2) and success clears the row. (No toast — the app has no toast component and a transient message is wrong for a persisting failure.) |
| Interruption, no `.shouldResume` | §3 | Stays `paused`; play button shows ▶; card stays highlighted at interrupted sentence |
| Headphones unplugged | §4 | Pauses; no banner (expected behavior) |
| Page finished (last `didFinish`, repeat off) | §1 | `paused(lastIndex, .replay)`, session deactivated; last card stays selected, ▶ replays the last sentence, next disabled, prev enabled — matches today |
| Loading / permission-denied | n/a for audio | OCR/camera concerns — owned by Scan flow, unchanged here |

**Accessibility (plan §9: "VoiceOver-navigable Reader screen"):**
- Playback bar: `accessibilityLabel` on every control — play/pause reflects state ("Pause"/"Play"), repeat toggle uses `.isSelected`, speed picker exposes its value ("Speed, 0.75×"); prev/next are "Previous sentence"/"Next sentence".
- Amber rows and the "Nothing to read" placeholder are announced when they appear (`AccessibilityNotification.Announcement` on `audioIssue` change), not just visually inserted.
- Voice picker rows read "«name», «quality», selected"; preview buttons are "Preview «name»".
- **VoiceOver + TTS coexistence:** `AVSpeechSynthesizer` output and VoiceOver speech contend for spoken audio; sentence playback is deliberate user-initiated content (like an audiobook app), so we do not duck or suppress it — but VoiceOver focus moves must not auto-trigger card playback (play only on double-tap activate, never on focus). Test the Reader end-to-end with VoiceOver on; note residual overlap as a known limitation against plan §9.

## 9. Highlight timing & repeat-mode semantics

- `willSpeakRangeOfSpeechString` fires marginally **before** the audio for that word — that pre-echo is why drift feels < 100 ms (acceptance §9 of the plan). Keep the highlight animation ≤ 150 ms (current `easeOut(0.15)` is fine); longer animation, not callback latency, is what creates perceived drift.
- Ranges are **UTF-16 `NSRange` in the utterance string**; after a §5 mid-utterance restart they must be rebased by `utteranceBaseOffset` or the highlight jumps to the sentence start. `Range(nsRange, in: AttributedString)` already guards composed-character misalignment — keep that guard.
- Compact (`.default`) voices in some languages report coarse ranges (phrase-sized, or none for ja/zh) — another reason §6 prefers enhanced/premium and surfaces the download hint. Do not "fix" coarse ranges with timers; show what the engine reports.
- **Repeat mode:** loops the current sentence indefinitely on `didFinish` (as today), now with `utterance.postUtteranceDelay = 0.4` when `repeatMode` is on, giving shadowing learners a breath between repetitions. `next()`/`previous()`/tap moves the loop to the new sentence; repeat stays latched until toggled off. *Trade-off:* "repeat N× then advance" rejected — extra setting, and the learner, not a counter, knows when a sentence is conquered.

## Open questions

1. Should auto-advance insert a short inter-sentence `postUtteranceDelay` (e.g. 0.2 s) even outside repeat mode, for read-along pacing? Needs testing against highlight-drift perception.
2. When Phase 2 wires SwiftData, should `SpeechPlayer` speak `Sentence` models directly (enabling per-sentence bookmark state in Now Playing) or stay `[String]`-based with the view mapping indices? Leaning `[String]` + index mapping to keep the service model-free.
3. Does `pauseSpeaking(at: .word)` + `continueSpeaking()` survive a full app-suspension cycle on iOS 17.4 devices, or is replay-from-sentence-start needed there too (§3 chose replay for interruptions; the toggle path still uses continue)? Needs on-device verification.
4. Review-mode audio (plan §4.5, listen-first flashcards) will reuse `SpeechPlayer` with a 1-element queue — does it need `repeatMode` semantics or a dedicated `speakOnce(_:)` API?

## Carry-forward tasks

- [ ] **Phase 2 — Refactor `SpeechPlayer` to `PlaybackState` enum** — acceptance: all Reader interactions (tap, prev/next, toggle, repeat) behave identically; end-of-page lands in `paused(lastIndex, .replay)` so the last card stays selected and ▶ replays the last sentence (identical to today, per §1); `isJumping`/`isSpeaking` bools deleted; `stop()`-while-idle no longer leaves a stale jump flag.
- [ ] **Phase 2 — Session activate/deactivate lifecycle (§2)** — acceptance: background music resumes (via `.notifyOthersOnDeactivation`) after leaving Reader or finishing the last sentence; user-toggle pause does not release the session; deactivation never runs synchronously inside `didFinish`.
- [ ] **Phase 2 — Interruption observer (§3)** — acceptance: incoming call mid-sentence pauses; declining the call auto-resumes at the start of the interrupted sentence; accepting it leaves the Reader paused for manual resume; a call arriving **while already paused** demotes to `.replay` so the next ▶ replays instead of silently no-oping; all handlers run on the main actor.
- [ ] **Phase 2 — Foreground reconciliation after suspension (§7 interim)** — acceptance: lock the screen mid-sentence, unlock → Reader shows ▶ (paused at the interrupted sentence), one tap resumes; no double-tap-to-resume, no stuck pause icon.
- [ ] **Phase 2 — Route-change observer (§4)** — acceptance: unplugging headphones (or disconnecting AirPods) mid-sentence pauses playback; reconnecting does not auto-play.
- [ ] **Phase 3 — Mid-utterance speed change (§5)** — acceptance: moving the speed picker while a sentence plays restarts it from the last spoken word at the new rate, with the highlight continuing at correct full-sentence offsets; changing speed while paused takes effect on resume (sentence replays from its start at the new rate).
- [ ] **Phase 3 — `VoiceCatalog` + fallback chain + `@AppStorage` voice preference (§6)** — acceptance: deleting the preferred voice in iOS Settings falls back per chain without a crash or silent playback; unit tests cover chain ordering with stubbed voice lists.
- [ ] **Phase 3 — Voice picker UI in Settings with preview + enhanced-voice hint (§6)** — acceptance: picker lists installed voices for the Book's language with quality labels, previews one sample sentence, and shows the download hint only when no enhanced/premium voice exists.
- [ ] **Phase 3 — Reader empty/error states rows (§8)** — acceptance: empty sentence list, missing voice, and failed session activation each render their specified UI instead of a silent no-op; the two amber rows share one component (per repo reuse rule, `Shared/Components/`).
- [ ] **Phase 3 — Reader audio accessibility pass (§8)** — acceptance: every playback-bar control, warning row, and voice-picker row has the specified VoiceOver label/trait; `audioIssue` changes are announced; card playback triggers on activate, not focus; VoiceOver end-to-end run logged with known limitations.
- [ ] **Phase 3 — Repeat-mode `postUtteranceDelay` (§9)** — acceptance: with repeat on, a ~0.4 s gap separates repetitions; with repeat off, auto-advance timing is unchanged.
- [ ] **Phase 4 — Background audio via `project.yml` `info:` block (§7)** — acceptance: locking the screen mid-sentence continues speech and auto-advance to end of page; camera-usage description still present in the built Info.plist after `xcodegen generate`.
- [ ] **Phase 4 — Now Playing info + `MPRemoteCommandCenter` (§7)** — acceptance: lock screen shows current sentence + book title with working play/pause and next/previous-sentence controls; skip-by-time controls are absent.
- [ ] **Tech debt — Unit tests for `PlaybackState` transitions behind a synthesizer protocol** — acceptance: every edge in the §1 diagram has a test, including didCancel-during-jump and didFinish-at-last-sentence; tests run without AVFoundation audio output.

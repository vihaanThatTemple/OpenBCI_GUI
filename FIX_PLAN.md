# Speech Experiment Widget — Bug Fix Plan

> Generated from full branch review of commits `a2173e45..d5618b1d`
> 15 issues identified, ordered by severity. Each fix includes the exact
> file, line numbers, what to change, and why it's safe.

---

## P0 — Critical (breaks existing functionality or causes crashes)

### Fix 1: `controlPanel.open()` calls commented out instead of renamed

**File:** `OpenBCI_GUI/OpenBCI_GUI.pde`
**Lines:** 662, 708

**Problem:** When `controlPanel.open()` was renamed to `controlPanel.openPanel()` in
ControlPanel.pde, two call sites in the error-recovery paths of `initSystem()` were
commented out instead of updated. If board init fails (no Daisy, or `abandonInit`),
the control panel never re-opens — the user is stuck with no way to retry.

**Fix:** Uncomment and rename both lines:
- Line 662: `//controlPanel.openPanel();` → `controlPanel.openPanel();`
- Line 708: `//controlPanel.openPanel();` → `controlPanel.openPanel();`

**Risk:** Zero. This restores the original behavior that existed before the rename.

**Verify:** Launch with no board connected, click Start Session, confirm the control
panel re-opens after the error message.

---

### Fix 2: Microphone unavailable after first session

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 660, 1527-1546, 1578-1585

**Problem:** `initAudio()` runs once in the constructor (line 210). `closeAudio()`
(called from `finalizeSession()` at line 660) nulls `micInput` and never resets
`audioAvailable`. On the second session, `audioAvailable` is still `true` but
`micInput` is `null`, so `startUtteranceAudio()` silently no-ops — no audio is
recorded and the user gets no warning.

**Fix:** Replace `closeAudio()` with a method that releases the current recorder
without destroying the mic input:

```java
// In finalizeSession(), replace:
closeAudio();

// With:
stopUtteranceAudio(); // just stop the recorder, keep mic alive
```

Then modify `closeAudio()` to only be called on true widget teardown (if ever).
The mic input should persist across sessions. `stopUtteranceAudio()` is already
called on line 646 in `endSession()` and is null-safe, so the redundant call in
`finalizeSession()` just becomes the authoritative cleanup.

Alternatively, if you want to keep `closeAudio()` in `finalizeSession()` for
resource hygiene, add a `reinitAudio()` call at the top of `startSession()`:

```java
private void startSession() {
    if (!runPreSessionChecklist()) return;
    if (!audioAvailable && micInput == null) initAudio(); // re-init if closed
    ...
```

**Risk:** Low. Either approach preserves existing behavior for session 1 and fixes
session 2+.

**Verify:** Run two back-to-back sessions. Confirm both produce `.wav` files in
`audio_raw/`.

---

### Fix 3: Start marker recomputed at stop time

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 731-752 (`beginRecording`), 754-786 (`endRecording`)

**Problem:** `endRecording()` at line 762 recomputes `startMarker` from the current
`speakingMode`. If mode changes between start and stop (possible via F9 in single
trial mode, or if a parallel trial phase transition races), the logged `startMarker`
won't match what was actually sent to the board. The session log CSV becomes
inconsistent with the BrainFlow data file.

**Fix:** Add two fields to store state captured at recording start:

```java
// Add near line 155 (Audio Recording section):
private int activeStartMarker = 0;
private int activeRecordingSpeakingMode = MODE_VOCALIZED;
```

In `beginRecording()` (line 742), after computing the marker:
```java
int markerValue = computeMarker(currentSentenceIndex, speakingMode, 1);
activeStartMarker = markerValue;
activeRecordingSpeakingMode = speakingMode;
```

In `endRecording()` (lines 762-763), replace the recomputation:
```java
// Replace:
int startMarker = computeMarker(currentSentenceIndex, speakingMode, 1);
int stopMarker = computeMarker(currentSentenceIndex, speakingMode, 2);

// With:
int startMarker = activeStartMarker;
int stopMarker = computeMarker(currentSentenceIndex, activeRecordingSpeakingMode, 2);
```

Also update the `getSpeakingModeStr()` call in the log entry (line 776) to use
`activeRecordingSpeakingMode` instead of current `speakingMode`:
```java
String modeStr = (activeRecordingSpeakingMode == MODE_SILENT) ? "silent" : "vocalized";
```

**Risk:** Zero. Purely additive fields. No logic changes — just reads stored values
instead of recomputing them.

**Verify:** In single trial mode, start recording, press F9 to toggle mode, then
stop recording. The log entry's `start_marker` should match the actual marker that
was sent when recording began.

---

### Fix 4: `baseline_emg` NameError in export_gaddy.py

**File:** `export_gaddy.py`
**Lines:** 316, 326, 328, 374, 382, 384

**Problem:** In sections 5a (line 308) and 5c (line 368), when `bf_data is None`, the
code skips the `baseline_emg = create_silence_segment(...)` assignment (guarded by
`if bf_data is not None`), but then unconditionally references `baseline_emg.shape[0]`
in `write_info_json` and `write_button_npy`. This raises `NameError`.

**Fix:** Initialize `baseline_emg` before the conditional and use it consistently:

```python
# Section 5a (line ~308), replace the block with:
for mode, out_dir in dir_map.items():
    idx = 0
    mode_counters[mode] = 1

    emg_samples = 0
    if bf_data is not None:
        baseline_emg = create_silence_segment(bf_data, marker_col, config,
                                               duration_sec=5.0, from_start=True)
        np.save(os.path.join(out_dir, f"{idx}_emg.npy"), baseline_emg.astype(np.float32))
        emg_samples = baseline_emg.shape[0]

    baseline_wav = os.path.join(audio_dir, "baseline_start.wav")
    audio_out = os.path.join(out_dir, f"{idx}_audio.flac")
    convert_wav_to_flac(baseline_wav, audio_out)

    write_info_json(os.path.join(out_dir, f"{idx}_info.json"), "", -1, emg_samples)
    write_button_npy(os.path.join(out_dir, f"{idx}_button.npy"), emg_samples)
```

Apply the same pattern to section 5c (line ~368).

**Risk:** Zero. Only changes what happens when `bf_data is None` (which was crashing).

**Verify:** Run `python export_gaddy.py <session_dir>` with no BrainFlow CSV present.
Should complete without error.

---

## P1 — High (data integrity or resource issues)

### Fix 5: Minim instance leaks on widget recreation

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 1529, 1578-1585

**Problem:** `new Minim(ourApplet)` is created in `initAudio()` (constructor) but
never `stop()`'d. If the widget is destroyed/recreated (layout change), the old
Minim instance leaks — it holds onto audio system resources.

**Fix:** Add `minim.stop()` to `closeAudio()`:

```java
private void closeAudio() {
    stopUtteranceAudio();
    if (micInput != null) {
        try { micInput.close(); } catch (Exception e) { /* ignore */ }
        micInput = null;
    }
    if (minim != null) {
        try { minim.stop(); } catch (Exception e) { /* ignore */ }
        minim = null;
    }
    audioAvailable = false;
}
```

**Note:** If Fix 2 changes `finalizeSession()` to NOT call `closeAudio()`, then this
only fires on actual widget teardown, which is correct.

**Risk:** Very low. `minim.stop()` is idempotent.

---

### Fix 6: Session log timestamps are relative, not wall-clock

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 734, 777

**Problem:** `recordingStartTime = millis()` at line 734. The session log CSV stores
`recordingStartTime` and `millis()` as `start_timestamp_ms` / `stop_timestamp_ms`.
These are relative to sketch start (milliseconds since `setup()`), not epoch time.
Anyone analyzing the CSV with external tools or trying to align with BrainFlow
timestamps will get unusable values.

**Fix:** Add an epoch-time field and capture it alongside `millis()`:

```java
// Add near line 120 (Timing section):
private long recordingStartEpoch = 0;
```

In `beginRecording()` (after line 734):
```java
recordingStartTime = millis();
recordingStartEpoch = System.currentTimeMillis();
```

In `endRecording()` (line 777), change the SpeechLogEntry construction:
```java
// Replace:
startMarker, stopMarker, recordingStartTime, millis(), duration, recordingIndex

// With:
startMarker, stopMarker, recordingStartEpoch, System.currentTimeMillis(), duration, recordingIndex
```

**Risk:** Zero. `millis()` is still used for all UI timing and duration calculation.
Only the log file values change to epoch.

**Verify:** Check session_log.csv — timestamps should be ~1.7 trillion (epoch ms)
instead of small numbers.

---

### Fix 7: `sessionId` never auto-increments

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 650-678 (`finalizeSession`)

**Problem:** After a session ends, `sessionId` stays the same. The next session reuses
the ID in both the session log filename and the marker values. Two sessions get
identical metadata.

**Fix:** Add `sessionId++` at the end of `finalizeSession()`, after the summary is
output but before `updateButtonStates()`:

```java
    output(summary);
    sessionId++;
    updateButtonStates();
```

This way the completed session's summary and log file use the correct ID, and the
next session automatically gets the next number.

**Risk:** Very low. The increment happens after all logging/output for the old
session is done.

**Verify:** Run two sessions back-to-back. First session should show "Session 1",
second should show "Session 2" in the header and log filenames.

---

## P2 — Medium (edge cases, robustness, code quality)

### Fix 8: Silent error swallowing in ConsoleLog.pde

**File:** `OpenBCI_GUI/ConsoleLog.pde`
**Line:** 199

**Problem:** `catch (Exception e) {}` silently swallows all errors from the reflection
call. If the Desktop API fails, the user gets no feedback.

**Fix:**
```java
// Replace:
} catch (Exception e) {}

// With:
} catch (Exception e) {
    println("ConsoleLog: Error opening log file - " + e.getMessage());
}
```

**Risk:** Zero.

---

### Fix 9: `periodicBoardTypeCheck()` fragile timing heuristic

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 463-471

**Problem:** `if (millis() - lastStreamCheckTime > 100) return;` is a fragile way to
piggyback on the stream check interval. Frame-rate drops can permanently skip this.

**Fix:** Merge the board type detection into `periodicStreamCheck()` directly:

```java
private void periodicStreamCheck() {
    long now = millis();
    if (now - lastStreamCheckTime < STREAM_CHECK_INTERVAL) return;
    lastStreamCheckTime = now;

    boolean streaming = (currentBoard != null && currentBoard.isStreaming());
    boolean hasMarkerCh = false;
    if (currentBoard instanceof BoardBrainFlow) {
        hasMarkerCh = (((DataSource) currentBoard).getMarkerChannel() != -1);
    }
    markerChannelAvailable = hasMarkerCh;
    streamingWarningActive = sessionActive && !practiceMode && (!streaming || !hasMarkerCh);

    // Board type detection (moved from periodicBoardTypeCheck)
    if (currentBoard != null) {
        String boardName = currentBoard.getClass().getSimpleName();
        isSyntheticBoard = boardName.contains("Synthetic");
        isPlaybackBoard = boardName.contains("Playback");
    }
}
```

Then remove `periodicBoardTypeCheck()` entirely and remove its call from `update()`.

**Risk:** Zero. Same logic, just runs in the same timer callback instead of a
separate one.

---

### Fix 10: `advanceToNextSentence()` → `endSession()` indirect recursion

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 537, 812-820

**Problem:** `advanceToNextSentence()` calls `endSession()` (via baseline transition)
when sentences run out. `endSession()` can be reached from
`onPauseComplete() → advanceToNextSentence()`. The chain terminates because
`finalizeSession()` sets `sessionActive = false`, but it's fragile.

**Fix:** Add an explicit guard in `onPauseComplete()` after `advanceToNextSentence()`:

```java
// In onPauseComplete(), after line 537:
if (!practiceMode) {
    advanceToNextSentence();
} else {
    transitionTo(STATE_READY);
    updateSpeakingModeForPhase();
}

// Add this guard:
if (!sessionActive) {
    updateButtonStates();
    return;
}
```

**Risk:** Zero. Just an early return that prevents dead-code execution after session
end.

---

### Fix 11: F9 falls through without returning true

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 936-942

**Problem:** When F9 conditions aren't met (not TRIAL_SINGLE, or recording), the
handler falls through to `return false`, letting the keypress propagate to the main
GUI handler. While harmless now, it's a latent bug if F9 ever gets assigned elsewhere.

**Fix:** Always return true for F9 when session is active, but only act on it when
conditions are met:

```java
if (keyCodePress == KEY_F9) {
    if (trialModeIndex == TRIAL_SINGLE && trialState != STATE_RECORDING) {
        speakingMode = (speakingMode == MODE_SILENT) ? MODE_VOCALIZED : MODE_SILENT;
        output("Speech Experiment: Mode toggled to " + getSpeakingModeStr());
    }
    return true; // consume the key either way
}
```

**Risk:** Zero. Only changes whether an unhandled F9 propagates.

---

### Fix 12: `mkdirs()` return value unchecked

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Lines:** 845, and wherever `mkdirs()` is called in export setup

**Problem:** `new File(logDir).mkdirs()` returns false on failure but the return value
is ignored. On a full disk or permissions error, the subsequent `createWriter()` will
throw an exception that's caught, but the error message won't indicate the root cause.

**Fix:** Check the return value and warn early:

```java
File dir = new File(logDir);
if (!dir.exists() && !dir.mkdirs()) {
    outputError("Speech Experiment: Cannot create directory: " + logDir);
    return;
}
```

Apply the same pattern to all `mkdirs()` calls in the export setup code.

**Risk:** Zero. Adds an early return with a clear message instead of a cryptic
IOException.

---

### Fix 13: `actualAudioSampleRate` written when audio unavailable

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`
**Line:** 1642

**Problem:** `config.setInt("audio_sample_rate_hz", actualAudioSampleRate)` writes
`16000` (the field default) even when `audioAvailable` is `false`. The Python export
script may incorrectly assume audio exists.

**Fix:**
```java
config.setInt("audio_sample_rate_hz", audioAvailable ? actualAudioSampleRate : 0);
```

**Risk:** Zero. The Python script should already check `audio_available` before using
this field, but writing 0 makes the intent unambiguous.

---

## P3 — Low (cleanup, dead code)

### Fix 14: Remove dead code

**File:** `OpenBCI_GUI/W_SpeechExperiment.pde`

**Items to remove:**
- **Lines 1298-1300:** `markerToSentenceIndex()`, `markerToMode()`, `markerIsStart()`
  — defined but never called. Trivially re-derivable from the marker formula
  documented in the header if ever needed.
- **Line 156:** `private int utteranceCounter = 0;` — incremented in
  `startUtteranceAudio()` (line 1563) and reset in `startSession()` (line 614), but
  the value is never read or used for anything. Filenames use sentence ID + mode
  string, not this counter.
- **Line 614:** `utteranceCounter = 0;` — remove alongside the field.
- **Line 1563:** `utteranceCounter++;` — remove alongside the field.

**Risk:** Zero. Unused code deletion.

---

### Fix 15: export_gaddy.py hardening

**File:** `export_gaddy.py`

**Items:**
- **`rglob` too broad:** `find_brainflow_csv()` uses `rglob("BrainFlow*.csv")` which
  could match files from other sessions in parent directories. Restrict search to the
  session directory only: use `glob` (non-recursive) or limit depth.
- **Marker detection heuristic fragile:** The "last few columns, values 10-1000"
  heuristic could false-positive on accelerometer data. Add a check that the column
  contains both odd (start) and even (stop) values matching the marker scheme.
- **`sentence_id` parsing:** `replace("S","")` will crash or produce wrong results on
  IDs not matching the `S<number>` format. Add a try/except or regex check.

**Risk:** Low. These are edge-case hardening for the export script.

---

## Execution Order

Recommended order to minimize risk and maximize value per step:

| Step | Fix | Impact | Touches |
|------|-----|--------|---------|
| 1 | Fix 1 | Restores broken GUI error recovery | OpenBCI_GUI.pde |
| 2 | Fix 2 | Fixes silent audio loss on session 2+ | W_SpeechExperiment.pde |
| 3 | Fix 3 | Fixes marker data integrity | W_SpeechExperiment.pde |
| 4 | Fix 4 | Fixes Python crash | export_gaddy.py |
| 5 | Fix 5 | Prevents resource leak | W_SpeechExperiment.pde |
| 6 | Fix 6 | Fixes log timestamps | W_SpeechExperiment.pde |
| 7 | Fix 7 | Auto-increments session ID | W_SpeechExperiment.pde |
| 8 | Fix 8 | Adds error logging | ConsoleLog.pde |
| 9 | Fix 9 | Simplifies board detection | W_SpeechExperiment.pde |
| 10 | Fix 10 | Adds recursion guard | W_SpeechExperiment.pde |
| 11 | Fix 11 | Prevents key propagation | W_SpeechExperiment.pde |
| 12 | Fix 12 | Better directory error handling | W_SpeechExperiment.pde |
| 13 | Fix 13 | Correct config when no audio | W_SpeechExperiment.pde |
| 14 | Fix 14 | Dead code cleanup | W_SpeechExperiment.pde |
| 15 | Fix 15 | Export script hardening | export_gaddy.py |

Fixes 1-4 are the critical path. Fixes 5-7 should be done before any real data
collection. Fixes 8-15 can be batched into a single cleanup commit.
# Speech Experiment Widget — Claude Code Agent Instructions

## Role
You are a UI/UX designer and Processing/Java developer specializing in the OpenBCI GUI widget system. You are building a data collection widget for silent speech EMG research.

## Project Context
This is an OpenBCI GUI widget (Processing/Java, ControlP5 library) that guides participants through recording facial EMG while reading sentences. The data feeds into the Gaddy & Klein silent speech ML pipeline. The widget must be usable by non-technical research assistants running hour-long recording sessions with participants who have electrodes glued to their face.

## Tech Stack
- **Language**: Processing (Java-based), runs inside OpenBCI GUI
- **UI Library**: ControlP5 (buttons, dropdowns, toggles)
- **Fonts available**: `p3` (large), `p4` (medium), `p5` (small) — these are global PFont objects in OpenBCI GUI
- **Colors available**: `OPENBCI_DARKBLUE`, `OPENBCI_BLUE`, `colorNotPressed`, `OBJECT_BORDER_GREY` — global color constants
- **Widget base class**: `Widget` — provides `x`, `y`, `w`, `h`, `navH` for layout. All drawing must be within these bounds.
- **Board API**: `currentBoard.isStreaming()`, `((Board)currentBoard).insertMarker(float value)` for markers
- **File I/O**: `loadStrings()`, `selectInput()` for file dialogs
- **Audio**: Processing `sound` library or `javax.sound` for microphone recording

## Design Constraints

### OpenBCI GUI Specific
- Widget can be resized and repositioned — all layout must be relative to `x, y, w, h`
- `screenResized()` must reposition all ControlP5 elements
- ControlP5 buttons use `createButton(localCP5, id, label, x, y, w, h, font, fontSize, bgColor, fontColor)`
- The widget shares screen with other widgets (EEG timeseries, FFT, etc.) — it may be as small as 400x300px
- Navigation bar height `navH` must be accounted for at top
- `draw()` is called ~60fps, `update()` before each draw

### UX Priorities (ranked)
1. **Participant focus**: The sentence text must be the dominant visual element. Minimize distractions during recording.
2. **Operator clarity**: The research assistant must always know: current state (recording/paused/idle), progress, and what to do next.
3. **Error prevention**: Make it hard to accidentally skip sentences, record over data, or lose progress.
4. **Session endurance**: Sessions last 30-60 minutes. Reduce fatigue with clear visual hierarchy, minimal eye movement, and good contrast.

### Recording Protocol
Each sentence is recorded twice per the Gaddy protocol:
1. **Vocalized**: participant speaks the sentence aloud
2. **Silent**: participant mouths the sentence without sound

The widget must track which mode is active and insert different markers for each.

## Data Structure Target

Output must be convertible to per-utterance files matching:
```
{i}_emg.npy     — shape (T, 8) raw EMG
{i}_audio.flac   — 16kHz mono audio
{i}_info.json    — {"book":"source","sentence_index":i,"text":"...","chunks":[[emg_len,audio_len,btn_len]]}
{i}_button.npy   — button state array
```

Session log CSV maps markers back to sentence IDs for the segmentation script.

## UI Layout Spec

```
┌─────────────────────────────────────────┐
│ [Nav Bar - handled by Widget base]      │
├─────────────────────────────────────────┤
│ STATUS BAR: Session info, mode, timer   │  ~35px
├─────────────────────────────────────────┤
│ CONTROL ROW: [Load][Start][Pause][Redo] │  ~40px
├─────────────────────────────────────────┤
│                                         │
│                                         │
│         SENTENCE DISPLAY                │  fills remaining
│     (large centered text)               │
│                                         │
│   mode badge: [VOCALIZED] or [SILENT]   │
│   next sentence preview (small, grey)   │
├─────────────────────────────────────────┤
│ ████████░░░░ 12/50 (24%) ■ REC 00:03.2 │  ~30px progress
└─────────────────────────────────────────┘
```

## Visual States

| State | Status Bar | Sentence BG | Recording Indicator |
|-------|-----------|-------------|-------------------|
| No CSV loaded | "Load a CSV to begin" | Grey placeholder text | Hidden |
| CSV loaded, not started | "Ready: 50 sentences" | First sentence preview | Hidden |
| Session active, idle | "Sentence 12/50" | White text on dark bg | Hidden |
| Session active, recording | "Recording... 3.2s" | White text, subtle red border | Pulsing red dot |
| Session paused | "Paused at 12/50" | Dimmed text | Hidden |
| Session complete | "Complete! 50/50" | Green success message | Hidden |

## Keyboard Shortcuts
- `S` — Start/stop recording
- `D` — Done with current sentence, advance
- `R` — Redo current sentence/mode
- `P` — Pause session
- Do NOT use `Space` (conflicts with OpenBCI stream toggle)

## Color Palette
```java
// Dark theme to match OpenBCI GUI
color BG_DARK = color(31, 31, 36);
color BG_PANEL = color(42, 42, 48);
color BG_SENTENCE = color(26, 26, 30);
color TEXT_PRIMARY = color(240, 240, 245);
color TEXT_SECONDARY = color(160, 160, 170);
color TEXT_MUTED = color(100, 100, 110);
color ACCENT_BLUE = color(80, 150, 220);
color RECORDING_RED = color(220, 60, 60);
color RECORDING_RED_DIM = color(120, 40, 40);
color SUCCESS_GREEN = color(80, 200, 120);
color MODE_VOCALIZED = color(80, 150, 220);   // blue badge
color MODE_SILENT = color(200, 160, 60);       // amber badge
color PROGRESS_FILL = color(80, 150, 220);
color PROGRESS_BG = color(55, 55, 62);
```

## Code Patterns to Follow

### Button creation
```java
Button btn = createButton(localCP5, "uniqueId", "Label",
    x + offset, y + offset, width, height,
    p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
btn.setBorderColor(OBJECT_BORDER_GREY);
btn.onRelease(new CallbackListener() {
    public void controlEvent(CallbackEvent e) {
        doSomething();
    }
});
```

### Drawing within bounds
```java
// Always use pushStyle/popStyle
pushStyle();
fill(BG_PANEL);
noStroke();
rect(x, y + navH, w, panelHeight);  // navH offset at top
// ... draw content
popStyle();
```

### Resize handling
```java
public void screenResized() {
    super.screenResized();
    localCP5.setGraphics(ourApplet, 0, 0);
    // Recalculate ALL element positions relative to x, y, w, h
    myButton.setPosition(x + 10, y + navH + 10);
}
```

## When Making Changes

1. Always preserve the existing state machine (sessionActive, currentlyRecording, etc.)
2. Test that the widget works at minimum size 400x300
3. Ensure all ControlP5 elements are repositioned in screenResized()
4. Use `output("Speech Experiment: ...")` for user-facing log messages
5. Use `verbosePrint(...)` for debug messages
6. Never block the draw loop — no `Thread.sleep()` or long operations in update/draw
7. Marker values must be deterministic and documented so the export script can parse them

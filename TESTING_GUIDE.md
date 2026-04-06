# Quick Testing Guide - Speech Experiment Widget

## In Processing IDE:

1. **Click the Run button** (▶️) or press **Ctrl+R**

2. **Watch the console** at the bottom for any errors
   - If you see errors, copy the ENTIRE error message
   - Look for lines mentioning "W_SpeechExperiment" or "speechExp"

3. **In the OpenBCI GUI window:**
   - Select **Synthetic (algorithmic)** as data source
   - Click **START SESSION**
   - Click any widget container dropdown
   - Look for **"Speech Experiment"** in the list

4. **If the widget appears:**
   - Select it
   - Click **"Load CSV"**
   - Navigate to: `OpenBCI_GUI/data/test_sentences.csv`
   - Click **"Start Session"**
   - Test the controls:
     - **S** key or button = Start/Stop Recording
     - **D** key or button = Next Sentence
     - **P** key or button = Pause

## Expected Behavior:

✓ Widget appears in dropdown
✓ CSV loads with "Loaded 15 sentences..." message  
✓ First sentence displays in large text
✓ Recording button turns red when recording
✓ Progress bar shows X/15 sentences
✓ Console shows marker insertion messages

## Common Issues & Fixes:

| Issue | Fix |
|-------|-----|
| Widget not in dropdown | Check console for "W_SpeechExperiment" errors |
| CSV won't load | Make sure file is in `OpenBCI_GUI/data/` folder |
| Buttons don't work | Check if session is started |
| Keyboard shortcuts don't work | Make sure widget is active & session running |

## From VS Code (After Testing):

You can now also build/run from VS Code:
- **Ctrl+Shift+B** → Select "Run Processing Sketch"

Or from terminal:
```powershell
& "C:\Program Files\Processing\Processing.exe" cli --sketch="OpenBCI_GUI" --run
```

## Share These With Me:

1. ✓/✗ Sketch runs without errors
2. ✓/✗ Widget appears in dropdown
3. ✓/✗ CSV loads successfully
4. ✓/✗ Recording controls work
5. ✓/✗ Keyboard shortcuts work
6. **Any console errors** (copy full text)

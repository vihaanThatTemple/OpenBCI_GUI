# Gaddy-Compatible Data Export — OpenBCI Speech Experiment

## Overview

This pipeline converts data collected by the OpenBCI Speech Experiment widget into the directory structure expected by the [Gaddy & Klein silent speech EMG pipeline](https://github.com/dgaddy/silent_speech).

## Sampling Rate Difference (IMPORTANT)

| Parameter | Gaddy & Klein (2020/2021) | OpenBCI Cyton | Action Needed |
|-----------|--------------------------|---------------|---------------|
| EMG sample rate | 1000 Hz | **250 Hz** serial, **up to 16kHz** WiFi | See below |
| EMG channels | 8 | 8 (Cyton) / 16 (Daisy) | Use first 8 channels |
| Audio sample rate | 16000 Hz | 16000 Hz (widget mic) | No change |
| Target resample | 800 Hz | N/A | Change source rate |

### Cyton Sample Rate Options

| Connection | Max Sample Rate | Notes |
|------------|----------------|-------|
| **Cyton Serial** (USB dongle / Bluetooth) | **250 Hz** | Bluetooth bandwidth limited |
| **Cyton WiFi Shield** | **250 / 500 / 1000 / 2000 / 4000 / 8000 / 16000 Hz** | Select in GUI Control Panel |

To match Gaddy's 1000Hz, use the **WiFi Shield** and set sample rate to 1000Hz in the OpenBCI GUI Control Panel before streaming. At 1000Hz, no resampling changes are needed in the ML pipeline.

### What to change in the ML pipeline (if not at 1000Hz)

In `read_emg.py`, the original code resamples from 1000Hz to 800Hz:

```python
# ORIGINAL (Gaddy)
emg = scipy.signal.resample(emg, int(len(emg) * 800 / 1000))

# MODIFIED (for 250Hz OpenBCI data) — Option A: upsample to 800Hz
emg = scipy.signal.resample(emg, int(len(emg) * 800 / 250))

# MODIFIED — Option B: keep at 250Hz, adjust model conv factors
# This requires changing the temporal conv downsampling in the model
# from factors suited for 800Hz to factors suited for 250Hz
```

**Option A** (upsample) is simpler but may introduce artifacts. **Option B** (adjust model) is more principled but requires architecture changes. Benster et al. (2024) discuss handling different sample rates.

For Cyton WiFi boards, higher sample rates (500Hz, 1000Hz) are available — configure in the OpenBCI GUI control panel before recording.

## Pipeline: Widget → Export Script → ML Training

```
┌─────────────────────────────────────────┐
│  1. OpenBCI GUI — W_SpeechExperiment    │
│     - Load sentence CSV                 │
│     - Configure: trial mode, countdown  │
│     - Start streaming + Start session   │
│     - Record each sentence              │
│     - Auto: mic recording per utterance │
│     - Auto: EMG markers in data stream  │
│     - Auto: 5s baseline at start/end    │
│     - End session → writes:             │
│       session_log.csv                   │
│       export_config.json                │
│       audio_raw/*.wav                   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  2. export_gaddy.py                     │
│     - Reads session_log.csv             │
│     - Reads export_config.json          │
│     - Reads BrainFlow-RAW CSV           │
│     - Segments EMG by marker timestamps │
│     - Converts WAV → FLAC              │
│     - Writes per-utterance:             │
│       {i}_emg.npy                       │
│       {i}_audio.flac                    │
│       {i}_info.json                     │
│       {i}_button.npy                    │
│     - Organizes into Gaddy dirs         │
└��─────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  3. clean_audio.py (from Gaddy repo)    │
│     - Normalizes audio levels           │
│     - Removes leading/trailing silence  │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  4. ML Training (Gaddy pipeline)        │
│     - read_emg.py loads the data        │
│     - Adjust resample: 250→800Hz        │
│     - Train transduction model          │
└─────────────────────────────────────────┘
```

## Output Directory Structure

```
emg_data/
├── silent_parallel_data/
│   └── session_1/
│       ├── 0_emg.npy          # Baseline start (5s silence)
│       ├── 0_audio.flac
│       ├── 0_info.json        # {"sentence_index": -1, "text": ""}
│       ├── 0_button.npy
│       ├── 1_emg.npy          # First sentence, silent
│       ├── 1_audio.flac       # Near-silent audio
│       ├── 1_info.json        # {"sentence_index": 1, "text": "The cat sat..."}
│       ├── 1_button.npy
│       └── ...
├── voiced_parallel_data/
│   └── session_1/
│       ├── 0_emg.npy          # Same baseline
│       ├── 1_emg.npy          # Same sentence, vocalized
│       ├── 1_audio.flac       # Audible speech
│       └── ...
└── nonparallel_data/           # Used for single-mode sessions
    └── session_1/
        └── ...
```

## File Formats

### {i}_emg.npy
- NumPy float32 array, shape `(T, num_channels)`
- `T` = number of EMG samples (varies per utterance)
- `num_channels` = 8 for standard Cyton
- Sample rate: check `export_config.json → emg_sample_rate_hz`

### {i}_audio.flac
- 16kHz mono FLAC audio
- Duration matches the EMG recording period
- Silent recordings will have near-zero audio (ambient noise only)

### {i}_info.json
```json
{
    "book": "",
    "sentence_index": 1,
    "text": "The quick brown fox jumps over the lazy dog.",
    "chunks": [[1250, 80000, 1250]]
}
```
- `chunks`: `[[emg_length, audio_length, button_length]]`
- `sentence_index`: -1 for baseline silence segments

### {i}_button.npy
- Float32 array of zeros (length matches EMG samples)
- Placeholder for compatibility with Gaddy pipeline

## Running the Export

```bash
# Install dependencies
pip install numpy soundfile

# Run export
python export_gaddy.py path/to/SpeechExp_Session1_2026-04-06_14-30-00/

# If BrainFlow CSV isn't auto-detected:
python export_gaddy.py path/to/session/ --brainflow path/to/BrainFlow-RAW_1.csv

# Custom output location:
python export_gaddy.py path/to/session/ --output ./my_emg_data/
```

## Marker Encoding Reference

The widget inserts integer markers into the EEG data stream:

```
marker = (sentence_index + 1) * 10 + mode * 2 + event

mode:  0 = silent,    1 = vocalized
event: 1 = start,     2 = stop
```

| Sentence | Mode | Event | Marker |
|----------|------|-------|--------|
| 0 | silent | start | 11 |
| 0 | silent | stop | 12 |
| 0 | vocalized | start | 13 |
| 0 | vocalized | stop | 14 |
| 1 | silent | start | 21 |
| 5 | vocalized | stop | 64 |

The export script uses these markers to find the exact sample boundaries in the BrainFlow CSV for EMG segmentation.
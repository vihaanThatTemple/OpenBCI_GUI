#!/usr/bin/env python3
"""
export_gaddy.py — Convert OpenBCI Speech Experiment session to Gaddy & Klein format.

Reads the session export directory produced by W_SpeechExperiment and generates
the directory structure expected by github.com/dgaddy/silent_speech.

Usage:
    python export_gaddy.py <session_export_dir> [--output <output_dir>]

Example:
    python export_gaddy.py ~/Documents/OpenBCI_GUI/Recordings/SpeechExp_Session1_2026-04-06_14-30-00/
    python export_gaddy.py ./SpeechExp_Session1_.../ --output ./emg_data/

Input (from widget):
    SpeechExp_SessionN_timestamp/
    ├── session_log.csv          # marker-to-sentence mapping
    ├── export_config.json       # metadata (sample rates, trial mode, etc.)
    └── audio_raw/               # per-utterance WAV files
        ├── baseline_start.wav
        ├── S001_vocalized.wav
        ├── S001_silent.wav
        └── baseline_end.wav

Also requires:
    - BrainFlow-RAW CSV file (located automatically or specified with --brainflow)

Output (Gaddy format):
    emg_data/
    ├── silent_parallel_data/session_N/
    │   ├── 0_emg.npy, 0_audio.flac, 0_info.json, 0_button.npy
    │   └── ...
    ├── voiced_parallel_data/session_N/
    │   └── ...
    └── nonparallel_data/session_N/
        └── ...

Requirements:
    pip install numpy soundfile pandas
"""

import argparse
import csv
import json
import os
import sys
from pathlib import Path

import numpy as np

# Optional: soundfile for WAV->FLAC conversion
try:
    import soundfile as sf
    HAS_SOUNDFILE = True
except ImportError:
    HAS_SOUNDFILE = False
    print("WARNING: soundfile not installed. Audio will remain as WAV (pip install soundfile)")

# Optional: pandas for easier CSV handling
try:
    import pandas as pd
    HAS_PANDAS = True
except ImportError:
    HAS_PANDAS = False


def load_export_config(session_dir):
    """Load export_config.json from the session directory."""
    config_path = os.path.join(session_dir, "export_config.json")
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"export_config.json not found in {session_dir}")
    with open(config_path, "r") as f:
        return json.load(f)


def load_session_log(session_dir):
    """Load session_log.csv into a list of dicts."""
    log_path = os.path.join(session_dir, "session_log.csv")
    if not os.path.exists(log_path):
        raise FileNotFoundError(f"session_log.csv not found in {session_dir}")

    entries = []
    with open(log_path, "r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            row["start_marker"] = int(row["start_marker"])
            row["stop_marker"] = int(row["stop_marker"])
            row["start_timestamp_ms"] = int(row["start_timestamp_ms"])
            row["stop_timestamp_ms"] = int(row["stop_timestamp_ms"])
            row["duration_ms"] = int(row["duration_ms"])
            row["recording_index"] = int(row["recording_index"])
            row["session_id"] = int(row["session_id"])
            entries.append(row)
    return entries


def find_brainflow_csv(session_dir, recordings_dir=None):
    """Try to locate the BrainFlow-RAW CSV file."""
    # Check in session dir first
    for f in Path(session_dir).glob("BrainFlow-RAW*.csv"):
        return str(f)

    # Check in parent (Recordings/) directory
    parent = os.path.dirname(session_dir.rstrip(os.sep))
    for f in Path(parent).rglob("BrainFlow-RAW*.csv"):
        return str(f)

    if recordings_dir:
        for f in Path(recordings_dir).rglob("BrainFlow-RAW*.csv"):
            return str(f)

    return None


def load_brainflow_csv(csv_path, config):
    """
    Load a BrainFlow-RAW CSV file.
    Returns the full data array and identifies the marker channel.

    BrainFlow CSV format: each row is a sample, columns are channels.
    The marker channel index depends on the board type.
    """
    print(f"  Loading BrainFlow data: {csv_path}")
    with open(csv_path, "r") as f:
        first_line = f.readline()
    sep = "\t" if "\t" in first_line else ","
    print(f"  Detected delimiter: {'TAB' if sep == '\t' else 'COMMA'}")

    # BrainFlow CSVs can have inconsistent column counts and corrupted values
    # (board restarts, buffer glitches). Parse line-by-line and skip bad rows.
    rows = []
    skipped = 0
    target_cols = None
    with open(csv_path, "r") as f:
        for line_num, line in enumerate(f):
            vals = line.strip().split(sep)
            try:
                parsed = [float(v) if v else 0.0 for v in vals]
            except ValueError:
                skipped += 1
                continue
            # Lock column count to the first valid row
            if target_cols is None:
                target_cols = len(parsed)
            if len(parsed) != target_cols:
                skipped += 1
                continue
            rows.append(parsed)
    if skipped > 0:
        print(f"  Skipped {skipped} malformed rows")
    data = np.array(rows, dtype=np.float64)

    print(f"  Shape: {data.shape} ({data.shape[0]} samples, {data.shape[1]} columns)")
    return data


def find_marker_channel(data, config):
    """
    Find the marker channel by looking for non-zero values matching our encoding.
    Markers are encoded as (sentence_index+1)*10 + mode*2 + event.
    """
    num_cols = data.shape[1]
    # Try the last few columns (marker is typically near the end)
    for col_idx in range(num_cols - 1, max(num_cols - 5, -1), -1):
        col = data[:, col_idx]
        non_zero = col[col != 0]
        if len(non_zero) > 0 and len(non_zero) < data.shape[0] * 0.1:
            # Marker channel: sparse non-zero values, mostly small integers
            vals = set(non_zero.astype(int))
            # Check if ANY values match our marker encoding (11+ range)
            marker_like = [v for v in vals if 10 < v < 1000]
            if len(marker_like) >= 2:  # at least one start+stop pair
                print(f"  Marker channel detected at column {col_idx} ({len(non_zero)} non-zero, {len(marker_like)} marker-like)")
                return col_idx
    return None


def segment_emg_by_markers(data, marker_col, config, log_entries):
    """
    Segment the continuous EMG data into per-utterance arrays using markers.
    Returns list of (emg_array, log_entry) tuples.
    """
    emg_channels = config.get("emg_num_channels", 8)
    sample_rate = config.get("emg_sample_rate_hz", 250)
    markers = data[:, marker_col]

    segments = []
    for entry in log_entries:
        start_marker = entry["start_marker"]
        stop_marker = entry["stop_marker"]

        # Find sample indices where markers appear
        start_indices = np.where(markers == start_marker)[0]
        stop_indices = np.where(markers == stop_marker)[0]

        if len(start_indices) == 0 or len(stop_indices) == 0:
            print(f"  WARNING: Markers {start_marker}/{stop_marker} not found for {entry['sentence_id']}")
            continue

        start_idx = start_indices[0]
        stop_idx = stop_indices[0]

        if stop_idx <= start_idx:
            print(f"  WARNING: Invalid marker range for {entry['sentence_id']}: {start_idx}-{stop_idx}")
            continue

        # Extract EXG channels (first N columns, typically 0-7)
        emg_segment = data[start_idx:stop_idx, :emg_channels]
        segments.append((emg_segment, entry))

        dur_sec = emg_segment.shape[0] / sample_rate
        print(f"  Segmented {entry['sentence_id']} [{entry['speaking_mode']}]: "
              f"{emg_segment.shape[0]} samples ({dur_sec:.2f}s)")

    return segments


def create_silence_segment(data, marker_col, config, duration_sec=5.0, from_start=True):
    """Create a silence/baseline segment from the start or end of the recording."""
    emg_channels = config.get("emg_num_channels", 8)
    sample_rate = config.get("emg_sample_rate_hz", 250)
    n_samples = int(duration_sec * sample_rate)

    if from_start:
        emg = data[:n_samples, :emg_channels]
    else:
        emg = data[-n_samples:, :emg_channels]

    return emg


def convert_wav_to_flac(wav_path, flac_path):
    """Convert WAV to FLAC using soundfile."""
    if not HAS_SOUNDFILE:
        # Just copy WAV as-is
        import shutil
        flac_path = flac_path.replace(".flac", ".wav")
        if os.path.exists(wav_path):
            shutil.copy2(wav_path, flac_path)
        return flac_path

    if not os.path.exists(wav_path):
        return None

    audio_data, sr = sf.read(wav_path)
    sf.write(flac_path, audio_data, sr, format="FLAC")
    return flac_path


def write_info_json(output_path, sentence_text, sentence_index, emg_len, audio_len=0):
    """Write a Gaddy-format {i}_info.json file."""
    info = {
        "book": "",
        "sentence_index": sentence_index,
        "text": sentence_text,
        "chunks": [[emg_len, audio_len, emg_len]]  # [emg_len, audio_len, button_len]
    }
    with open(output_path, "w") as f:
        json.dump(info, f, indent=2)


def write_button_npy(output_path, length):
    """Write a dummy button array (zeros)."""
    button = np.zeros(length, dtype=np.float32)
    np.save(output_path, button)


def get_output_dirs(trial_mode, session_id, output_base):
    """
    Determine output directories based on trial mode.
    Returns dict mapping speaking_mode -> directory path.
    """
    session_name = f"session_{session_id}"

    if trial_mode in ("vocal_then_silent", "silent_then_vocal"):
        return {
            "silent": os.path.join(output_base, "silent_parallel_data", session_name),
            "vocalized": os.path.join(output_base, "voiced_parallel_data", session_name),
        }
    else:
        # Single mode (vocalized-only or mixed) -> nonparallel
        return {
            "vocalized": os.path.join(output_base, "nonparallel_data", session_name),
            "silent": os.path.join(output_base, "nonparallel_data", session_name),
        }


def export_session(session_dir, output_base, brainflow_csv_path=None):
    """Main export function."""
    print(f"=== Gaddy Export: {session_dir} ===\n")

    # 1. Load config and log
    config = load_export_config(session_dir)
    log_entries = load_session_log(session_dir)
    print(f"  Session {config['session_id']}: {len(log_entries)} recordings")
    print(f"  Trial mode: {config['trial_mode']}")
    print(f"  EMG: {config['emg_num_channels']}ch @ {config['emg_sample_rate_hz']}Hz")
    print(f"  Audio: {'available' if config['audio_available'] else 'not available'} "
          f"@ {config['audio_sample_rate_hz']}Hz")
    print()

    # 2. Find and load BrainFlow data
    if brainflow_csv_path is None:
        brainflow_csv_path = find_brainflow_csv(session_dir)
    if brainflow_csv_path is None:
        print("ERROR: BrainFlow-RAW CSV not found. Specify with --brainflow <path>")
        print("  Exporting audio-only (no EMG segmentation)...")
        bf_data = None
        marker_col = None
    else:
        bf_data = load_brainflow_csv(brainflow_csv_path, config)
        marker_col = find_marker_channel(bf_data, config)
        if marker_col is None:
            print("WARNING: Could not identify marker channel. EMG segmentation unavailable.")
    print()

    # 3. Setup output directories
    trial_mode = config.get("trial_mode", "single")
    session_id = config["session_id"]
    dir_map = get_output_dirs(trial_mode, session_id, output_base)

    for d in dir_map.values():
        os.makedirs(d, exist_ok=True)
    print(f"  Output directories: {list(set(dir_map.values()))}\n")

    # 4. Segment EMG data
    segments = []
    if bf_data is not None and marker_col is not None:
        segments = segment_emg_by_markers(bf_data, marker_col, config, log_entries)
    print()

    # 5. Export per-utterance files
    audio_dir = os.path.join(session_dir, "audio_raw")
    # Track per-directory counters (not per-mode, to avoid overwrites when
    # multiple modes map to the same directory in nonparallel/single mode)
    dir_counters = {}  # out_dir -> next index

    # 5a. Baseline start (utterance 0 in each UNIQUE output dir)
    unique_dirs = list(set(dir_map.values()))
    for out_dir in unique_dirs:
        idx = 0
        dir_counters[out_dir] = 1  # next real utterance starts at 1

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

    print(f"  Exported baseline start as utterance 0\n")

    # 5b. Per-utterance exports
    for seg_idx, (emg_array, entry) in enumerate(segments):
        mode = entry["speaking_mode"]  # "silent" or "vocalized"
        out_dir = dir_map.get(mode, list(dir_map.values())[0])
        idx = dir_counters.get(out_dir, 1)
        dir_counters[out_dir] = idx + 1

        # EMG
        np.save(os.path.join(out_dir, f"{idx}_emg.npy"), emg_array.astype(np.float32))

        # Audio
        audio_filename = f"{entry['sentence_id']}_{mode}"
        wav_path = os.path.join(audio_dir, audio_filename + ".wav")
        flac_path = os.path.join(out_dir, f"{idx}_audio.flac")
        convert_wav_to_flac(wav_path, flac_path)

        # Info
        audio_len = 0
        if os.path.exists(wav_path) and HAS_SOUNDFILE:
            audio_info = sf.info(wav_path)
            audio_len = int(audio_info.frames)
        write_info_json(
            os.path.join(out_dir, f"{idx}_info.json"),
            entry["sentence_text"],
            int(entry["sentence_id"].replace("S", "").replace("s", "")) if entry["sentence_id"][0] in "Ss" else idx,
            emg_array.shape[0],
            audio_len
        )

        # Button (zeros)
        write_button_npy(os.path.join(out_dir, f"{idx}_button.npy"), emg_array.shape[0])

        print(f"  [{mode}] {idx}: {entry['sentence_id']} "
              f"({emg_array.shape[0]} samples, {emg_array.shape[0]/config['emg_sample_rate_hz']:.2f}s)")

    # 5c. Baseline end (final utterance in each UNIQUE output dir)
    for out_dir in unique_dirs:
        idx = dir_counters.get(out_dir, 1)

        emg_samples = 0
        if bf_data is not None:
            baseline_emg = create_silence_segment(bf_data, marker_col, config,
                                                   duration_sec=5.0, from_start=False)
            np.save(os.path.join(out_dir, f"{idx}_emg.npy"), baseline_emg.astype(np.float32))
            emg_samples = baseline_emg.shape[0]

        baseline_wav = os.path.join(audio_dir, "baseline_end.wav")
        audio_out = os.path.join(out_dir, f"{idx}_audio.flac")
        convert_wav_to_flac(baseline_wav, audio_out)

        write_info_json(os.path.join(out_dir, f"{idx}_info.json"), "", -1, emg_samples)
        write_button_npy(os.path.join(out_dir, f"{idx}_button.npy"), emg_samples)

    print(f"\n  Exported baseline end as final utterance")

    # 6. Print summary
    print("\n" + "=" * 60)
    print("EXPORT COMPLETE")
    print(f"  Output: {output_base}")
    total = sum(dir_counters.values())
    print(f"  Total utterances: {total} (including 2 baselines per directory)")
    print(f"  EMG sample rate: {config['emg_sample_rate_hz']}Hz")
    if config['emg_sample_rate_hz'] == 1000:
        print(f"  Sample rate matches Gaddy & Klein (2020) — no resampling changes needed.")
    else:
        print(f"\n  NOTE: Original Gaddy dataset uses 1000Hz EMG.")
        print(f"  Your data is {config['emg_sample_rate_hz']}Hz.")
        print(f"  Cyton serial (USB dongle/Bluetooth) is limited to 250Hz.")
        print(f"  Cyton WiFi Shield supports 250/500/1000/2000/4000/8000/16000Hz.")
        print(f"  Modify read_emg.py resampling: change from_hz=1000 to from_hz={config['emg_sample_rate_hz']}")
        print(f"  Or upsample to 800Hz target directly from {config['emg_sample_rate_hz']}Hz.")
    if config.get("needs_clean_audio", False):
        print(f"\n  NEXT STEP: Run clean_audio.py on the exported audio files.")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Export OpenBCI Speech Experiment session to Gaddy & Klein format",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example:
  python export_gaddy.py ./SpeechExp_Session1_2026-04-06_14-30-00/
  python export_gaddy.py ./SpeechExp_Session1_.../ --output ./emg_data/ --brainflow ./BrainFlow-RAW_1.csv
        """
    )
    parser.add_argument("session_dir", help="Path to the session export directory")
    parser.add_argument("--output", "-o", default=None,
                       help="Output directory (default: emg_data/ next to session dir)")
    parser.add_argument("--brainflow", "-b", default=None,
                       help="Path to BrainFlow-RAW CSV file (auto-detected if not specified)")

    args = parser.parse_args()

    session_dir = os.path.abspath(args.session_dir)
    if not os.path.isdir(session_dir):
        print(f"ERROR: Session directory not found: {session_dir}")
        sys.exit(1)

    output_base = args.output
    if output_base is None:
        output_base = os.path.join(os.path.dirname(session_dir), "emg_data")

    export_session(session_dir, output_base, args.brainflow)


if __name__ == "__main__":
    main()
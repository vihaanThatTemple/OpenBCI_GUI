# Speech Experiment Widget for OpenBCI GUI

## Overview
The Speech Experiment Widget is a custom widget for the OpenBCI GUI that enables controlled speech data collection experiments with EMG or EEG signals. It allows researchers to:

1. Load sentences from CSV files
2. Display sentences in large, readable format
3. Control recording with automatic marker insertion
4. Track experiment progress

## Installation
The widget has been installed in the OpenBCI GUI. The following files were added/modified:

### New Files:
- `OpenBCI_GUI/W_SpeechExperiment.pde` - Main widget code
- `OpenBCI_GUI/data/test_sentences.csv` - Sample test data

### Modified Files:
- `OpenBCI_GUI/WidgetManager.pde` - Added widget registration
- `OpenBCI_GUI/Interactivity.pde` - Added keyboard shortcut handling

## Usage

### 1. Start OpenBCI GUI
Run the OpenBCI_GUI.pde sketch in Processing.

### 2. Select the Widget
After starting a session (real or synthetic board):
1. Click on any widget container dropdown
2. Select "Speech Experiment" from the list

### 3. Load Sentences
1. Click "Load CSV" button
2. Select a CSV file (see format below)
3. Verify sentence count in status bar

### 4. Start Session
1. Click "Start Session" button
2. First sentence will be displayed

### 5. Recording Controls
- **Start/Stop Recording**: Click button or press `S`
- **Next Sentence**: Click button or press `D`
- **Pause Session**: Click button or press `P`

## Keyboard Shortcuts
| Key | Action |
|-----|--------|
| `S` | Start/Stop Recording |
| `D` | Next Sentence (Done with current) |
| `P` | Pause Session |

Note: These shortcuts only work when the widget is active and a session is running.

## CSV File Format
```csv
sentence_id,text,book_source
S001,"The quick brown fox jumps over the lazy dog.","Test Set 1"
S002,"She sells seashells by the seashore.","Test Set 1"
```

Required columns:
- `sentence_id`: Unique identifier for each sentence
- `text`: The sentence text to display
- `book_source`: Source/category of the sentence

## Marker Values
The widget automatically inserts markers into the data stream:

| Event | Marker Value |
|-------|-------------|
| Start Recording Sentence 1 | 1.1 |
| Stop Recording Sentence 1 | 1.2 |
| Start Recording Sentence 2 | 2.1 |
| Stop Recording Sentence 2 | 2.2 |
| ... | ... |
| Start Recording Sentence N | N.1 |
| Stop Recording Sentence N | N.2 |

## Recording Modes
Select from the "Mode" dropdown in the widget:

1. **Manual**: User manually starts/stops recording for each sentence
2. **Continuous**: Automatically starts recording when advancing to next sentence
3. **Timed (5s)**: Records for 5 seconds then automatically stops

## Features
- Large, centered sentence display for easy reading
- Progress bar showing experiment completion
- Recording indicator (red dot) when actively recording
- Automatic marker insertion for data annotation
- Session pause/resume capability

## Troubleshooting

### Widget doesn't appear in dropdown
- Ensure the GUI has started a session (select board type first)
- Check Processing console for errors

### Markers not appearing in data
- Ensure data streaming is active (use Synthetic board for testing)
- Check that recording is enabled in OpenBCI GUI

### CSV file not loading
- Verify CSV format matches expected format
- Check for encoding issues (use UTF-8)
- Ensure file path doesn't contain special characters

## Testing with Synthetic Board
1. Start OpenBCI GUI
2. Select "Synthetic (algorithmic)" data source
3. Start session
4. Add Speech Experiment widget
5. Load `data/test_sentences.csv`
6. Test recording controls

## Contact
For issues with this widget, check the OpenBCI GUI documentation or community forums.

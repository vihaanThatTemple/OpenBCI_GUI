# W_SpeechExperiment — Data Flow Diagrams

## 1. Context Diagram (Level 0)

```mermaid
flowchart LR
    CSV["CSV File\n(sentence_id, sentence_text)"]
    USER["User\n(keyboard + buttons)"]
    BOARD["OpenBCI Board\n(streaming, marker channel)"]
    CONSOLE["Console / Help Widget"]
    EEG["EEG Data Stream\n(raw data + markers)"]
    LOG["Session Log CSV\n(marker-to-sentence map)"]
    AUTOSAVE["Auto-save JSON\n(crash recovery)"]

    CSV -->|loadSentencesFromFile| W[W_SpeechExperiment]
    USER -->|keys S,D,P,R,M,E,H\nbuttons, dropdowns| W
    BOARD -->|isStreaming\ngetMarkerChannel| W

    W -->|insertMarker int| EEG
    W -->|writeSessionLog| LOG
    W -->|saveProgress| AUTOSAVE
    W -->|output, outputWarn\noutputError, outputSuccess| CONSOLE
```

## 2. Internal Data Flow (Level 1)

```mermaid
flowchart TD
    subgraph INPUTS
        CSV["CSV File"]
        KEYS["User Keys/Buttons"]
        DROPS["Dropdown Callbacks\n(RecMode, Trial,\nCountdown)"]
        BOARD["Board Status\n(streaming, markerCh)"]
    end

    subgraph PARSING
        PARSE["parseCSVLine()\nRFC 4180 parser\nBOM strip, header mapping"]
    end

    subgraph STATE["In-Memory State"]
        SENT["sentences\nArrayList&lt;SpeechSentenceData&gt;"]
        FSM["Trial State Machine\nIDLE|READY|COUNTDOWN\n|RECORDING|PAUSE"]
        CONFIG["Configuration\nrecordingMode, trialMode\ncountdownDuration\nspeakingMode, sessionId"]
        LOG["sessionLog\nArrayList&lt;SpeechLogEntry&gt;"]
        COUNTERS["Counters\ncurrentSentenceIndex\nskippedCount\nrecordingIndex"]
    end

    subgraph PROCESSING
        LOCK["Action Lock\n150ms cooldown"]
        MARKER["Marker Encoder\n(idx+1)*10 + mode*2 + event"]
        VALIDATE["Duration Validator\nwarn if &lt;1s or &gt;30s"]
        CHECK["Pre-session Checklist\nstreaming? markerCh?\nsentences loaded?"]
    end

    subgraph OUTPUTS
        EEG["EEG Data Stream\nBoard.insertMarker(int)"]
        LOGFILE["Session Log CSV\nRecordings/ directory"]
        SAVEFILE["Auto-save JSON\nOpenBCI_GUI/ directory"]
        DISPLAY["Widget Display\nheader, sentences,\nprogress, overlays"]
    end

    CSV --> PARSE --> SENT
    KEYS --> LOCK --> FSM
    DROPS --> CONFIG
    BOARD --> CHECK

    SENT --> FSM
    CONFIG --> FSM
    CONFIG --> MARKER

    FSM -->|beginRecording| MARKER
    FSM -->|endRecording| MARKER
    FSM -->|endRecording| VALIDATE
    FSM -->|endRecording| LOG

    MARKER --> EEG
    LOG --> LOGFILE
    COUNTERS --> SAVEFILE

    SENT --> DISPLAY
    FSM --> DISPLAY
    CONFIG --> DISPLAY
    COUNTERS --> DISPLAY
```

## 3. Marker Encoding & Decoding

```mermaid
flowchart LR
    subgraph ENCODE["Encoding: computeMarker()"]
        direction TB
        IDX["sentenceIndex\n(0-based)"]
        MODE["speakingMode\n0=silent\n1=vocalized"]
        EVT["event\n1=start\n2=stop"]
        FORMULA["marker =\n(idx+1)*10 + mode*2 + event"]
        IDX --> FORMULA
        MODE --> FORMULA
        EVT --> FORMULA
    end

    subgraph EXAMPLES["Examples"]
        direction TB
        E1["Sent 0, silent, start\n= 1*10 + 0 + 1 = 11"]
        E2["Sent 0, silent, stop\n= 1*10 + 0 + 2 = 12"]
        E3["Sent 0, vocal, start\n= 1*10 + 2 + 1 = 13"]
        E4["Sent 0, vocal, stop\n= 1*10 + 2 + 2 = 14"]
        E5["Sent 5, vocal, stop\n= 6*10 + 2 + 2 = 64"]
    end

    subgraph DECODE["Decoding"]
        direction TB
        D1["sentenceIndex =\n(marker / 10) - 1"]
        D2["mode =\n(marker % 10) / 2"]
        D3["isStart =\n(marker % 2) == 1"]
    end

    ENCODE --> EXAMPLES
    EXAMPLES --> DECODE
```

## 4. Marker Insertion Path

```mermaid
flowchart TD
    START["User presses S\nor auto-trigger"]
    LOCK{"acquireActionLock()\n&lt;150ms since last?"}
    REJECT["Rejected\n(too fast)"]
    PRACTICE{"practiceMode?"}
    COMPUTE["computeMarker(\nsentenceIndex,\nspeakingMode,\nevent)"]
    NOMARKER["No marker inserted\nlog: REC START PRACTICE"]
    CHECK{"currentBoard\ninstanceof\nBoardBrainFlow?"}
    CHECKCH{"getMarkerChannel()\n!= -1?"}
    FALLBACK{"currentBoard\ninstanceof Board\n& isStreaming?"}
    INSERT["Board.insertMarker(int)\nMarker appears in\nEEG data stream"]
    WARN["outputWarn:\nMarker channel\nnot available"]
    WARNSTREAM["outputWarn:\nNot streaming"]
    LOGOK["Log: REC START\nMarker: value"]
    LOGFAIL["Log: REC START\n[MARKER FAILED]"]

    START --> LOCK
    LOCK -->|Yes, rejected| REJECT
    LOCK -->|OK| PRACTICE
    PRACTICE -->|Yes| NOMARKER
    PRACTICE -->|No| COMPUTE
    COMPUTE --> CHECK
    CHECK -->|Yes| CHECKCH
    CHECK -->|No| FALLBACK
    CHECKCH -->|Yes| INSERT --> LOGOK
    CHECKCH -->|No| WARN --> LOGFAIL
    FALLBACK -->|Yes| INSERT
    FALLBACK -->|No| WARNSTREAM --> LOGFAIL
```

## 5. Session Log Output Path

```mermaid
flowchart TD
    TRIGGER["endSession() called\n(last sentence done,\nE key, or End Session button)"]
    CHECKLOG{"sessionLog.size() > 0\n&& !practiceMode?"}
    SKIP["No log written"]
    BUILDPATH["Build path:\nRecordings/SpeechExp_Session{id}_{timestamp}.csv"]
    MKDIR["Ensure directory exists\ndir.mkdirs()"]
    WRITER["createWriter(path)"]
    HEADER["Write CSV header:\nsession_id, sentence_id,\nsentence_text, speaking_mode,\nstart_marker, stop_marker,\nstart_timestamp_ms, stop_timestamp_ms,\nduration_ms, recording_index"]
    LOOP["For each SpeechLogEntry:\nescape text (RFC 4180)\nwrite CSV row"]
    FLUSH["writer.flush()\nwriter.close()"]
    SUCCESS["outputSuccess:\nSession log saved"]
    CLEAR["clearAutoSave()\ndelete JSON temp file"]

    TRIGGER --> CHECKLOG
    CHECKLOG -->|No| SKIP
    CHECKLOG -->|Yes| BUILDPATH --> MKDIR --> WRITER --> HEADER --> LOOP --> FLUSH --> SUCCESS --> CLEAR
```

## 6. Data Stores Reference

```mermaid
erDiagram
    SpeechSentenceData {
        String id "e.g. S001"
        String text "The sentence to read"
        String source "e.g. TIMIT (optional)"
    }

    SpeechLogEntry {
        int sessionId "Session number"
        String sentenceId "Matches CSV id"
        String sentenceText "Full sentence"
        String speakingMode "silent or vocalized"
        int startMarker "Encoded start marker"
        int stopMarker "Encoded stop marker"
        long startTimestampMs "millis() at start"
        long stopTimestampMs "millis() at stop"
        long durationMs "Recording length"
        int recordingIndex "Sequential counter"
    }

    AutoSaveJSON {
        int sessionId "Current session"
        int currentSentenceIndex "Progress position"
        int totalSentences "Total loaded"
        String csvFilePath "Path to reload"
        int recordingIndex "Counter"
        int skippedCount "Skips"
        int speakingMode "0 or 1"
        int trialModeIndex "0-2"
        int parallelPhase "0 or 1"
        long timestamp "When saved"
    }

    InputCSV ||--o{ SpeechSentenceData : "parsed into"
    SpeechSentenceData ||--o{ SpeechLogEntry : "generates on recording"
    SpeechLogEntry }o--|| SessionLogCSV : "written to"
    SpeechSentenceData }o--|| AutoSaveJSON : "path saved in"
```

## 7. File I/O Summary

```mermaid
flowchart LR
    subgraph READ["Inputs (Read)"]
        R1["User-selected CSV\n(any location)"]
        R2["Auto-save JSON\n~/Documents/OpenBCI_GUI/\nSpeechExp_autosave.json"]
        R3["Board streaming state\n(polled every 1s)"]
    end

    subgraph WIDGET["W_SpeechExperiment"]
        W1["sentences ArrayList"]
        W2["sessionLog ArrayList"]
        W3["trialState FSM"]
    end

    subgraph WRITE["Outputs (Write)"]
        O1["Session Log CSV\n~/Documents/OpenBCI_GUI/\nRecordings/\nSpeechExp_Session1_\n2026-04-06_14-30-00.csv"]
        O2["Auto-save JSON\n(overwritten every 10s)"]
        O3["EEG marker channel\n(via Board.insertMarker)"]
        O4["Console messages\n(via output/outputWarn)"]
    end

    R1 --> W1
    R2 --> W1
    R3 --> W3

    W2 --> O1
    W1 --> O2
    W3 --> O3
    W3 --> O4
```

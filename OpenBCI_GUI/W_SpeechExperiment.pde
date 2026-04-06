//////////////////////////////////////////////////////
//                                                  //
//          W_SpeechExperiment.pde                  //
//                                                  //
//  Speech Data Collection Experiment Widget        //
//                                                  //
//  Marker scheme (integer):                        //
//    marker = (sentIdx+1)*10 + mode*2 + event      //
//    mode: 0=silent, 1=vocalized                   //
//    event: 1=start, 2=stop                        //
//                                                  //
//  Trial states:                                   //
//    IDLE → READY → COUNTDOWN → RECORDING → PAUSE  //
//                                                  //
//  Shortcuts (F-keys, no conflicts with GUI):       //
//    F5=record, F6=next, F7=pause, F8=re-record,   //
//    F9=toggle mode, F10=end (2x), F1=help,         //
//    +/-=font size                                   //
//                                                  //
//////////////////////////////////////////////////////

class W_SpeechExperiment extends Widget {

    // === Trial State Constants ===
    private static final int STATE_IDLE = 0;
    private static final int STATE_READY = 1;
    private static final int STATE_COUNTDOWN = 2;
    private static final int STATE_RECORDING = 3;
    private static final int STATE_PAUSE = 4;
    private static final int STATE_BASELINE_START = 5; // 5s silence at session start
    private static final int STATE_BASELINE_END = 6;   // 5s silence at session end

    // === Speaking Mode Constants ===
    private static final int MODE_SILENT = 0;
    private static final int MODE_VOCALIZED = 1;

    // === Trial Mode Constants ===
    private static final int TRIAL_SINGLE = 0;
    private static final int TRIAL_VOCAL_THEN_SILENT = 1;
    private static final int TRIAL_SILENT_THEN_VOCAL = 2;

    // === Duration Validation Thresholds ===
    private static final long MIN_RECORDING_DURATION_MS = 1000;
    private static final long MAX_RECORDING_DURATION_MS = 30000;

    // === Font Size Limits (Task 16) ===
    private static final int MIN_FONT_SIZE = 16;
    private static final int MAX_FONT_SIZE = 48;

    // === F-Key Codes (java.awt.event.KeyEvent values) ===
    private static final int KEY_F1  = 112;
    private static final int KEY_F5  = 116;
    private static final int KEY_F6  = 117;
    private static final int KEY_F7  = 118;
    private static final int KEY_F8  = 119;
    private static final int KEY_F9  = 120;
    private static final int KEY_F10 = 121;

    // === End Session Safety (double-press F10) ===
    private boolean endSessionPending = false;
    private long endSessionPendingTime = 0;
    private static final long END_SESSION_CONFIRM_MS = 2000;

    // === UI Layout ===
    private int headerHeight = 40;
    private int controlPanelHeight = 80;
    private int progressHeight = 30;
    private int sentenceDisplayHeight;

    // === Control Elements ===
    private ControlP5 localCP5;
    private Button loadCsvButton;
    private Button startSessionButton;
    private Button startStopRecButton;
    private Button nextSentenceButton;
    private Button pauseSessionButton;
    private Button reRecordButton;
    private Button practiceToggleButton;
    private Button endSessionButton;   // Task 18

    // === Experiment State ===
    private ArrayList<SpeechSentenceData> sentences;
    private int currentSentenceIndex = 0;
    private boolean sessionActive = false;
    private boolean currentlyRecording = false;
    private String csvFilePath = "";
    private int totalSentences = 0;
    private long sessionStartTime = 0;

    // === Trial State Machine ===
    private int trialState = STATE_IDLE;
    private long stateStartTime = 0;

    // === Recording Mode (Manual/Continuous/Timed) ===
    private int recordingModeIndex = 0;
    private int timedRecordingDuration = 5000;

    // === Speaking Mode ===
    private int speakingMode = MODE_VOCALIZED;

    // === Trial Mode (Single vs Parallel) ===
    private int trialModeIndex = TRIAL_SINGLE;
    private int parallelPhase = 0;

    // === Session Tracking ===
    private int sessionId = 1;

    // === Practice Mode ===
    private boolean practiceMode = false;

    // === Countdown Settings ===
    private int countdownDuration = 3000;
    private int countdownSettingIndex = 1;

    // === Pause Durations ===
    private int interModePause = 1500;
    private int interSentencePause = 500;
    private int currentPauseDuration = 0;
    private String pauseReason = "";

    // === Timing ===
    private long recordingStartTime = 0;
    private long currentSentenceStartTime = 0;

    // === Session Log ===
    private ArrayList<SpeechLogEntry> sessionLog;
    private int recordingIndex = 0;
    private String sessionLogPath = "";

    // === Sentence Counters (Task 15) ===
    private int skippedCount = 0;

    // === Action Lock (Task 20) — prevents rapid-click state corruption ===
    private long lastActionTime = 0;
    private static final long ACTION_COOLDOWN_MS = 150; // min ms between actions

    // === Auto-save (Task 21) — crash recovery ===
    private long lastAutoSaveTime = 0;
    private static final long AUTO_SAVE_INTERVAL = 10000; // save every 10s
    private String autoSaveFilePath = "";

    // === Board Type Detection (Task 22) ===
    private boolean isSyntheticBoard = false;
    private boolean isPlaybackBoard = false;

    // === Audio Recording (Task 23) ===
    private Minim minim;
    private AudioInput micInput;
    private AudioRecorder currentAudioRecorder;
    private boolean audioAvailable = false;
    private int actualAudioSampleRate = 16000;

    // === Export Directory (Tasks 24-26) ===
    private String sessionExportDir = "";  // per-session folder
    private String audioRawDir = "";       // audio_raw/ subfolder
    private int utteranceCounter = 0;      // sequential file index

    // === Baseline Recording (Task 25) ===
    private static final long BASELINE_DURATION = 5000; // 5 seconds

    // === Streaming Status ===
    private boolean streamingWarningActive = false;
    private boolean markerChannelAvailable = false;
    private long lastStreamCheckTime = 0;
    private static final long STREAM_CHECK_INTERVAL = 1000;

    // === Pre-session Checklist ===
    private boolean checklistPassed = false;

    // === Help Overlay (Task 17) ===
    private boolean showHelpOverlay = false;

    // === Display Settings ===
    private int sentenceFontSize = 28;  // Task 16: adjustable with +/-
    private color textColor = color(255, 255, 255);
    private color progressBarColor = color(100, 150, 200);
    private color recordingColor = color(220, 50, 50);
    private color headerBgColor = color(50, 50, 55);
    private color controlBgColor = color(45, 45, 50);
    private color sentenceBgColor = color(30, 30, 35);
    private color silentModeColor = color(80, 160, 220);
    private color vocalizedModeColor = color(220, 160, 50);
    private color countdownColor = color(255, 220, 80);
    private color practiceColor = color(100, 200, 100);
    private color pauseTextColor = color(180, 180, 220);
    private color warningColor = color(220, 180, 50);

    // === CSV Parse Stats ===
    private int lastLoadSkippedRows = 0;

    // =========================================================
    // === Constructor ===
    // =========================================================
    W_SpeechExperiment(PApplet _parent) {
        super(_parent);

        sentences = new ArrayList<SpeechSentenceData>();
        sessionLog = new ArrayList<SpeechLogEntry>();
        sentenceDisplayHeight = h - headerHeight - controlPanelHeight - progressHeight - navH * 2;

        addDropdown("SpeechRecMode", "Rec Mode", Arrays.asList("Manual", "Continuous", "Timed (5s)"), 0);
        addDropdown("SpeechTrialMode", "Trial", Arrays.asList("Single", "Vocal\u2192Silent", "Silent\u2192Vocal"), 0);
        addDropdown("SpeechCountdown", "Countdown", Arrays.asList("Off", "3 sec", "5 sec"), 1);

        localCP5 = new ControlP5(ourApplet);
        localCP5.setGraphics(ourApplet, 0, 0);
        localCP5.setAutoDraw(false);

        // Task 23: Initialize Minim for audio recording
        initAudio();

        createButtons();
    }

    // =========================================================
    // === Create UI Buttons ===
    // =========================================================
    private void createButtons() {
        int bW = 120;
        int bH = 24;
        int pad = 10;
        int row1Y = y + navH * 2 + 10;
        int row2Y = row1Y + bH + 10;

        // --- Row 1 ---
        loadCsvButton = createButton(localCP5, "speechLoadCsv", "Load CSV",
            x + pad, row1Y, bW, bH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        loadCsvButton.setBorderColor(OBJECT_BORDER_GREY);
        loadCsvButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { loadCsvFile(); }
        });
        loadCsvButton.setDescription("Load a CSV file containing sentences");

        startSessionButton = createButton(localCP5, "speechStartSession", "Start Session",
            x + pad + bW + 10, row1Y, bW, bH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        startSessionButton.setBorderColor(OBJECT_BORDER_GREY);
        startSessionButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { startSession(); }
        });
        startSessionButton.setDescription("Start the experiment session");

        pauseSessionButton = createButton(localCP5, "speechPauseSession", "Pause",
            x + pad + (bW + 10) * 2, row1Y, 80, bH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        pauseSessionButton.setBorderColor(OBJECT_BORDER_GREY);
        pauseSessionButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { pauseSession(); }
        });
        pauseSessionButton.setDescription("Pause session (F7)");

        // Task 18: End Session button (beside Pause)
        endSessionButton = createButton(localCP5, "speechEndSession", "End Session",
            x + pad + (bW + 10) * 2 + 90, row1Y, 100, bH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        endSessionButton.setBorderColor(OBJECT_BORDER_GREY);
        endSessionButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { endSession(); }
        });
        endSessionButton.setDescription("End session, save log, show summary (F10 x2)");

        practiceToggleButton = createButton(localCP5, "speechPracticeToggle", "Practice: OFF",
            x + pad + (bW + 10) * 2 + 200, row1Y, 110, bH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        practiceToggleButton.setBorderColor(OBJECT_BORDER_GREY);
        practiceToggleButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { togglePracticeMode(); }
        });
        practiceToggleButton.setDescription("Toggle practice mode - no markers, no progress");

        // --- Row 2 ---
        startStopRecButton = createButton(localCP5, "speechToggleRec", "Start Recording",
            x + pad, row2Y, 140, 30, p4, 14, colorNotPressed, OPENBCI_DARKBLUE);
        startStopRecButton.setBorderColor(OBJECT_BORDER_GREY);
        startStopRecButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { handleRecordButton(); }
        });
        startStopRecButton.setDescription("Start or stop recording (F5)");

        nextSentenceButton = createButton(localCP5, "speechNextSentence", "Next \u2192",
            x + pad + 150, row2Y, 100, 30, p4, 14, colorNotPressed, OPENBCI_DARKBLUE);
        nextSentenceButton.setBorderColor(OBJECT_BORDER_GREY);
        nextSentenceButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { skipToNextSentence(); }
        });
        nextSentenceButton.setDescription("Next sentence (F6)");

        reRecordButton = createButton(localCP5, "speechReRecord", "Re-record \u21BA",
            x + pad + 260, row2Y, 110, 30, p4, 14, colorNotPressed, OPENBCI_DARKBLUE);
        reRecordButton.setBorderColor(OBJECT_BORDER_GREY);
        reRecordButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) { reRecord(); }
        });
        reRecordButton.setDescription("Re-record current sentence/mode (F8)");

        updateButtonStates();
    }

    // =========================================================
    // === Update ===
    // =========================================================
    public void update() {
        super.update();
        updateTrialFlow();
        periodicStreamCheck();
        periodicAutoSave();
        periodicBoardTypeCheck();
    }

    // =========================================================
    // === Draw ===
    // =========================================================
    public void draw() {
        super.draw();
        drawHeader();
        drawControlPanel();
        drawSentenceDisplay();
        drawProgressBar();
        drawStreamingWarning();
        localCP5.draw();

        // Task 17: Help overlay drawn last (on top of everything)
        if (showHelpOverlay) {
            drawHelpOverlay();
        }
    }

    // =========================================================
    // === Periodic Streaming Check ===
    // =========================================================
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
    }

    // =========================================================
    // === Action Lock (Task 20) ===
    // =========================================================
    // Returns true if action is allowed (cooldown has elapsed)
    private boolean acquireActionLock() {
        long now = millis();
        if (now - lastActionTime < ACTION_COOLDOWN_MS) {
            return false; // too soon, reject
        }
        lastActionTime = now;
        return true;
    }

    // =========================================================
    // === Auto-save Progress (Task 21) ===
    // =========================================================
    private void periodicAutoSave() {
        if (!sessionActive || practiceMode) return;
        long now = millis();
        if (now - lastAutoSaveTime < AUTO_SAVE_INTERVAL) return;
        lastAutoSaveTime = now;
        saveProgress();
    }

    private String getAutoSaveFilePath() {
        if (autoSaveFilePath.length() == 0) {
            autoSaveFilePath = directoryManager.getGuiDataPath() + "SpeechExp_autosave.json";
        }
        return autoSaveFilePath;
    }

    private void saveProgress() {
        try {
            JSONObject data = new JSONObject();
            data.setInt("sessionId", sessionId);
            data.setInt("currentSentenceIndex", currentSentenceIndex);
            data.setInt("totalSentences", totalSentences);
            data.setString("csvFilePath", csvFilePath);
            data.setInt("recordingIndex", recordingIndex);
            data.setInt("skippedCount", skippedCount);
            data.setInt("speakingMode", speakingMode);
            data.setInt("trialModeIndex", trialModeIndex);
            data.setInt("parallelPhase", parallelPhase);
            data.setLong("sessionStartTime", sessionStartTime);
            data.setLong("timestamp", System.currentTimeMillis());
            saveJSONObject(data, getAutoSaveFilePath());
        } catch (Exception e) {
            verbosePrint("Speech Experiment: Auto-save failed - " + e.getMessage());
        }
    }

    private void clearAutoSave() {
        try {
            File f = new File(getAutoSaveFilePath());
            if (f.exists()) f.delete();
        } catch (Exception e) {
            // ignore
        }
    }

    // Check if auto-save exists and offer to resume
    public boolean hasAutoSave() {
        try {
            File f = new File(getAutoSaveFilePath());
            return f.exists();
        } catch (Exception e) {
            return false;
        }
    }

    public void loadAutoSave() {
        try {
            JSONObject data = loadJSONObject(getAutoSaveFilePath());
            String savedCsvPath = data.getString("csvFilePath", "");

            if (savedCsvPath.length() == 0) {
                output("Speech Experiment: Auto-save has no CSV path");
                return;
            }

            // Reload the CSV first
            File csvFile = new File(savedCsvPath);
            if (!csvFile.exists()) {
                outputWarn("Speech Experiment: Auto-save CSV not found: " + savedCsvPath);
                return;
            }

            loadSentencesFromFile(csvFile);

            if (sentences.size() == 0) {
                outputWarn("Speech Experiment: Could not reload sentences from auto-save");
                return;
            }

            // Restore state
            sessionId = data.getInt("sessionId", 1);
            currentSentenceIndex = min(data.getInt("currentSentenceIndex", 0), sentences.size() - 1);
            recordingIndex = data.getInt("recordingIndex", 0);
            skippedCount = data.getInt("skippedCount", 0);
            speakingMode = data.getInt("speakingMode", MODE_VOCALIZED);
            trialModeIndex = data.getInt("trialModeIndex", TRIAL_SINGLE);
            parallelPhase = data.getInt("parallelPhase", 0);

            outputSuccess("Speech Experiment: Restored progress - sentence " +
                         (currentSentenceIndex + 1) + "/" + totalSentences +
                         " (Session " + sessionId + ")");
            clearAutoSave();
            updateButtonStates();

        } catch (Exception e) {
            outputError("Speech Experiment: Failed to load auto-save - " + e.getMessage());
        }
    }

    // =========================================================
    // === Board Type Detection (Task 22) ===
    // =========================================================
    private void periodicBoardTypeCheck() {
        // Only check once per stream-check interval (piggyback on same timer)
        if (millis() - lastStreamCheckTime > 100) return; // just ran stream check
        if (currentBoard == null) return;

        String boardName = currentBoard.getClass().getSimpleName();
        isSyntheticBoard = boardName.contains("Synthetic");
        isPlaybackBoard = boardName.contains("Playback");
    }

    // =========================================================
    // === Trial State Machine ===
    // =========================================================
    private void updateTrialFlow() {
        // Expire end-session confirmation if user waited too long
        if (endSessionPending && (millis() - endSessionPendingTime) >= END_SESSION_CONFIRM_MS) {
            endSessionPending = false;
        }

        if (trialState == STATE_IDLE || trialState == STATE_READY) return;

        long now = millis();
        long elapsed = now - stateStartTime;

        switch (trialState) {
            case STATE_BASELINE_START:
                if (elapsed >= BASELINE_DURATION) {
                    stopUtteranceAudio();
                    output("Speech Experiment: Start baseline recorded (" + BASELINE_DURATION + "ms)");
                    transitionTo(STATE_READY);
                    updateButtonStates();
                }
                break;
            case STATE_BASELINE_END:
                if (elapsed >= BASELINE_DURATION) {
                    stopUtteranceAudio();
                    output("Speech Experiment: End baseline recorded (" + BASELINE_DURATION + "ms)");
                    finalizeSession();
                }
                break;
            case STATE_COUNTDOWN:
                if (elapsed >= countdownDuration) {
                    transitionTo(STATE_RECORDING);
                    beginRecording();
                }
                break;
            case STATE_RECORDING:
                if (recordingModeIndex == 2) {
                    if ((now - recordingStartTime) >= timedRecordingDuration) {
                        endRecordingAndAdvance();
                    }
                }
                break;
            case STATE_PAUSE:
                if (elapsed >= currentPauseDuration) {
                    onPauseComplete();
                }
                break;
        }
    }

    private void transitionTo(int newState) {
        trialState = newState;
        stateStartTime = millis();
    }

    private void onPauseComplete() {
        if (parallelPhase == 0 && trialModeIndex != TRIAL_SINGLE) {
            parallelPhase = 1;
            updateSpeakingModeForPhase();
            if (countdownDuration > 0) {
                transitionTo(STATE_COUNTDOWN);
            } else {
                transitionTo(STATE_RECORDING);
                beginRecording();
            }
        } else {
            parallelPhase = 0;
            if (!practiceMode) {
                advanceToNextSentence();
            } else {
                transitionTo(STATE_READY);
                updateSpeakingModeForPhase();
            }

            if (trialState != STATE_IDLE) {
                if (sessionActive && recordingModeIndex == 1 && currentSentenceIndex < sentences.size()) {
                    transitionTo(countdownDuration > 0 ? STATE_COUNTDOWN : STATE_RECORDING);
                    if (countdownDuration == 0) beginRecording();
                } else if (sessionActive) {
                    transitionTo(STATE_READY);
                }
            }
        }
        updateButtonStates();
    }

    private void updateSpeakingModeForPhase() {
        if (trialModeIndex == TRIAL_SINGLE) return;
        if (trialModeIndex == TRIAL_VOCAL_THEN_SILENT) {
            speakingMode = (parallelPhase == 0) ? MODE_VOCALIZED : MODE_SILENT;
        } else if (trialModeIndex == TRIAL_SILENT_THEN_VOCAL) {
            speakingMode = (parallelPhase == 0) ? MODE_SILENT : MODE_VOCALIZED;
        }
    }

    // =========================================================
    // === Core Actions ===
    // =========================================================

    private void loadCsvFile() {
        selectInput("Select CSV file with sentences:", "speechExpCsvSelected");
    }

    private boolean runPreSessionChecklist() {
        ArrayList<String> issues = new ArrayList<String>();
        if (sentences.size() == 0) issues.add("No sentences loaded");

        if (!practiceMode) {
            boolean streaming = (currentBoard != null && currentBoard.isStreaming());
            if (!streaming) issues.add("Board is not streaming - start streaming first");

            if (currentBoard instanceof BoardBrainFlow) {
                if (((DataSource) currentBoard).getMarkerChannel() == -1) {
                    issues.add("No marker channel available on this board");
                }
                String boardName = currentBoard.getClass().getSimpleName();
                if (boardName.contains("Synthetic") || boardName.contains("Playback")) {
                    outputWarn("Speech Experiment: Running on " + boardName + " - markers may not persist");
                }
            }
        }

        if (issues.size() > 0) {
            for (String issue : issues) outputError("Speech Experiment: Checklist FAIL - " + issue);
            return false;
        }
        checklistPassed = true;
        return true;
    }

    private void startSession() {
        if (!runPreSessionChecklist()) return;

        sessionActive = true;
        sessionStartTime = millis();
        currentSentenceIndex = 0;
        currentSentenceStartTime = sessionStartTime;
        parallelPhase = 0;
        recordingIndex = 0;
        skippedCount = 0;
        utteranceCounter = 0;
        sessionLog.clear();
        sessionLogPath = "";
        updateSpeakingModeForPhase();

        // Task 26: Create per-session export directory
        createSessionExportDir();

        // Task 22: Inform about synthetic/playback board
        String boardInfo = "";
        if (isSyntheticBoard) boardInfo = " [Synthetic board - markers for testing only]";
        else if (isPlaybackBoard) boardInfo = " [Playback mode - markers not recorded]";

        String audioInfo = audioAvailable ? " [Mic: " + actualAudioSampleRate + "Hz]" : " [No mic]";
        output("Speech Experiment: Session " + sessionId + " started with " + totalSentences + " sentences"
               + (practiceMode ? " [PRACTICE]" : "") + boardInfo + audioInfo);

        // Task 25: Record start baseline (5s silence)
        startUtteranceAudio("baseline_start");
        transitionTo(STATE_BASELINE_START);

        // Task 21: Initial auto-save with CSV path
        saveProgress();
        updateButtonStates();
    }

    private void pauseSession() {
        if (trialState == STATE_RECORDING) endRecording();
        sessionActive = false;
        transitionTo(STATE_IDLE);
        output("Speech Experiment: Session " + sessionId + " paused at sentence " + (currentSentenceIndex + 1));
        updateButtonStates();
    }

    // Manual end session (F10 double-press) — skips end baseline
    private void endSession() {
        if (trialState == STATE_RECORDING) endRecording();
        stopUtteranceAudio(); // stop any in-progress audio
        finalizeSession();
    }

    // Common finalization — called after end baseline or manual end
    private void finalizeSession() {
        sessionActive = false;
        transitionTo(STATE_IDLE);

        if (!practiceMode && sessionLog.size() > 0) {
            writeSessionLog();
            writeExportConfig(); // Task 24: metadata for Python export script
        }

        closeAudio();
        clearAutoSave();

        // Build summary
        long elapsed = millis() - sessionStartTime;
        int mins = (int)(elapsed / 60000);
        int secs = (int)((elapsed % 60000) / 1000);
        int recorded = sessionLog.size();
        int remaining = totalSentences - currentSentenceIndex;

        String summary = "Speech Experiment: Session " + sessionId + " ended." +
            " Recorded: " + recorded +
            " | Skipped: " + skippedCount +
            " | Remaining: " + remaining +
            " | Duration: " + mins + "m " + secs + "s";
        if (sessionLogPath.length() > 0) summary += " | Log: " + sessionExportDir;
        output(summary);
        updateButtonStates();
    }

    private void handleRecordButton() {
        if (!sessionActive || currentSentenceIndex >= sentences.size()) return;
        if (!acquireActionLock()) return;

        switch (trialState) {
            case STATE_READY:
                transitionTo(countdownDuration > 0 ? STATE_COUNTDOWN : STATE_RECORDING);
                if (countdownDuration == 0) beginRecording();
                break;
            case STATE_COUNTDOWN:
                transitionTo(STATE_READY);
                output("Speech Experiment: Countdown cancelled");
                break;
            case STATE_RECORDING:
                endRecordingAndAdvance();
                break;
            case STATE_PAUSE:
                onPauseComplete();
                break;
        }
        updateButtonStates();
    }

    private void skipToNextSentence() {
        if (!acquireActionLock()) return;
        if (trialState == STATE_RECORDING) endRecording();

        // Task 15: Count skips
        if (sessionActive && currentSentenceIndex < sentences.size() && !practiceMode) {
            skippedCount++;
        }

        parallelPhase = 0;
        advanceToNextSentence();
        if (sessionActive) {
            updateSpeakingModeForPhase();
            transitionTo(STATE_READY);
        }
        updateButtonStates();
    }

    private void reRecord() {
        if (!sessionActive || currentSentenceIndex >= sentences.size()) return;
        if (!acquireActionLock()) return;
        if (trialState == STATE_RECORDING) endRecording();
        transitionTo(STATE_READY);
        output("Speech Experiment: Ready to re-record sentence " + (currentSentenceIndex + 1) +
               " [" + getSpeakingModeStr() + "]");
        updateButtonStates();
    }

    private void beginRecording() {
        if (currentSentenceIndex >= sentences.size()) return;
        currentlyRecording = true;
        recordingStartTime = millis();

        // Task 23: Start per-utterance audio recording
        String sid = sentences.get(currentSentenceIndex).id;
        String audioFilename = sid + "_" + getSpeakingModeStr().toLowerCase();
        startUtteranceAudio(audioFilename);

        if (!practiceMode) {
            int markerValue = computeMarker(currentSentenceIndex, speakingMode, 1);
            boolean markerOk = insertSpeechMarker(markerValue);
            output("Speech Experiment: REC START - " + sid +
                   " [" + getSpeakingModeStr() + "] (Marker: " + markerValue + ")" +
                   (markerOk ? "" : " [MARKER FAILED]"));
        } else {
            output("Speech Experiment: REC START [PRACTICE] - sentence " + (currentSentenceIndex + 1) +
                   " [" + getSpeakingModeStr() + "]");
        }
        updateButtonStates();
    }

    private void endRecording() {
        if (!currentlyRecording) return;
        long duration = millis() - recordingStartTime;

        // Task 23: Stop per-utterance audio
        stopUtteranceAudio();

        if (!practiceMode) {
            int startMarker = computeMarker(currentSentenceIndex, speakingMode, 1);
            int stopMarker = computeMarker(currentSentenceIndex, speakingMode, 2);
            boolean markerOk = insertSpeechMarker(stopMarker);

            String sid = currentSentenceIndex < sentences.size() ? sentences.get(currentSentenceIndex).id : "N/A";
            String sentText = currentSentenceIndex < sentences.size() ? sentences.get(currentSentenceIndex).text : "";
            output("Speech Experiment: REC STOP - " + sid +
                   " [" + getSpeakingModeStr() + "] (" + duration + "ms, Marker: " + stopMarker + ")" +
                   (markerOk ? "" : " [MARKER FAILED]"));

            validateRecordingDuration(duration, sid);

            recordingIndex++;
            sessionLog.add(new SpeechLogEntry(
                sessionId, sid, sentText, getSpeakingModeStr().toLowerCase(),
                startMarker, stopMarker, recordingStartTime, millis(), duration, recordingIndex
            ));
        } else {
            output("Speech Experiment: REC STOP [PRACTICE] (" + duration + "ms)");
            validateRecordingDuration(duration, "practice");
        }

        currentlyRecording = false;
        updateButtonStates();
    }

    private void validateRecordingDuration(long durationMs, String sentenceId) {
        if (durationMs < MIN_RECORDING_DURATION_MS) {
            outputWarn("Speech Experiment: Recording for " + sentenceId +
                       " was very short (" + durationMs + "ms). Consider re-recording.");
        } else if (durationMs > MAX_RECORDING_DURATION_MS) {
            outputWarn("Speech Experiment: Recording for " + sentenceId +
                       " was very long (" + durationMs + "ms). Check if left running.");
        }
    }

    private void endRecordingAndAdvance() {
        endRecording();
        if (parallelPhase == 0 && trialModeIndex != TRIAL_SINGLE) {
            currentPauseDuration = interModePause;
            String nextMode = (trialModeIndex == TRIAL_VOCAL_THEN_SILENT) ? "Silent" : "Vocalized";
            pauseReason = "Switching to " + nextMode + "...";
        } else {
            currentPauseDuration = interSentencePause;
            pauseReason = "Next sentence...";
        }
        transitionTo(STATE_PAUSE);
        updateButtonStates();
    }

    private void advanceToNextSentence() {
        if (!practiceMode) currentSentenceIndex++;
        currentSentenceStartTime = millis();
        if (currentSentenceIndex >= sentences.size()) {
            // Task 25: Record end baseline before finalizing
            startUtteranceAudio("baseline_end");
            transitionTo(STATE_BASELINE_END);
        }
    }

    private void togglePracticeMode() {
        if (trialState == STATE_RECORDING) {
            outputWarn("Speech Experiment: Cannot toggle practice mode while recording");
            return;
        }
        practiceMode = !practiceMode;
        practiceToggleButton.setLabel("Practice: " + (practiceMode ? "ON" : "OFF"));
        practiceToggleButton.setColorBackground(practiceMode ? practiceColor : colorNotPressed);
        output("Speech Experiment: Practice mode " + (practiceMode ? "ON" : "OFF"));
    }

    // =========================================================
    // === Session Log File ===
    // =========================================================
    private void writeSessionLog() {
        if (sessionLog.size() == 0) return;
        try {
            // Save inside session export directory if available, else fallback
            String logDir = (sessionExportDir.length() > 0) ? sessionExportDir : directoryManager.getRecordingsPath();
            String fileName = "session_log.csv";
            sessionLogPath = logDir + fileName;

            File dir = new File(logDir);
            if (!dir.exists()) dir.mkdirs();

            PrintWriter writer = createWriter(sessionLogPath);
            writer.println("session_id,sentence_id,sentence_text,speaking_mode,start_marker,stop_marker,start_timestamp_ms,stop_timestamp_ms,duration_ms,recording_index");

            for (SpeechLogEntry entry : sessionLog) {
                String escapedText = "\"" + entry.sentenceText.replace("\"", "\"\"") + "\"";
                writer.println(
                    entry.sessionId + "," + entry.sentenceId + "," + escapedText + "," +
                    entry.speakingMode + "," + entry.startMarker + "," + entry.stopMarker + "," +
                    entry.startTimestampMs + "," + entry.stopTimestampMs + "," +
                    entry.durationMs + "," + entry.recordingIndex
                );
            }
            writer.flush();
            writer.close();
            outputSuccess("Speech Experiment: Session log saved to " + fileName + " (" + sessionLog.size() + " recordings)");
        } catch (Exception e) {
            outputError("Speech Experiment: Failed to save session log - " + e.getMessage());
            e.printStackTrace();
        }
    }

    // =========================================================
    // === Keyboard Input ===
    // =========================================================
    public void mousePressed() { super.mousePressed(); }
    public void mouseReleased() { super.mouseReleased(); }

    public boolean checkForSpeechKeyPress(char keyPress, int keyCodePress) {
        boolean isCoded = (keyPress == CODED);

        // F1 = toggle help overlay (works even when session not active)
        if (isCoded && keyCodePress == KEY_F1) {
            showHelpOverlay = !showHelpOverlay;
            return true;
        }

        // +/- to adjust font size (always available)
        if (keyPress == '+' || keyPress == '=') {
            sentenceFontSize = min(sentenceFontSize + 2, MAX_FONT_SIZE);
            return true;
        }
        if (keyPress == '-' || keyPress == '_') {
            sentenceFontSize = max(sentenceFontSize - 2, MIN_FONT_SIZE);
            return true;
        }

        if (!isCoded || !sessionActive) return false;

        // Any session key press cancels a pending end-session confirmation
        if (keyCodePress != KEY_F10) {
            endSessionPending = false;
        }

        if (keyCodePress == KEY_F5) { handleRecordButton(); return true; }
        if (keyCodePress == KEY_F6) { skipToNextSentence(); return true; }
        if (keyCodePress == KEY_F7) { pauseSession(); return true; }
        if (keyCodePress == KEY_F8) { reRecord(); return true; }
        if (keyCodePress == KEY_F9) {
            if (trialModeIndex == TRIAL_SINGLE && trialState != STATE_RECORDING) {
                speakingMode = (speakingMode == MODE_SILENT) ? MODE_VOCALIZED : MODE_SILENT;
                output("Speech Experiment: Mode toggled to " + getSpeakingModeStr());
                return true;
            }
        }
        if (keyCodePress == KEY_F10) {
            if (endSessionPending && (millis() - endSessionPendingTime) < END_SESSION_CONFIRM_MS) {
                endSessionPending = false;
                endSession();
            } else {
                endSessionPending = true;
                endSessionPendingTime = millis();
                output("Speech Experiment: Press F10 again to confirm end session");
            }
            return true;
        }
        return false;
    }

    // =========================================================
    // === Drawing ===
    // =========================================================

    private void drawHeader() {
        int headerY = y + navH * 2;

        pushStyle();
        fill(headerBgColor);
        noStroke();
        rect(x, headerY, w, headerHeight);

        // Left: title, session, session timer (Task 14)
        fill(textColor);
        textAlign(LEFT, CENTER);
        textFont(p4, 15);

        String status = "Speech Exp";
        if (csvFilePath.length() > 0) {
            String fileName = csvFilePath;
            int lastSlash = max(csvFilePath.lastIndexOf("/"), csvFilePath.lastIndexOf("\\"));
            if (lastSlash >= 0) fileName = csvFilePath.substring(lastSlash + 1);
            status += " - " + fileName;
        }
        status += "  |  Sess: " + sessionId;
        if (practiceMode) status += " [PRACTICE]";
        // Task 22: Show board type when synthetic/playback
        if (isSyntheticBoard) status += " [SYNTH]";
        else if (isPlaybackBoard) status += " [PLAYBACK]";

        // Task 14: Session elapsed time
        if (sessionActive) {
            long sessionElapsed = millis() - sessionStartTime;
            int sMins = (int)(sessionElapsed / 60000);
            int sSecs = (int)((sessionElapsed % 60000) / 1000);
            status += "  |  " + nf(sMins, 1) + ":" + nf(sSecs, 2);
        }

        text(status, x + 10, headerY + headerHeight / 2);

        // Right: mode + REC
        String modeLabel = getSpeakingModeStr().toUpperCase();
        color modeColor = (speakingMode == MODE_SILENT) ? silentModeColor : vocalizedModeColor;
        int rightEdge = x + w - 10;

        if (currentlyRecording) {
            long recElapsed = millis() - recordingStartTime;
            int secs = (int)(recElapsed / 1000);
            int mins = secs / 60;
            secs = secs % 60;
            String timeStr = nf(mins, 1) + ":" + nf(secs, 2);

            if (((millis() / 500) % 2) == 0) {
                fill(recordingColor);
                noStroke();
                ellipse(rightEdge - 8, headerY + headerHeight / 2, 14, 14);
            }
            fill(textColor);
            textAlign(RIGHT, CENTER);
            textFont(p4, 13);
            text("REC " + timeStr, rightEdge - 20, headerY + headerHeight / 2);

            fill(modeColor);
            textFont(p4, 12);
            text(modeLabel, rightEdge - 110, headerY + headerHeight / 2);
        } else {
            fill(modeColor);
            textAlign(RIGHT, CENTER);
            textFont(p4, 13);
            text(modeLabel, rightEdge, headerY + headerHeight / 2);
        }
        popStyle();
    }

    private void drawControlPanel() {
        int panelY = y + navH * 2 + headerHeight;

        pushStyle();
        fill(controlBgColor);
        noStroke();
        rect(x, panelY, w, controlPanelHeight);

        fill(180);
        textAlign(LEFT, BOTTOM);
        textFont(p5, 11);

        String helpText;
        if (!sessionActive) {
            helpText = "Load CSV and start session to begin  |  F1=Help  +/-=Font size";
        } else {
            helpText = "F5=Record  F6=Next  F7=Pause  F8=Re-record  F9=Mode  F10=End  F1=Help  +/-=Font";
        }
        text(helpText, x + 10, panelY + controlPanelHeight - 5);

        // Task 15: Counters on right side
        if (sessionActive) {
            textAlign(RIGHT, BOTTOM);
            int recorded = sessionLog.size();
            int remaining = totalSentences - currentSentenceIndex;
            String counters = "Rec: " + recorded + "  Skip: " + skippedCount + "  Left: " + remaining;
            if (trialModeIndex != TRIAL_SINGLE) {
                counters += "  Phase: " + (parallelPhase + 1) + "/2";
            }
            text(counters, x + w - 10, panelY + controlPanelHeight - 5);
        }

        popStyle();
    }

    private void drawStreamingWarning() {
        if (!streamingWarningActive) return;
        int bannerY = y + navH * 2 + headerHeight - 18;

        pushStyle();
        fill(warningColor);
        noStroke();
        rect(x, bannerY, w, 18);
        fill(0);
        textAlign(CENTER, CENTER);
        textFont(p5, 11);
        boolean streaming = (currentBoard != null && currentBoard.isStreaming());
        text(streaming ?
            "\u26A0 No marker channel - markers may not be recorded" :
            "\u26A0 Board not streaming - markers will NOT be inserted!",
            x + w / 2, bannerY + 9);
        popStyle();
    }

    private void drawSentenceDisplay() {
        int displayY = y + navH * 2 + headerHeight + controlPanelHeight;
        sentenceDisplayHeight = max(40, h - headerHeight - controlPanelHeight - progressHeight - navH * 2);

        pushStyle();
        fill(sentenceBgColor);
        noStroke();
        rect(x, displayY, w, sentenceDisplayHeight);

        int centerX = x + w / 2;
        int centerY = displayY + sentenceDisplayHeight / 2;

        if (trialState == STATE_BASELINE_START || trialState == STATE_BASELINE_END) {
            drawBaselineOverlay(displayY, centerX, centerY);
        } else if (trialState == STATE_COUNTDOWN) {
            drawCountdownOverlay(displayY, centerX, centerY);
        } else if (trialState == STATE_PAUSE) {
            drawPauseOverlay(displayY, centerX, centerY);
        } else if (sentences.size() > 0 && currentSentenceIndex < sentences.size()) {
            drawSentenceText(displayY, centerX, centerY);
        } else if (!sessionActive && sessionLogPath.length() > 0) {
            // Session ended summary
            drawSessionSummary(centerX, centerY);
        } else if (sessionActive && currentSentenceIndex >= sentences.size()) {
            fill(100, 200, 100);
            textAlign(CENTER, CENTER);
            textFont(p3, 24);
            text("Experiment Complete!", centerX, centerY);
        } else {
            fill(120);
            textAlign(CENTER, CENTER);
            textFont(p4, 16);
            text("Load CSV and start session\nto display sentences", centerX, centerY);
        }
        popStyle();
    }

    // Task 18: Session end summary display
    private void drawSessionSummary(int centerX, int centerY) {
        fill(100, 200, 100);
        textAlign(CENTER, CENTER);
        textFont(p3, 22);
        text("Session " + sessionId + " Complete", centerX, centerY - 50);

        textFont(p4, 16);
        fill(textColor);
        int recorded = sessionLog.size();
        int remaining = totalSentences - currentSentenceIndex;
        text("Recordings: " + recorded + "   Skipped: " + skippedCount + "   Remaining: " + remaining,
             centerX, centerY - 15);

        fill(180);
        textFont(p5, 14);
        if (sessionLogPath.length() > 0) {
            // Show just the filename, not the full path
            String logName = sessionLogPath;
            int lastSlash = max(sessionLogPath.lastIndexOf("/"), sessionLogPath.lastIndexOf("\\"));
            if (lastSlash >= 0) logName = sessionLogPath.substring(lastSlash + 1);
            text("Log saved: " + logName, centerX, centerY + 15);
        }
        text("Press 'Start Session' to begin a new session", centerX, centerY + 40);
    }

    private void drawCountdownOverlay(int displayY, int centerX, int centerY) {
        if (currentSentenceIndex < sentences.size()) {
            SpeechSentenceData current = sentences.get(currentSentenceIndex);
            fill(160);
            textAlign(CENTER, CENTER);
            textFont(p3, sentenceFontSize - 4);
            text(wrapText(current.text, w - 60), centerX, centerY - 40);
        }

        long elapsed = millis() - stateStartTime;
        int remaining = (int) Math.ceil((countdownDuration - elapsed) / 1000.0);
        remaining = max(remaining, 1);

        fill(countdownColor);
        textAlign(CENTER, CENTER);
        textFont(p3, 72);
        text("" + remaining, centerX, centerY + 40);

        fill(180);
        textFont(p4, 18);
        text((speakingMode == MODE_VOCALIZED) ? "Get ready to SPEAK" : "Get ready to THINK",
             centerX, centerY + 85);
    }

    private void drawPauseOverlay(int displayY, int centerX, int centerY) {
        fill(pauseTextColor);
        textAlign(CENTER, CENTER);
        textFont(p3, 22);
        text(pauseReason, centerX, centerY - 20);

        long elapsed = millis() - stateStartTime;
        int remainMs = max(0, currentPauseDuration - (int) elapsed);
        textFont(p4, 16);
        fill(150);
        text(nf(remainMs / 1000.0, 1, 1) + "s", centerX, centerY + 20);
    }

    private void drawSentenceText(int displayY, int centerX, int centerY) {
        SpeechSentenceData current = sentences.get(currentSentenceIndex);

        // Main sentence text
        fill(textColor);
        textAlign(CENTER, CENTER);
        textFont(p3, sentenceFontSize);
        text(wrapText(current.text, w - 60), centerX, centerY - 25);

        // Task 13: Next sentence preview
        if (currentSentenceIndex + 1 < sentences.size()) {
            fill(90);
            textFont(p5, 13);
            textAlign(CENTER, CENTER);
            SpeechSentenceData next = sentences.get(currentSentenceIndex + 1);
            String preview = "Next: " + next.text;
            if (preview.length() > 80) preview = preview.substring(0, 77) + "...";
            text(preview, centerX, displayY + sentenceDisplayHeight - 35);
        }

        // Info line at bottom
        textFont(p5, 13);
        textAlign(CENTER, BOTTOM);
        fill(150);
        String infoLine = "ID: " + current.id + "  |  Mode: " + getSpeakingModeStr();
        if (trialModeIndex != TRIAL_SINGLE) infoLine += "  |  Phase: " + (parallelPhase + 1) + "/2";
        if (current.source.length() > 0) infoLine += "  |  Src: " + current.source;
        // Task 16: Show current font size
        infoLine += "  |  Font: " + sentenceFontSize;
        text(infoLine, centerX, displayY + sentenceDisplayHeight - 12);

        // State indicator at top
        textFont(p5, 13);
        textAlign(CENTER, TOP);
        if (trialState == STATE_READY) {
            fill(180);
            text("Press F5 to start recording", centerX, displayY + 10);
        } else if (trialState == STATE_RECORDING) {
            fill(recordingColor);
            long recElapsed = millis() - recordingStartTime;
            text("RECORDING  " + nf((int)(recElapsed / 1000), 1) + "s", centerX, displayY + 10);
        }
    }

    // Task 17: Help overlay
    private void drawHelpOverlay() {
        int displayY = y + navH * 2 + headerHeight + controlPanelHeight;
        sentenceDisplayHeight = max(40, h - headerHeight - controlPanelHeight - progressHeight - navH * 2);

        pushStyle();
        // Semi-transparent background
        fill(20, 20, 25, 230);
        noStroke();
        rect(x, displayY, w, sentenceDisplayHeight);

        int cx = x + w / 2;
        int topY = displayY + 20;

        fill(countdownColor);
        textAlign(CENTER, TOP);
        textFont(p3, 20);
        text("Keyboard Shortcuts", cx, topY);

        textFont(p4, 15);
        fill(textColor);
        textAlign(LEFT, TOP);

        int col1X = x + w / 4 - 40;
        int col2X = x + w * 3 / 4 - 60;
        int lineH = 22;
        int startY = topY + 35;

        String[][] shortcuts = {
            {"F5", "Start / Stop recording"},
            {"F6", "Next sentence (skip)"},
            {"F7", "Pause session"},
            {"F8", "Re-record current"},
            {"F9", "Toggle Silent/Vocalized"},
            {"F10", "End session (press 2x)"},
            {"F1", "Toggle this help"},
            {"+/-", "Increase/decrease font"},
        };

        for (int i = 0; i < shortcuts.length; i++) {
            int colX = (i < 4) ? col1X : col2X;
            int row = (i < 4) ? i : i - 4;

            fill(countdownColor);
            text(shortcuts[i][0], colX, startY + row * lineH);
            fill(textColor);
            text(shortcuts[i][1], colX + 50, startY + row * lineH);
        }

        // Marker scheme info
        fill(150);
        textFont(p5, 12);
        textAlign(CENTER, TOP);
        int infoY = startY + 4 * lineH + 15;
        text("Marker encoding: (sentIdx+1)*10 + mode*2 + event", cx, infoY);
        text("mode: 0=silent, 1=vocalized  |  event: 1=start, 2=stop", cx, infoY + 16);
        text("Press F1 to close", cx, infoY + 40);

        popStyle();
    }

    private void drawProgressBar() {
        int progressY = y + h - progressHeight;

        pushStyle();
        fill(60);
        noStroke();
        rect(x, progressY, w, progressHeight);

        if (totalSentences > 0) {
            float progress = (float) currentSentenceIndex / totalSentences;
            fill(progressBarColor);
            rect(x, progressY, w * progress, progressHeight);

            fill(textColor);
            textAlign(CENTER, CENTER);
            textFont(p5, 12);
            // Task 15: Richer progress text
            String progressText = currentSentenceIndex + " / " + totalSentences +
                " (" + nf(progress * 100, 1, 1) + "%)";
            if (trialModeIndex != TRIAL_SINGLE && sessionActive && currentSentenceIndex < totalSentences) {
                progressText += "  [" + getSpeakingModeStr() + " " + (parallelPhase + 1) + "/2]";
            }
            text(progressText, x + w / 2, progressY + progressHeight / 2);
        }
        popStyle();
    }

    // =========================================================
    // === Marker Functions ===
    // =========================================================

    private int computeMarker(int sentenceIndex, int mode, int event) {
        return (sentenceIndex + 1) * 10 + mode * 2 + event;
    }

    private int markerToSentenceIndex(int marker) { return (marker / 10) - 1; }
    private int markerToMode(int marker) { return (marker % 10) / 2; }
    private boolean markerIsStart(int marker) { return (marker % 2) == 1; }

    private boolean insertSpeechMarker(int value) {
        if (currentBoard instanceof BoardBrainFlow) {
            int markerChannel = ((DataSource) currentBoard).getMarkerChannel();
            if (markerChannel != -1) {
                ((Board) currentBoard).insertMarker(value);
                return true;
            } else {
                outputWarn("Speech Experiment: Marker channel not available");
                return false;
            }
        } else if (currentBoard != null && currentBoard.isStreaming()) {
            if (currentBoard instanceof Board) {
                ((Board) currentBoard).insertMarker(value);
                return true;
            }
        }
        outputWarn("Speech Experiment: Cannot insert marker - not streaming");
        return false;
    }

    // =========================================================
    // === CSV Loading ===
    // =========================================================

    public void loadSentencesFromFile(File selection) {
        if (selection == null) { output("Speech Experiment: No file selected"); return; }

        csvFilePath = selection.getAbsolutePath();
        sentences.clear();
        lastLoadSkippedRows = 0;

        try {
            String[] lines = loadStrings(csvFilePath);
            if (lines == null || lines.length == 0) {
                outputError("Speech Experiment: Could not read file or file is empty");
                return;
            }
            if (lines[0].length() > 0 && lines[0].charAt(0) == '\uFEFF') {
                lines[0] = lines[0].substring(1);
            }
            if (lines.length < 2) {
                outputError("Speech Experiment: CSV has header but no data rows");
                return;
            }

            String[] headerFields = parseCSVLine(lines[0]);
            int idCol = -1, textCol = -1, sourceCol = -1;
            for (int c = 0; c < headerFields.length; c++) {
                String hdr = headerFields[c].toLowerCase().trim();
                if (hdr.equals("sentence_id") || hdr.equals("id")) idCol = c;
                else if (hdr.equals("sentence_text") || hdr.equals("text") || hdr.equals("sentence")) textCol = c;
                else if (hdr.equals("source")) sourceCol = c;
            }
            if (idCol == -1 || textCol == -1) {
                outputError("Speech Experiment: CSV must have 'sentence_id' and 'sentence_text' columns. Found: " + join(headerFields, ", "));
                return;
            }

            for (int i = 1; i < lines.length; i++) {
                if (lines[i].trim().length() == 0) continue;
                String[] parts = parseCSVLine(lines[i]);
                if (parts.length <= idCol || parts.length <= textCol) { lastLoadSkippedRows++; continue; }
                String id = parts[idCol].trim();
                String txt = parts[textCol].trim();
                String source = (sourceCol >= 0 && sourceCol < parts.length) ? parts[sourceCol].trim() : "";
                if (id.length() == 0 || txt.length() == 0) { lastLoadSkippedRows++; continue; }
                sentences.add(new SpeechSentenceData(id, txt, source));
            }

            totalSentences = sentences.size();
            currentSentenceIndex = 0;
            sessionActive = false;
            trialState = STATE_IDLE;

            String msg = "Speech Experiment: Loaded " + totalSentences + " sentences from " + selection.getName();
            if (lastLoadSkippedRows > 0) msg += " (" + lastLoadSkippedRows + " rows skipped)";
            output(msg);
            updateButtonStates();
        } catch (Exception e) {
            outputError("Speech Experiment: Error loading CSV - " + e.getMessage());
            e.printStackTrace();
        }
    }

    private String[] parseCSVLine(String line) {
        ArrayList<String> fields = new ArrayList<String>();
        boolean inQuotes = false;
        StringBuilder field = new StringBuilder();
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < line.length() && line.charAt(i + 1) == '"') { field.append('"'); i++; }
                    else inQuotes = false;
                } else field.append(c);
            } else {
                if (c == '"') inQuotes = true;
                else if (c == ',') { fields.add(field.toString().trim()); field = new StringBuilder(); }
                else field.append(c);
            }
        }
        fields.add(field.toString().trim());
        return fields.toArray(new String[0]);
    }

    // =========================================================
    // === Utility ===
    // =========================================================

    private String wrapText(String text, float maxWidth) {
        if (text == null || text.length() == 0) return "";
        String[] words = text.split(" ");
        StringBuilder wrapped = new StringBuilder();
        StringBuilder currentLine = new StringBuilder();
        for (String word : words) {
            String testLine = currentLine.length() == 0 ? word : currentLine + " " + word;
            if (textWidth(testLine) > maxWidth && currentLine.length() > 0) {
                wrapped.append(currentLine).append("\n");
                currentLine = new StringBuilder(word);
            } else {
                currentLine = new StringBuilder(testLine);
            }
        }
        if (currentLine.length() > 0) wrapped.append(currentLine);
        return wrapped.toString();
    }

    private String getSpeakingModeStr() {
        return (speakingMode == MODE_SILENT) ? "Silent" : "Vocalized";
    }

    private void updateButtonStates() {
        if (loadCsvButton == null) return;

        boolean hasSentences = sentences.size() > 0;
        boolean inSession = sessionActive && trialState != STATE_IDLE;

        loadCsvButton.setVisible(!sessionActive);
        startSessionButton.setVisible(hasSentences && !sessionActive);
        pauseSessionButton.setVisible(inSession);
        endSessionButton.setVisible(inSession);
        startStopRecButton.setVisible(inSession);
        nextSentenceButton.setVisible(inSession);
        reRecordButton.setVisible(inSession);
        practiceToggleButton.setVisible(true);

        if (trialState == STATE_RECORDING || trialState == STATE_COUNTDOWN) {
            startStopRecButton.setLabel(trialState == STATE_RECORDING ? "Stop Recording" : "Cancel");
            startStopRecButton.setColorBackground(recordingColor);
        } else {
            startStopRecButton.setLabel("Start Recording");
            startStopRecButton.setColorBackground(colorNotPressed);
        }
    }

    // =========================================================
    // === Dropdown Setters ===
    // =========================================================

    public void setRecordingMode(int index) { recordingModeIndex = index; }

    public void setTrialMode(int index) {
        if (trialState == STATE_RECORDING || trialState == STATE_COUNTDOWN) {
            outputWarn("Speech Experiment: Cannot change trial mode during recording");
            return;
        }
        trialModeIndex = index;
        parallelPhase = 0;
        updateSpeakingModeForPhase();
        String[] names = {"Single", "Vocal\u2192Silent", "Silent\u2192Vocal"};
        output("Speech Experiment: Trial mode set to " + names[index]);
    }

    public void setCountdownSetting(int index) {
        countdownSettingIndex = index;
        switch (index) {
            case 0: countdownDuration = 0; break;
            case 1: countdownDuration = 3000; break;
            case 2: countdownDuration = 5000; break;
        }
    }

    public void setSpeakingMode(int index) {
        if (trialState == STATE_RECORDING) {
            outputWarn("Speech Experiment: Cannot change mode while recording");
            return;
        }
        speakingMode = index;
    }

    public void setSessionId(int id) { sessionId = id; }
    public void incrementSessionId() {
        sessionId++;
        output("Speech Experiment: Session ID incremented to " + sessionId);
    }

    // =========================================================
    // === Screen Resize (Task 19) ===
    // =========================================================
    public void screenResized() {
        super.screenResized();

        // Null guard: screenResized() is called on ALL widgets including inactive ones.
        // Buttons may not exist if constructor hasn't completed.
        if (localCP5 == null || loadCsvButton == null) return;

        localCP5.setGraphics(ourApplet, 0, 0);

        int bW = 120;
        int bH = 24;
        int pad = 10;
        int row1Y = y + navH * 2 + 10;
        int row2Y = row1Y + bH + 10;

        loadCsvButton.setPosition(x + pad, row1Y);
        startSessionButton.setPosition(x + pad + bW + 10, row1Y);
        pauseSessionButton.setPosition(x + pad + (bW + 10) * 2, row1Y);
        endSessionButton.setPosition(x + pad + (bW + 10) * 2 + 90, row1Y);
        practiceToggleButton.setPosition(x + pad + (bW + 10) * 2 + 200, row1Y);
        startStopRecButton.setPosition(x + pad, row2Y);
        nextSentenceButton.setPosition(x + pad + 150, row2Y);
        reRecordButton.setPosition(x + pad + 260, row2Y);

        // Clamp to minimum usable height to avoid negative dimensions
        sentenceDisplayHeight = max(40, h - headerHeight - controlPanelHeight - progressHeight - navH * 2);
    }

    // =========================================================
    // === Audio Recording (Task 23) ===
    // =========================================================
    private void initAudio() {
        try {
            minim = new Minim(ourApplet);
            // Try 16kHz mono; fall back to default if unsupported
            try {
                micInput = minim.getLineIn(Minim.MONO, 1024, 16000);
                actualAudioSampleRate = 16000;
            } catch (Exception e) {
                micInput = minim.getLineIn(Minim.MONO, 1024);
                actualAudioSampleRate = 44100; // Minim default
                verbosePrint("Speech Experiment: 16kHz not supported, using default sample rate");
            }
            audioAvailable = (micInput != null);
            if (audioAvailable) {
                verbosePrint("Speech Experiment: Microphone initialized at " + actualAudioSampleRate + "Hz");
            }
        } catch (Exception e) {
            audioAvailable = false;
            verbosePrint("Speech Experiment: No microphone available - " + e.getMessage());
        }
    }

    private void startUtteranceAudio(String filename) {
        if (!audioAvailable || micInput == null) return;
        try {
            // Stop any prior recorder
            stopUtteranceAudio();

            String wavPath = audioRawDir + filename + ".wav";
            currentAudioRecorder = minim.createRecorder(micInput, wavPath);
            currentAudioRecorder.beginRecord();
            utteranceCounter++;
            verbosePrint("Speech Experiment: Audio recording started -> " + filename + ".wav");
        } catch (Exception e) {
            verbosePrint("Speech Experiment: Audio start failed - " + e.getMessage());
            currentAudioRecorder = null;
        }
    }

    private void stopUtteranceAudio() {
        if (currentAudioRecorder == null) return;
        try {
            currentAudioRecorder.endRecord();
            currentAudioRecorder.save();
            verbosePrint("Speech Experiment: Audio saved");
        } catch (Exception e) {
            verbosePrint("Speech Experiment: Audio save failed - " + e.getMessage());
        }
        currentAudioRecorder = null;
    }

    private void closeAudio() {
        stopUtteranceAudio();
        if (micInput != null) {
            try { micInput.close(); } catch (Exception e) { /* ignore */ }
            micInput = null;
        }
        // Don't close minim itself — it's shared with the PApplet lifecycle
    }

    // =========================================================
    // === Export Directory & Config (Tasks 24-28) ===
    // =========================================================
    private void createSessionExportDir() {
        String timestamp = new SimpleDateFormat("yyyy-MM-dd_HH-mm-ss").format(new Date());
        sessionExportDir = directoryManager.getRecordingsPath() +
            "SpeechExp_Session" + sessionId + "_" + timestamp + File.separator;
        audioRawDir = sessionExportDir + "audio_raw" + File.separator;

        try {
            new File(sessionExportDir).mkdirs();
            new File(audioRawDir).mkdirs();
            verbosePrint("Speech Experiment: Export dir created: " + sessionExportDir);
        } catch (Exception e) {
            outputError("Speech Experiment: Failed to create export directory - " + e.getMessage());
        }
    }

    private void writeExportConfig() {
        if (sessionExportDir.length() == 0) return;
        try {
            JSONObject config = new JSONObject();

            // Session metadata
            config.setInt("session_id", sessionId);
            config.setString("csv_file_path", csvFilePath);
            config.setInt("total_sentences", totalSentences);
            config.setInt("sentences_completed", currentSentenceIndex);
            config.setInt("recordings_count", sessionLog.size());
            config.setInt("skipped_count", skippedCount);

            // Trial mode
            String[] trialNames = {"single", "vocal_then_silent", "silent_then_vocal"};
            config.setString("trial_mode", trialNames[min(trialModeIndex, 2)]);

            // Board/EMG info
            int sampleRate = 250; // default
            int numChannels = 8;  // default
            try {
                if (currentBoard != null) {
                    sampleRate = currentBoard.getSampleRate();
                    numChannels = currentBoard.getNumEXGChannels();
                }
            } catch (Exception e) { /* use defaults */ }
            config.setInt("emg_sample_rate_hz", sampleRate);
            config.setInt("emg_num_channels", numChannels);
            config.setString("board_type", currentBoard != null ? currentBoard.getClass().getSimpleName() : "unknown");

            // Audio info
            config.setBoolean("audio_available", audioAvailable);
            config.setInt("audio_sample_rate_hz", actualAudioSampleRate);
            config.setString("audio_format", "wav");
            config.setString("audio_dir", "audio_raw");

            // Marker encoding reference
            config.setString("marker_encoding", "(sentence_index+1)*10 + mode*2 + event");
            config.setString("marker_mode_0", "silent");
            config.setString("marker_mode_1", "vocalized");
            config.setString("marker_event_1", "start");
            config.setString("marker_event_2", "stop");

            // Task 27: Document sampling rate difference
            config.setInt("gaddy_original_sample_rate_hz", 1000);
            config.setInt("gaddy_target_resample_hz", 800);
            if (sampleRate == 1000) {
                config.setString("sampling_rate_note",
                    "Sample rate matches Gaddy & Klein (2020) at 1000Hz. " +
                    "No resampling adjustments needed in read_emg.py.");
            } else {
                config.setString("sampling_rate_note",
                    "OpenBCI records at " + sampleRate + "Hz, not 1000Hz as in Gaddy & Klein (2020). " +
                    "Cyton serial (USB dongle/Bluetooth) is limited to 250Hz. " +
                    "Cyton WiFi Shield supports 250/500/1000/2000/4000/8000/16000Hz. " +
                    "The ML pipeline (read_emg.py) resamples from 1000Hz to 800Hz. " +
                    "For " + sampleRate + "Hz data, adjust resampling: upsample to 800Hz or modify " +
                    "conv downsampling factors in the model architecture.");
            }

            // Task 28: clean_audio flag
            config.setBoolean("needs_clean_audio", true);
            config.setString("clean_audio_note",
                "Run clean_audio.py from the Gaddy pipeline on the exported audio " +
                "to remove silence and normalize levels before training.");

            // Baseline info
            config.setInt("baseline_duration_ms", (int) BASELINE_DURATION);
            config.setString("baseline_start_audio", "audio_raw/baseline_start.wav");
            config.setString("baseline_end_audio", "audio_raw/baseline_end.wav");

            // Session log reference
            config.setString("session_log", "session_log.csv");

            // BrainFlow data file hint (user needs to locate this)
            config.setString("brainflow_data_note",
                "Locate the BrainFlow-RAW CSV file from this recording session. " +
                "It is typically in the same Recordings directory or a subfolder. " +
                "The marker channel in that CSV contains the integer markers from this experiment.");

            // Gaddy directory structure reference
            config.setString("export_structure_note",
                "Run the companion export_gaddy.py script to convert this session " +
                "into the Gaddy-compatible directory structure: " +
                "silent_parallel_data/, voiced_parallel_data/, nonparallel_data/");

            String configPath = sessionExportDir + "export_config.json";
            saveJSONObject(config, configPath);
            outputSuccess("Speech Experiment: Export config saved to export_config.json");

        } catch (Exception e) {
            outputError("Speech Experiment: Failed to write export config - " + e.getMessage());
            e.printStackTrace();
        }
    }

    // =========================================================
    // === Baseline Overlay Drawing (Task 25) ===
    // =========================================================
    private void drawBaselineOverlay(int displayY, int centerX, int centerY) {
        boolean isStart = (trialState == STATE_BASELINE_START);
        long elapsed = millis() - stateStartTime;
        int remainSec = max(0, (int) Math.ceil((BASELINE_DURATION - elapsed) / 1000.0));

        // Pulsing recording indicator
        float pulse = 0.5 + 0.5 * sin(millis() * 0.005);
        fill(lerpColor(color(60, 60, 80), recordingColor, pulse));
        textAlign(CENTER, CENTER);
        textFont(p3, 26);
        text(isStart ? "Recording Baseline Silence" : "Recording End Baseline", centerX, centerY - 30);

        fill(countdownColor);
        textFont(p3, 64);
        text("" + remainSec, centerX, centerY + 30);

        fill(180);
        textFont(p4, 16);
        text("Please remain still and silent", centerX, centerY + 75);

        if (audioAvailable) {
            fill(practiceColor);
            textFont(p5, 12);
            text("Microphone active", centerX, centerY + 100);
        }
    }

    // =========================================================
    // === Public Accessors ===
    // =========================================================
    public boolean isSessionActive() { return sessionActive; }
    public boolean isRecording() { return currentlyRecording; }
    public int getSessionId() { return sessionId; }
    public int getSpeakingMode() { return speakingMode; }
    public int getTrialState() { return trialState; }
    public boolean isPracticeMode() { return practiceMode; }
    public String getSessionLogPath() { return sessionLogPath; }
    public int getRecordingCount() { return sessionLog.size(); }
    public int getSkippedCount() { return skippedCount; }
    public String getSessionExportDir() { return sessionExportDir; }
    public boolean isAudioAvailable() { return audioAvailable; }
}

// =========================================================
// === Session Log Entry ===
// =========================================================
class SpeechLogEntry {
    int sessionId;
    String sentenceId;
    String sentenceText;
    String speakingMode;
    int startMarker;
    int stopMarker;
    long startTimestampMs;
    long stopTimestampMs;
    long durationMs;
    int recordingIndex;

    SpeechLogEntry(int _sessionId, String _sentenceId, String _sentenceText,
                   String _speakingMode, int _startMarker, int _stopMarker,
                   long _startTs, long _stopTs, long _duration, int _recIdx) {
        this.sessionId = _sessionId;
        this.sentenceId = _sentenceId;
        this.sentenceText = _sentenceText;
        this.speakingMode = _speakingMode;
        this.startMarker = _startMarker;
        this.stopMarker = _stopMarker;
        this.startTimestampMs = _startTs;
        this.stopTimestampMs = _stopTs;
        this.durationMs = _duration;
        this.recordingIndex = _recIdx;
    }
}

// =========================================================
// === Data Class ===
// =========================================================
class SpeechSentenceData {
    String id;
    String text;
    String source;

    SpeechSentenceData(String _id, String _text, String _source) {
        this.id = _id.trim();
        this.text = _text.trim();
        this.source = _source.trim();
    }
}

// =========================================================
// === Global Callbacks ===
// =========================================================
void speechExpCsvSelected(File selection) {
    if (w_speechExperiment != null) w_speechExperiment.loadSentencesFromFile(selection);
}

void SpeechRecMode(int n) {
    if (w_speechExperiment != null) w_speechExperiment.setRecordingMode(n);
}

void SpeechTrialMode(int n) {
    if (w_speechExperiment != null) w_speechExperiment.setTrialMode(n);
}

void SpeechCountdown(int n) {
    if (w_speechExperiment != null) w_speechExperiment.setCountdownSetting(n);
}

void SpeechSpeakMode(int n) {
    if (w_speechExperiment != null) w_speechExperiment.setSpeakingMode(n);
}

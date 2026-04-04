//////////////////////////////////////////////////////
//                                                  //
//          W_SpeechExperiment.pde                  //
//                                                  //
//  Speech Data Collection Experiment Widget        //
//                                                  //
//  Purpose: Load sentences from CSV, display them  //
//  with large text, control recording with         //
//  automatic marker insertion, track progress      //
//                                                  //
//  Markers: START = n.1, STOP = n.2                //
//  Shortcuts: S=record, D=next, P=pause            //
//                                                  //
//////////////////////////////////////////////////////

class W_SpeechExperiment extends Widget {
    
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
    
    // === Experiment State ===
    private ArrayList<SpeechSentenceData> sentences;
    private int currentSentenceIndex = 0;
    private boolean sessionActive = false;
    private boolean currentlyRecording = false;
    private String csvFilePath = "";
    private int totalSentences = 0;
    private long sessionStartTime = 0;
    
    // === Recording Mode ===
    private int recordingModeIndex = 0; // 0=Manual, 1=Continuous, 2=Timed
    private int timedRecordingDuration = 5000; // 5 seconds default
    
    // === Timing ===
    private long recordingStartTime = 0;
    private long currentSentenceStartTime = 0;
    private long autoStartDelay = 0;
    
    // === Display Settings ===
    private int sentenceFontSize = 28;
    private color backgroundColor = color(40, 40, 40);
    private color textColor = color(255, 255, 255);
    private color progressBarColor = color(100, 150, 200);
    private color recordingColor = color(220, 50, 50);
    private color headerBgColor = color(50, 50, 55);
    private color controlBgColor = color(45, 45, 50);
    private color sentenceBgColor = color(30, 30, 35);
    
    // === Constructor ===
    W_SpeechExperiment(PApplet _parent) {
        super(_parent);
        
        sentences = new ArrayList<SpeechSentenceData>();
        
        // Calculate initial layout
        sentenceDisplayHeight = h - headerHeight - controlPanelHeight - progressHeight - navH*2;
        
        // Setup dropdown for recording mode
        addDropdown("SpeechRecMode", "Mode", Arrays.asList("Manual", "Continuous", "Timed (5s)"), 0);
        
        // Create local ControlP5 instance
        localCP5 = new ControlP5(ourApplet);
        localCP5.setGraphics(ourApplet, 0, 0);
        localCP5.setAutoDraw(false);
        
        createButtons();
    }
    
    // === Create UI Buttons ===
    private void createButtons() {
        int buttonW = 120;
        int buttonH = 24;
        int buttonPadding = 10;
        int buttonY = y + navH*2 + 10;
        
        // Load CSV Button
        loadCsvButton = createButton(localCP5, "speechLoadCsv", "Load CSV", 
            x + buttonPadding, buttonY, buttonW, buttonH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        loadCsvButton.setBorderColor(OBJECT_BORDER_GREY);
        loadCsvButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                loadCsvFile();
            }
        });
        loadCsvButton.setDescription("Load a CSV file containing sentences for the experiment");
        
        // Start Session Button
        startSessionButton = createButton(localCP5, "speechStartSession", "Start Session", 
            x + buttonPadding + buttonW + 10, buttonY, buttonW, buttonH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        startSessionButton.setBorderColor(OBJECT_BORDER_GREY);
        startSessionButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                startSession();
            }
        });
        startSessionButton.setDescription("Start the experiment session");
        
        // Pause Session Button
        pauseSessionButton = createButton(localCP5, "speechPauseSession", "Pause", 
            x + buttonPadding + (buttonW + 10) * 2, buttonY, 80, buttonH, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        pauseSessionButton.setBorderColor(OBJECT_BORDER_GREY);
        pauseSessionButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                pauseSession();
            }
        });
        pauseSessionButton.setDescription("Pause the current session");
        
        // Start/Stop Recording Button
        int recButtonY = buttonY + buttonH + 10;
        startStopRecButton = createButton(localCP5, "speechToggleRec", "Start Recording", 
            x + buttonPadding, recButtonY, 140, 30, p4, 14, colorNotPressed, OPENBCI_DARKBLUE);
        startStopRecButton.setBorderColor(OBJECT_BORDER_GREY);
        startStopRecButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                toggleRecording();
            }
        });
        startStopRecButton.setDescription("Start or stop recording for the current sentence (Shortcut: S)");
        
        // Next Sentence Button
        nextSentenceButton = createButton(localCP5, "speechNextSentence", "Next →", 
            x + buttonPadding + 150, recButtonY, 100, 30, p4, 14, colorNotPressed, OPENBCI_DARKBLUE);
        nextSentenceButton.setBorderColor(OBJECT_BORDER_GREY);
        nextSentenceButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                nextSentence();
            }
        });
        nextSentenceButton.setDescription("Move to the next sentence (Shortcut: D)");
        
        updateButtonStates();
    }
    
    // === Update Method ===
    public void update() {
        super.update();
        
        // Handle automatic recording modes
        handleAutomaticRecording();
    }
    
    // === Draw Method ===
    public void draw() {
        super.draw();
        
        // Draw custom widget content
        drawHeader();
        drawControlPanel();
        drawSentenceDisplay();
        drawProgressBar();
        
        // Draw CP5 elements
        localCP5.draw();
    }
    
    // === Header Section ===
    private void drawHeader() {
        int headerY = y + navH * 2;
        
        // Header background
        pushStyle();
        fill(headerBgColor);
        noStroke();
        rect(x, headerY, w, headerHeight);
        
        // Title and status
        fill(textColor);
        textAlign(LEFT, CENTER);
        textFont(p4, 16);
        
        String status = "Speech Experiment";
        if (csvFilePath.length() > 0) {
            String fileName = csvFilePath;
            int lastSlash = max(csvFilePath.lastIndexOf("/"), csvFilePath.lastIndexOf("\\"));
            if (lastSlash >= 0) {
                fileName = csvFilePath.substring(lastSlash + 1);
            }
            status += " - " + fileName;
        }
        if (sessionActive) {
            status += " [ACTIVE]";
        }
        
        text(status, x + 10, headerY + headerHeight / 2);
        
        // Recording indicator
        if (currentlyRecording) {
            fill(recordingColor);
            noStroke();
            ellipse(x + w - 25, headerY + headerHeight / 2, 18, 18);
            fill(textColor);
            textAlign(RIGHT, CENTER);
            textFont(p4, 14);
            text("REC", x + w - 40, headerY + headerHeight / 2);
        }
        
        popStyle();
    }
    
    // === Control Panel Section ===
    private void drawControlPanel() {
        int panelY = y + navH * 2 + headerHeight;
        
        pushStyle();
        fill(controlBgColor);
        noStroke();
        rect(x, panelY, w, controlPanelHeight);
        
        // Help text at bottom of control panel
        fill(180);
        textAlign(LEFT, BOTTOM);
        textFont(p5, 11);
        
        String helpText;
        if (!sessionActive) {
            helpText = "Load CSV file and start session to begin the experiment";
        } else {
            helpText = "Shortcuts: S = Start/Stop Recording | D = Next Sentence | P = Pause";
        }
        
        text(helpText, x + 10, panelY + controlPanelHeight - 5);
        popStyle();
    }
    
    // === Sentence Display Section ===
    private void drawSentenceDisplay() {
        int displayY = y + navH * 2 + headerHeight + controlPanelHeight;
        sentenceDisplayHeight = h - headerHeight - controlPanelHeight - progressHeight - navH * 2;
        
        pushStyle();
        // Background
        fill(sentenceBgColor);
        noStroke();
        rect(x, displayY, w, sentenceDisplayHeight);
        
        if (sentences.size() > 0 && currentSentenceIndex < sentences.size()) {
            SpeechSentenceData current = sentences.get(currentSentenceIndex);
            
            // Center the sentence text
            fill(textColor);
            textAlign(CENTER, CENTER);
            textFont(p3, sentenceFontSize);
            
            // Word wrap for long sentences
            String wrappedText = wrapText(current.text, w - 60);
            text(wrappedText, x + w/2, displayY + sentenceDisplayHeight/2 - 20);
            
            // Sentence ID and source at bottom
            textFont(p5, 14);
            textAlign(CENTER, BOTTOM);
            fill(150);
            text("ID: " + current.id + " | Source: " + current.source, 
                 x + w/2, displayY + sentenceDisplayHeight - 15);
                 
        } else if (sessionActive && currentSentenceIndex >= sentences.size()) {
            // Experiment complete
            fill(100, 200, 100);
            textAlign(CENTER, CENTER);
            textFont(p3, 24);
            text("Experiment Complete!", x + w/2, displayY + sentenceDisplayHeight/2 - 15);
            
            textFont(p4, 16);
            fill(180);
            text("All " + totalSentences + " sentences have been recorded.", 
                 x + w/2, displayY + sentenceDisplayHeight/2 + 25);
        } else {
            // Not started
            fill(120);
            textAlign(CENTER, CENTER);
            textFont(p4, 16);
            text("Load CSV and start session\nto display sentences", 
                 x + w/2, displayY + sentenceDisplayHeight/2);
        }
        popStyle();
    }
    
    // === Progress Bar Section ===
    private void drawProgressBar() {
        int progressY = y + h - progressHeight;
        
        pushStyle();
        // Background
        fill(60);
        noStroke();
        rect(x, progressY, w, progressHeight);
        
        if (totalSentences > 0) {
            // Calculate progress
            float progress = (float)currentSentenceIndex / totalSentences;
            
            // Progress bar fill
            fill(progressBarColor);
            rect(x, progressY, w * progress, progressHeight);
            
            // Progress text
            fill(textColor);
            textAlign(CENTER, CENTER);
            textFont(p5, 12);
            String progressText = currentSentenceIndex + " / " + totalSentences;
            progressText += " (" + nf(progress * 100, 1, 1) + "%)";
            text(progressText, x + w/2, progressY + progressHeight/2);
        }
        popStyle();
    }
    
    // === Core Functions ===
    
    private void loadCsvFile() {
        selectInput("Select CSV file with sentences:", "speechExpCsvSelected");
    }
    
    private void startSession() {
        if (sentences.size() == 0) {
            output("Speech Experiment: No sentences loaded. Please load a CSV file first.");
            return;
        }
        
        sessionActive = true;
        sessionStartTime = System.currentTimeMillis();
        currentSentenceIndex = 0;
        currentSentenceStartTime = sessionStartTime;
        
        output("Speech Experiment: Session started with " + totalSentences + " sentences");
        updateButtonStates();
    }
    
    private void pauseSession() {
        if (currentlyRecording) {
            stopRecording();
        }
        sessionActive = false;
        
        output("Speech Experiment: Session paused at sentence " + (currentSentenceIndex + 1));
        updateButtonStates();
    }
    
    private void toggleRecording() {
        if (!sessionActive || currentSentenceIndex >= sentences.size()) {
            return;
        }
        
        if (currentlyRecording) {
            stopRecording();
        } else {
            startRecording();
        }
    }
    
    private void startRecording() {
        if (!sessionActive || currentSentenceIndex >= sentences.size()) {
            return;
        }
        
        currentlyRecording = true;
        recordingStartTime = System.currentTimeMillis();
        
        // Insert START marker
        float markerValue = getStartMarkerValue(currentSentenceIndex);
        insertSpeechMarker(markerValue);
        
        String sentenceId = sentences.get(currentSentenceIndex).id;
        output("Speech Experiment: Recording started - " + sentenceId + " (Marker: " + nf(markerValue, 1, 1) + ")");
        updateButtonStates();
    }
    
    private void stopRecording() {
        if (!currentlyRecording) {
            return;
        }
        
        // Insert STOP marker
        float markerValue = getStopMarkerValue(currentSentenceIndex);
        insertSpeechMarker(markerValue);
        
        currentlyRecording = false;
        
        long duration = System.currentTimeMillis() - recordingStartTime;
        String sentenceId = currentSentenceIndex < sentences.size() ? 
            sentences.get(currentSentenceIndex).id : "N/A";
        output("Speech Experiment: Recording stopped - " + sentenceId + 
               " (Duration: " + duration + "ms, Marker: " + nf(markerValue, 1, 1) + ")");
        updateButtonStates();
    }
    
    private void nextSentence() {
        // Stop recording if active
        if (currentlyRecording) {
            stopRecording();
        }
        
        // Advance to next sentence
        if (currentSentenceIndex < sentences.size()) {
            currentSentenceIndex++;
            currentSentenceStartTime = System.currentTimeMillis();
            
            // For continuous mode, set up auto-start
            if (recordingModeIndex == 1 && currentSentenceIndex < sentences.size()) {
                autoStartDelay = System.currentTimeMillis() + 500; // 0.5s delay
            }
            
            if (currentSentenceIndex < sentences.size()) {
                output("Speech Experiment: Advanced to sentence " + (currentSentenceIndex + 1) + 
                       " / " + totalSentences);
            } else {
                sessionActive = false;
                output("Speech Experiment: All sentences completed!");
            }
        }
        
        updateButtonStates();
    }
    
    // === Keyboard Input ===
    public void mousePressed() {
        super.mousePressed();
    }
    
    public void mouseReleased() {
        super.mouseReleased();
    }
    
    // Called from Interactivity.pde when a key is pressed
    // Returns true if a speech experiment key was pressed, false otherwise
    public boolean checkForSpeechKeyPress(char keyPress, int keyCodePress) {
        if (!sessionActive) {
            return false;
        }
        
        // 's' or 'S' for start/stop recording (using different key than spacebar which controls streaming)
        if (keyPress == 's' || keyPress == 'S') {
            toggleRecording();
            return true;
        }
        
        // 'd' or 'D' for next sentence (think "done" with current sentence)
        if (keyPress == 'd' || keyPress == 'D') {
            nextSentence();
            return true;
        }
        
        // 'p' or 'P' for pause
        if (keyPress == 'p' || keyPress == 'P') {
            pauseSession();
            return true;
        }
        
        return false;
    }

    // Global keyPressed handler is in the global function below
    
    // === Automatic Recording Modes ===
    private void handleAutomaticRecording() {
        if (!sessionActive || currentSentenceIndex >= sentences.size()) {
            return;
        }
        
        long currentTime = System.currentTimeMillis();
        
        // Continuous mode: auto-start after delay
        if (recordingModeIndex == 1) {
            if (!currentlyRecording && autoStartDelay > 0 && currentTime > autoStartDelay) {
                autoStartDelay = 0;
                startRecording();
            }
        }
        // Timed mode: auto-stop after duration
        else if (recordingModeIndex == 2) {
            if (currentlyRecording && 
                (currentTime - recordingStartTime) > timedRecordingDuration) {
                stopRecording();
            }
        }
    }
    
    // === Marker Functions ===
    private float getStartMarkerValue(int sentenceIndex) {
        return (sentenceIndex + 1) + 0.1f; // S1 = 1.1, S2 = 2.1, etc.
    }
    
    private float getStopMarkerValue(int sentenceIndex) {
        return (sentenceIndex + 1) + 0.2f; // S1 = 1.2, S2 = 2.2, etc.
    }
    
    private void insertSpeechMarker(float value) {
        if (currentBoard != null && currentBoard.isStreaming()) {
            if (currentBoard instanceof Board) {
                ((Board)currentBoard).insertMarker(value);
            }
        } else {
            verbosePrint("Speech Experiment: Warning - Cannot insert marker, not streaming");
        }
    }
    
    // === Utility Functions ===
    
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
        
        if (currentLine.length() > 0) {
            wrapped.append(currentLine);
        }
        
        return wrapped.toString();
    }
    
    public void loadSentencesFromFile(File selection) {
        if (selection == null) {
            output("Speech Experiment: No file selected");
            return;
        }
        
        csvFilePath = selection.getAbsolutePath();
        sentences.clear();
        
        try {
            String[] lines = loadStrings(csvFilePath);
            
            if (lines == null || lines.length < 2) {
                output("Speech Experiment: CSV file is empty or invalid");
                return;
            }
            
            // Skip header row, parse data rows
            for (int i = 1; i < lines.length; i++) {
                if (lines[i].trim().length() == 0) continue;
                
                String[] parts = parseCSVLine(lines[i]);
                if (parts.length >= 3) {
                    sentences.add(new SpeechSentenceData(parts[0], parts[1], parts[2]));
                } else if (parts.length == 2) {
                    sentences.add(new SpeechSentenceData(parts[0], parts[1], ""));
                }
            }
            
            totalSentences = sentences.size();
            currentSentenceIndex = 0;
            sessionActive = false;
            
            output("Speech Experiment: Loaded " + totalSentences + " sentences from " + 
                   selection.getName());
            updateButtonStates();
            
        } catch (Exception e) {
            output("Speech Experiment: Error loading CSV - " + e.getMessage());
            println("SpeechExperiment CSV Error: " + e.getMessage());
        }
    }
    
    private String[] parseCSVLine(String line) {
        ArrayList<String> fields = new ArrayList<String>();
        boolean inQuotes = false;
        StringBuilder field = new StringBuilder();
        
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            
            if (c == '"') {
                inQuotes = !inQuotes;
            } else if (c == ',' && !inQuotes) {
                fields.add(field.toString().trim().replaceAll("^\"|\"$", ""));
                field = new StringBuilder();
            } else {
                field.append(c);
            }
        }
        
        fields.add(field.toString().trim().replaceAll("^\"|\"$", ""));
        return fields.toArray(new String[0]);
    }
    
    private void updateButtonStates() {
        if (loadCsvButton == null) return;
        
        // Show/hide buttons based on state
        boolean hasSentences = sentences.size() > 0;
        
        startSessionButton.setVisible(hasSentences && !sessionActive);
        pauseSessionButton.setVisible(sessionActive);
        startStopRecButton.setVisible(sessionActive);
        nextSentenceButton.setVisible(sessionActive);
        
        // Update recording button label
        if (currentlyRecording) {
            startStopRecButton.setLabel("Stop Recording");
            startStopRecButton.setColorBackground(recordingColor);
        } else {
            startStopRecButton.setLabel("Start Recording");
            startStopRecButton.setColorBackground(colorNotPressed);
        }
    }
    
    // === Screen Resize Handler ===
    public void screenResized() {
        super.screenResized();
        
        localCP5.setGraphics(ourApplet, 0, 0);
        
        // Recalculate positions
        int buttonW = 120;
        int buttonH = 24;
        int buttonPadding = 10;
        int buttonY = y + navH*2 + 10;
        int recButtonY = buttonY + buttonH + 10;
        
        loadCsvButton.setPosition(x + buttonPadding, buttonY);
        startSessionButton.setPosition(x + buttonPadding + buttonW + 10, buttonY);
        pauseSessionButton.setPosition(x + buttonPadding + (buttonW + 10) * 2, buttonY);
        startStopRecButton.setPosition(x + buttonPadding, recButtonY);
        nextSentenceButton.setPosition(x + buttonPadding + 150, recButtonY);
        
        sentenceDisplayHeight = h - headerHeight - controlPanelHeight - progressHeight - navH * 2;
    }
    
    // Public methods for external access
    public boolean isSessionActive() {
        return sessionActive;
    }
    
    public boolean isRecording() {
        return currentlyRecording;
    }
}

// === Data Class ===
class SpeechSentenceData {
    String id;
    String text;
    String source;
    
    SpeechSentenceData(String _id, String _text, String _source) {
        this.id = _id.trim().replaceAll("^\"|\"$", "");
        this.text = _text.trim().replaceAll("^\"|\"$", "");
        this.source = _source.trim().replaceAll("^\"|\"$", "");
    }
}

// === Global callback function for file selection ===
void speechExpCsvSelected(File selection) {
    if (w_speechExperiment != null) {
        w_speechExperiment.loadSentencesFromFile(selection);
    }
}

// === Global dropdown callback ===
void SpeechRecMode(int n) {
    if (w_speechExperiment != null) {
        // Update recording mode based on dropdown selection
        // This is handled internally via the dropdown index
        verbosePrint("Speech Experiment: Recording mode changed to " + n);
    }
}

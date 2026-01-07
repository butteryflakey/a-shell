//
//  SceneDelegate+TerminalView.swift
//  a-Shell
//
//  Created by Nicolas Holzschuch on 24/12/2025.
//  Copyright © 2025 AsheKube. All rights reserved.
//
import SwiftTerm // for the terminal window
import ios_system
import TipKit // for helpful tips

var autocompleteRunning = false
var autocompleteSuggestions: [String] = []
var autocompletePosition = 0
// variables for user interaction with SwiftTerm:
var commandBeforeCursor = ""
var commandAfterCursor = ""

extension SceneDelegate {
    
    func longestCommonPrefix(_ strs: [String]) -> String {
        guard let first = strs.first else { return "" }
        
        var prefix = first
        
        for str in strs {
            while !str.hasPrefix(prefix) {
                prefix = String(prefix.dropLast())
                if prefix.isEmpty { return "" }
            }
        }
        
        return prefix
    }
    
    func fillAutocompleteSuggestions(command: String) -> String {
        autocompleteSuggestions = []
        autocompletePosition = 0
        if (currentCommand != "") {
            // a command is running, suggestions are only from command history
            for suggestion in commandHistory {
                if suggestion.hasPrefix(command) {
                    var shortenedSugg = suggestion
                    shortenedSugg.removeFirst(command.count)
                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                        autocompleteSuggestions.append(shortenedSugg)
                    }
                }
            }
            // the last command entered is the suggestion:
            autocompletePosition = autocompleteSuggestions.count - 1
        } else {
            // no commands are running:
            // suggestions are history + available commands
            for suggestion in history.reversed() { // reversed so the latest command appears first
                if suggestion.hasPrefix(command) {
                    var shortenedSugg = suggestion
                    shortenedSugg.removeFirst(command.count)
                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                        autocompleteSuggestions.append(shortenedSugg)
                    }
                }
            }
            // Are we autocompleting a command or something else?
            var commandParts = command.components(separatedBy: " ")
            NSLog("commandParts: \(commandParts)")
            if (commandParts.count == 1) {
                // Autocompleting a command:
                // The aliases go first:
                let aliasArray = aliasesAsArray() as! [String]?
                for suggestion in aliasArray! { // alphabetical order
                    if suggestion.hasPrefix(command) {
                        var shortenedSugg = suggestion
                        shortenedSugg.removeFirst(command.count)
                        if (!autocompleteSuggestions.contains(shortenedSugg)) {
                            autocompleteSuggestions.append(shortenedSugg)
                        }
                    }
                }
                // Followed by the actual commands:
                for suggestion in commandsArray { // alphabetical order
                    if suggestion.hasPrefix(command) {
                        var shortenedSugg = suggestion
                        shortenedSugg.removeFirst(command.count)
                        if (!autocompleteSuggestions.contains(shortenedSugg)) {
                            autocompleteSuggestions.append(shortenedSugg)
                        }
                    }
                }
            } else {
                // We have already entered a command:
                let futureCommand = aliasedCommand(commandParts.first)
                let commandOperatesOn = operatesOn(futureCommand)
                let optionList = getoptString(futureCommand)
                let lastElement = commandParts.last
                var directoryForListing = ""
                if (lastElement?.first == "-") {
                    // options, like "-l"
                    if (optionList != nil) {
                        for option in optionList! {
                            if (option != ":") {
                                if (!lastElement!.contains(option)) && (!command.contains("-" + String(option))) {
                                    autocompleteSuggestions.append(String(option))
                                }
                            }
                        }
                    }
                } else if (lastElement?.first == "$") {
                    // environment variable
                    if (lastElement!.contains("/")) {
                        let directoryComponents = lastElement!.split(separator: "/", maxSplits: 1)
                        var environmentVariable = String(directoryComponents[0])
                        environmentVariable.removeFirst()
                        directoryForListing = String(cString: ios_getenv(environmentVariable)) + "/" + String(directoryComponents[1])
                    } else {
                        let environmentVariables = environmentAsArray()
                        for envVar in environmentVariables! {
                            if let envVarString = envVar as? String {
                                var variableName = "$" + envVarString
                                if variableName.hasPrefix(lastElement!) {
                                    let envVarParts = envVarString.split(separator: "=", maxSplits: 1)
                                    var shortenedSugg = String(envVarParts[0])
                                    shortenedSugg.removeFirst(lastElement!.count - 1)
                                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                                        autocompleteSuggestions.append(shortenedSugg)
                                    }
                                }
                            }
                        }
                    }
                } else if (lastElement?.first == "~") {
                    
                }
                
                
            }
        }
        // TODO: arguments, files, folders, bookmarks, env var
        // Check if all suggestions start with the same substring:
        let prefix = longestCommonPrefix(autocompleteSuggestions)
        for i in 0..<autocompleteSuggestions.count {
            var shortenedSugg = autocompleteSuggestions[i]
            shortenedSugg.removeFirst(prefix.count)
            autocompleteSuggestions[i] = shortenedSugg
        }
        return prefix
    }
    
    // prints a string for autocomplete and move the rest of the command around, even if it is over multiple lines.
    // keep the command as it is until autocomplete has been accepted.
    func printAutocompleteString(suggestion: String) {
        // clear entire buffer, then reprint
        terminalView?.feed(text: escape + "[0J"); // delete display after cursor
        terminalView?.clearToEndOfLine()
        if (terminalView!.tintColor.getBrightness() > terminalView!.backgroundColor!.getBrightness()) {
            // We are in dark mode. Use yellow font for higher contrast
            terminalView?.feed(text: escape + "[33m")  // yellow
        } else {
            // light mode
            terminalView?.feed(text: escape + "[32m")  // yellow
            
        }
        terminalView?.feed(text: suggestion)
        terminalView?.feed(text: escape + "[39m")  // back to normal foreground color
    }
    
    func updateAutocomplete(text: String) {
        // remove all suggestions that don't fit the new string
        let currentSuggestion = autocompleteSuggestions[autocompletePosition]
        autocompleteSuggestions.removeAll(where: { !$0.hasPrefix(text) })
        switch (autocompleteSuggestions.count) {
        case 0:
            stopAutocomplete()
        case 1:
            // erase everything
            terminalView?.feed(text: escape + "[0J"); // delete display after cursor
            terminalView?.clearToEndOfLine()
            var suggestion = autocompleteSuggestions[0]
            suggestion.removeFirst(text.count)
            commandBeforeCursor += suggestion
            terminalView?.feed(text: suggestion)
            terminalView?.saveCursorPosition()
            terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
            terminalView?.restoreCursorPosition()
            autocompleteRunning = false
        default:
            autocompletePosition = 0
            for i in 0..<autocompleteSuggestions.count {
                var shortenedSugg = autocompleteSuggestions[i]
                if (shortenedSugg == currentSuggestion) {
                    autocompletePosition = i
                }
                shortenedSugg.removeFirst(text.count)
                autocompleteSuggestions[i] = shortenedSugg
            }
            terminalView?.saveCursorPosition()
            printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
            terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
            terminalView?.restoreCursorPosition()
            autocompleteRunning = true
        }
    }
    
    func stopAutocomplete() {
        autocompleteRunning = false
        autocompleteSuggestions = []
        autocompletePosition = 0
        terminalView?.feed(text: escape + "[0J"); // delete display after cursor
        terminalView?.clearToEndOfLine()
        terminalView?.saveCursorPosition()
        terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
        terminalView?.restoreCursorPosition()
    }
    
    func findNextWord(string: String) -> String {
        let regex = try? NSRegularExpression(pattern: "(\\b)", options: [])
        let results = regex?.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
        var returnValue = ""
        var offset = 0
        if let matches = results {
            for match in matches {
                let range = match.range
                let subString = string[string.index(string.startIndex, offsetBy:offset)..<string.index(string.startIndex, offsetBy: range.lowerBound)]
                returnValue += subString
                if (subString != " ") && subString != "/" && subString != "" {
                    return returnValue
                }
                offset = range.upperBound
            }
        }
        // If there's no word boundary, return the entire string:
        return string
    }
    
    private func title(_ button: UIBarButtonItem) -> String? {
        if let possibleTitles = button.possibleTitles {
            for attemptedTitle in possibleTitles {
                if (attemptedTitle.count > 0) {
                    return attemptedTitle
                }
            }
        }
        return button.title
    }
    
    // TerminalViewDelegate stubs:
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        if (newRows != height) || (newCols != width) {
            ios_setWindowSize(Int32(newCols), Int32(newRows), self.persistentIdentifier?.toCString())
        }
        if (newRows != height) {
            height = newRows
            setenv("LINES", "\(height)".toCString(), 1)
        }
        if (newCols != width) {
            width = newCols
            setenv("COLUMNS", "\(width)".toCString(), 1)
        }
    }
    
    // None of these are called.
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
        // Nope
    }
    
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        NSLog("hostCurrentDirectoryUpdate: \(directory)")
    }
    
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        // This is where I treat the incoming keypress
        if (currentCommand != "") && (commandBeforeCursor == "") && (commandAfterCursor == "") {
            // Sets the position of the end of the prompt for commands inside commands:
            terminalView!.setPromptEnd()
        }
        if var string = String (bytes: data, encoding: .utf8) {
            if (controlOn) {
                // a) switch control off
                controlOn = false
                if #available(iOS 15.0, *) {
                    if (!useSystemToolbar) {
                        for button in editorToolbar.items! {
                            if title(button) == "control" {
                                button.isSelected = controlOn
                                break
                            }
                        }
                    } else {
                        var foundControl = false
                        if let leftButtonGroups = terminalView?.inputAssistantItem.leadingBarButtonGroups {
                            for leftButtonGroup in leftButtonGroups {
                                for button in leftButtonGroup.barButtonItems {
                                    if title(button) == "control" {
                                        foundControl = true
                                        button.isSelected = controlOn
                                        break
                                    }
                                }
                            }
                        }
                        if (!foundControl) {
                            if let rightButtonGroups = terminalView?.inputAssistantItem.trailingBarButtonGroups {
                                for rightButtonGroup in rightButtonGroups {
                                    for button in rightButtonGroup.barButtonItems {
                                        if title(button) == "control" {
                                            button.isSelected = controlOn
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // b) extract control code:
                string = string.uppercased()
                switch string {
                    // transform control-arrows into alt-arrows:
                case escape + "OA": // up arrow (application mode)
                    fallthrough
                case escape + "[A": // up arrow
                    string = escape + "[1;3A";  // Alt-Up arrow
                case escape + "OB": // down arrow (application mode)
                    fallthrough
                case escape + "[B": // down arrow
                    string = escape + "[1;3B";  // Alt-Down arrow
                case escape + "OC": // right arrow (application mode)
                    fallthrough
                case escape + "[C": // right arrow
                    string = escape + "[1;3C";  // Alt-right arrow
                case escape + "OD": // left arrow (application mode)
                    fallthrough
                case escape + "[D": // left arrow
                    string = escape + "[1;3D";  // Alt-left arrow
                    break;
                default:
                    // create a control-something character
                    if let controlChar = string.first {
                        if let asciiCode = controlChar.asciiValue {
                            if (asciiCode > 64) {
                                string = String(UnicodeScalar(asciiCode - 64))
                            }
                        }
                    }
                }
            }
            if (currentCommand != "") {
                // If there is an interactive command running, we send the data to its stdin thread
                // active pager (interactive command): gets all the input sent through TTY:
                if (ios_activePager() != 0) {
                    if (tty_file_input != nil) {
                        let savedSession = ios_getContext()
                        ios_switchSession(self.persistentIdentifier?.toCString())
                        ios_setContext(UnsafeMutableRawPointer(mutating: self.persistentIdentifier?.toCString()))
                        ios_setStreams(self.stdin_file, self.stdout_file, self.stdout_file)
                        if let data = string.data(using: .utf8) {
                            tty_file_input?.write(data)
                        }
                        // We can get a session context that is not a valid UUID (InExtension, shSession...)
                        // In that case, don't switch back to it:
                        if let stringPointer = UnsafeMutablePointer<CChar>(OpaquePointer(savedSession)) {
                            let savedSessionIdentifier = String(cString: stringPointer)
                            if let uuid = UUID(uuidString: savedSessionIdentifier) {
                                ios_switchSession(savedSession)
                                ios_setContext(savedSession)
                            }
                        }
                    }
                    return
                }
                // from here on, we can assume ios_activePager() == 0
                // If there is a webAssembly command running:
                if (javascriptRunning && (thread_stdin_copy != nil)) {
                    wasmWebView?.evaluateJavaScript("inputString += '\(string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\n"))'; commandIsRunning;") { (result, error) in
                        // if let error = error { print(error) }
                        if let result = result as? Bool {
                            if (!result) {
                                self.endWebAssemblyCommand(error: 0, message: "")
                            }
                        }
                    }
                    stdinString += string
                    NSLog("input sent to WebAssembly: \(string)")
                    return
                }
                if (!javascriptRunning && executeWebAssemblyCommandsRunning) {
                    // There seems to be cases where the webassembly command did not terminate properly.
                    // We catch it here:
                    wasmWebView?.evaluateJavaScript("commandIsRunning;") { (result, error) in
                        // if let error = error { print(error) }
                        if let result = result as? Bool {
                            if (!result) {
                                self.endWebAssemblyCommand(error: 0, message: "")
                            }
                        }
                    }
                }
                // Special case: help() and license() in ipython are not interactive.
                var helpRunningInIpython = false
                if (currentCommand.hasPrefix("ipython") || currentCommand.hasPrefix("isympy")) {
                    if let lastLine = terminalView?.getLastPrompt() {
                        if (lastLine.hasSuffix("help> ") ||
                            lastLine.hasSuffix("Hit Return for more, or q (and Return) to quit: ") ||
                            lastLine.hasSuffix("Do you really want to exit ([y]/n)? ")) {
                            helpRunningInIpython = true
                        }
                    }
                }
                // interactive command: send the data directly
                if interactiveCommandRunning && !helpRunningInIpython {
                    ios_switchSession(self.persistentIdentifier?.toCString())
                    ios_setContext(UnsafeMutableRawPointer(mutating: self.persistentIdentifier?.toCString()));
                    ios_setStreams(self.stdin_file, self.stdout_file, self.stdout_file)
                    // Interactive commands: just send the input to them. Allows Vim to map control-D to down half a page.
                    guard let data = string.data(using: .utf8) else { return }
                    guard stdin_file_input != nil else { return }
                    // TODO: don't send data if pipe already closed (^D followed by another key)
                    // (store a variable that says the pipe has been closed)
                    // NSLog("Writing (interactive) \(command) to stdin")
                    stdin_file_input?.write(data)
                    return
                }
            }
            // TODO: don't send data if pipe already closed (^D followed by another key)
            // (store a variable that says the pipe has been closed)
            // NSLog("Writing (not interactive) \(command) to stdin")
            // stdin_file_input?.write(data)
            // insert mode does not work, so we keep our own version of the command line.
            NSLog("received string: \"\(string)\"")
            switch (string) {
            case endOfTransmission:
                // Stop standard input for the command:
                if (currentCommand != "") {
                    guard stdin_file_input != nil else {
                        // no command running, maybe it ended without us knowing:
                        printPrompt()
                        return
                    }
                    do {
                        try stdin_file_input?.close()
                    }
                    catch {
                        // NSLog("Could not close stdin input.")
                    }
                    stdin_file_input = nil
                }
            case interrupt:
                if autocompleteRunning {
                    stopAutocomplete()
                } else {
                    if (currentCommand != "") && (!javascriptRunning) {
                        // Calling ios_kill while executing webAssembly or JavaScript is a bad idea.
                        // Do we have a way to interrupt JS execution in WkWebView?
                        ios_kill() // TODO: add printPrompt() here if no command running
                    }
                    if (currentCommand == "") {
                        // disable auto-complete menu if running
                        // don't execute command, move to next line, print prompt
                        commandBeforeCursor = ""
                        commandAfterCursor = ""
                        terminalView?.feed(text: "\r\n")
                        printPrompt()
                    }
                }
            case deleteBackward:
                // send arrow-left, then delete-char, but only if there is something to delete:
                // This needs to be: currentPosition > cursorPosition
                // == canMoveLeft?
                if autocompleteRunning {
                    stopAutocomplete()
                } else {
                    if (commandBeforeCursor.count > 0) {
                        terminalView?.moveUpIfNeeded()
                        if let lastChar = commandBeforeCursor.last {
                            NSLog("deleting: \(lastChar)")
                            commandBeforeCursor.removeLast()
                            let characterWidth = NSAttributedString(string: String(lastChar), attributes: [.font: terminalView?.font]).size().width
                            if (characterWidth > 1.4 * basicCharWidth) {
                                // "large" characters: delete two columns
                                terminalView?.feed(text: escape + "[D")
                                terminalView?.feed(text: escape + "[P")
                            }
                            terminalView?.feed(text: escape + "[D")
                            terminalView?.feed(text: escape + "[P")
                        }
                    }
                }
            case tabulation: // autocomplete
                NSLog("received tab")
                if (autocompleteRunning) {
                    commandBeforeCursor += autocompleteSuggestions[autocompletePosition]
                    terminalView?.feed(text: autocompleteSuggestions[autocompletePosition])
                    autocompleteSuggestions = []
                    autocompletePosition = 0
                    autocompleteRunning = false
                } else {
                    let commonPrefix = fillAutocompleteSuggestions(command: commandBeforeCursor)
                    commandBeforeCursor += commonPrefix
                    terminalView?.feed(text: commonPrefix)
                    if (autocompleteSuggestions.count > 1) {
                        terminalView?.saveCursorPosition()
                        printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                        terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                        terminalView?.restoreCursorPosition()
                        autocompleteRunning = true
                    }
                }
            case escape + "OA": // up arrow (application mode)
                fallthrough
            case escape + "[A": // up arrow
                if (autocompleteRunning) {
                    autocompletePosition -= 1
                    if (autocompletePosition < 0) {
                        autocompletePosition = autocompleteSuggestions.count - 1
                    }
                    terminalView?.saveCursorPosition()
                    printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                    terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                    terminalView?.restoreCursorPosition()
                } else {
                    if (currentCommand == "") {
                        NSLog("Up arrow, position= \(historyPosition) count= \(history.count)")
                        if (historyPosition > 0) {
                            historyPosition -= 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView?.feed(text: history[historyPosition])
                            commandBeforeCursor = history[historyPosition]
                            commandAfterCursor = ""
                        }
                    } else {
                        NSLog("Up arrow, position= \(commandHistoryPosition) count= \(commandHistory.count)")
                        if (commandHistoryPosition > 0) {
                            commandHistoryPosition -= 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView!.setPromptEnd() // Required? Why?
                            terminalView?.feed(text: commandHistory[commandHistoryPosition])
                            commandBeforeCursor = commandHistory[commandHistoryPosition]
                            commandAfterCursor = ""
                        }
                    }
                }
            case escape + "OB": // down arrow (application mode)
                fallthrough
            case escape + "[B": // down arrow
                if (autocompleteRunning) {
                    autocompletePosition += 1
                    if (autocompletePosition > autocompleteSuggestions.count - 1) {
                        autocompletePosition = 0
                    }
                    terminalView?.saveCursorPosition()
                    printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                    terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                    terminalView?.restoreCursorPosition()
                } else {
                    if (currentCommand == "") {
                        NSLog("Down arrow, position= \(historyPosition) count= \(history.count)")
                        if (historyPosition < history.count - 1) {
                            historyPosition += 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            if (historyPosition < history.count) {
                                terminalView?.feed(text: history[historyPosition])
                                commandBeforeCursor = history[historyPosition]
                                commandAfterCursor = ""
                            }
                        } else {
                            historyPosition = history.count
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView?.getTerminal().updateFullScreen()
                            terminalView?.updateDisplay()
                            commandBeforeCursor = ""
                            commandAfterCursor = ""
                        }
                    } else {
                        NSLog("Down arrow, position= \(commandHistoryPosition) count= \(commandHistory.count)")
                        if (commandHistoryPosition < commandHistory.count - 1) {
                            commandHistoryPosition += 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            if (commandHistoryPosition < commandHistory.count) {
                                NSLog("sending \(commandHistory[commandHistoryPosition])")
                                terminalView?.feed(text: commandHistory[commandHistoryPosition])
                                commandBeforeCursor = commandHistory[commandHistoryPosition]
                                commandAfterCursor = ""
                            }
                        } else {
                            commandHistoryPosition = commandHistory.count
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView?.getTerminal().updateFullScreen()
                            terminalView?.updateDisplay()
                            commandBeforeCursor = ""
                            commandAfterCursor = ""
                        }
                    }
                }
            case escape + "OD": // left arrow (application mode)
                fallthrough
            case escape + "[D": // left arrow
                if autocompleteRunning {
                    stopAutocomplete()
                } else {
                    if (commandBeforeCursor.count > 0) {
                        if let lastChar = commandBeforeCursor.last {
                            commandBeforeCursor.removeLast()
                            commandAfterCursor = String(lastChar) + commandAfterCursor
                            terminalView?.moveUpIfNeeded()
                            let characterWidth = NSAttributedString(string: String(lastChar), attributes: [.font: terminalView?.font]).size().width
                            if (characterWidth > 1.4 * basicCharWidth) {
                                terminalView?.feed(text: escape + "[D")
                            }
                            terminalView?.feed(text: escape + "[D")
                        }
                    }
                }
            case escape + "OC": // right arrow (application mode)
                fallthrough
            case escape + "[C": // right arrow
                if (autocompleteRunning) {
                    // autocomplete up to the next word boundary
                    let string = findNextWord(string: autocompleteSuggestions[autocompletePosition])
                    commandBeforeCursor += string
                    terminalView?.feed(text: string) // prints the string
                    updateAutocomplete(text: string)
                } else {
                    if (commandAfterCursor.count > 0) {
                        if let firstChar = commandAfterCursor.first {
                            commandAfterCursor.removeFirst()
                            commandBeforeCursor = commandBeforeCursor + String(firstChar)
                            terminalView?.moveDownIfNeeded()
                            let characterWidth = NSAttributedString(string: String(firstChar), attributes: [.font: terminalView?.font]).size().width
                            if (characterWidth > 1.4 * basicCharWidth) {
                                terminalView?.feed(text: escape + "[C")
                            }
                            terminalView?.feed(text: escape + "[C")
                        }
                    } else {
                        NSLog("Cannot move right")
                    }
                }
            case escape:
                if (autocompleteRunning) {
                    stopAutocomplete()
                }
            case carriageReturn:
                if (autocompleteRunning) {
                    // validate current suggestion
                    // overwrite suggestion in default color
                    terminalView?.feed(text: autocompleteSuggestions[autocompletePosition])
                    commandBeforeCursor += autocompleteSuggestions[autocompletePosition]
                    autocompleteSuggestions = []
                    autocompletePosition = 0
                    autocompleteRunning = false
                }
                if (currentCommand == "") {
                    let commandLine = (commandBeforeCursor + commandAfterCursor).trimmingCharacters(in: .whitespaces)
                    commandBeforeCursor = ""
                    commandAfterCursor = ""
                    executeCommand(command: commandLine)
                    terminalView?.feed(text: "\n\r")
                } else {
                    let commandLine = (commandBeforeCursor + commandAfterCursor).trimmingCharacters(in: .whitespaces)
                    commandBeforeCursor = ""
                    commandAfterCursor = ""
                    terminalView?.feed(text: "\n\r")
                    guard let data = (commandLine + "\n").data(using: .utf8) else { return }
                    guard stdin_file_input != nil else { return }
                    // store command in local command history, reset if it's different:
                    if (currentCommand != lastCommand) {
                        lastCommand = currentCommand
                        commandHistory = []
                        commandHistoryPosition = 0
                    }
                    if (commandHistory.last != commandLine) && (commandLine != "") {
                        commandHistory.append(commandLine)
                        while (commandHistory.count > 100) {
                            commandHistory.removeFirst()
                        }
                    }
                    commandHistoryPosition = commandHistory.count
                    // TODO: don't send data if pipe already closed (^D followed by another key)
                    // (store a variable that says the pipe has been closed)
                    stdin_file_input?.write(data)
                }
            default:
                // Default, send to term
                commandBeforeCursor += string
                terminalView?.feed(text: string) // prints the string
                if autocompleteRunning {
                    updateAutocomplete(text: string)
                } else {
                    terminalView?.saveCursorPosition()
                    terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                    terminalView?.restoreCursorPosition()
                }
            }
        } else {
            NSLog("Failure of conversion: \(data)")
        }
    }
    
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {
        //
    }
    
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String : String]) {
        if let fixedup = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            if let url = NSURLComponents(string: fixedup) {
                if let nested = url.url {
                    UIApplication.shared.open (nested)
                }
            }
        }
    }
    
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        if let str = String (bytes: content, encoding: .utf8) {
            UIPasteboard.general.string = str
        }
    }
    
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        //
    }
}

// Copyright 2025 RnD Center "ELVEES", JSC

package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"
)

var (
	TargetAddr       = "__TARGET_ADDR__"
	TargetPort       = "__TARGET_PORT__"
	TargetUser       = "__TARGET_USER__"
	TargetPass       = "__TARGET_PASS__"
	DLoopRestartFile = "__DLOOP_RESTART_FILE__"
	SCPFlags         = []string{
		"__SCP_FLAGS__",
	}
)

func main() {
	log.Println("Running remote application...")
	for {
		time.Sleep(1 * time.Second)
		pollTerminationState()
	}
}

func pollTerminationState() {
	if len(os.Args) < 4 {
		return
	}
	sourceFile := DLoopRestartFile
	targetFile := DLoopRestartFile
	os.Remove(targetFile)
	remoteCmd := fmt.Sprintf("sshpass -p %s scp -C %s %s@%s:%s %s",
		TargetPass, strings.Join(SCPFlags, " "), TargetUser, TargetAddr, sourceFile, targetFile)
	_, err := runCommand("bash", `-c`, remoteCmd)
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		exitCode := exitError.ExitCode()
		if exitCode == 1 {
			terminateExecStub()
		}
	} else if err == nil {
		if _, err := os.Stat(targetFile); errors.Is(err, os.ErrNotExist) {
			terminateExecStub()
		}
	}
}

func terminateExecStub() {
	log.Println("Remote application terminated...")
	os.Exit(0)
}

func runCommand(name string, args ...string) (string, error) {
	var errorBuffer bytes.Buffer
	command := exec.Command(name, args...)
	command.Stderr = &errorBuffer
	output, err := command.Output()
	if err != nil {
		lines := stringToLines(trimEndings(errorBuffer.String()))
		const maxLines = 3
		if offset := len(lines) - maxLines; offset > 0 {
			lines = lines[offset:]
		}
		const trimLength = 256
		const trimPostfix = "..."
		for index, line := range lines {
			if len(line) > trimLength {
				lines[index] = line[:trimLength-len(trimPostfix)] + trimPostfix
			}
		}
		errorText := strings.Join(lines, "; ")
		if errorText != "" {
			errorText += ": "
		}
		commandLine := strings.Join(command.Args, " ")
		return "", fmt.Errorf("failed to execute '%v': %s%w", commandLine, errorText, err)
	}
	return trimEndings(string(output)), nil
}

func stringToLines(source string) []string {
	var lines []string
	scanner := bufio.NewScanner(strings.NewReader(source))
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	return lines
}

func trimEndings(value string) string {
	return strings.Trim(value, "\x00\n")
}

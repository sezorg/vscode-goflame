// Copyright 2024 RnD Center "ELVEES", JSC

package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"time"
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
	host := os.Args[1]
	user := os.Args[2]
	pass := os.Args[3]
	sourceFile := "/tmp/dlv-loop-restart"
	targetFile := "/var/tmp/goflame/go-execute-marker"
	os.Remove(targetFile)
	err := exec.Command("bash", `-c`,
		fmt.Sprintf("sshpass -p %s scp %s@%s:%s %s",
			pass, user, host, sourceFile, targetFile)).Run()
	if exitErr, ok := err.(*exec.ExitError); ok {
		exitCode := exitErr.ExitCode()
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

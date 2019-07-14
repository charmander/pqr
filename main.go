package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
)

type packageInfo struct {
	Path string
	Scripts map[string]string
}

func getPackageInfo(searchPath string) (*packageInfo, error) {
	for {
		f, err := os.Open(filepath.Join(searchPath, "package.json"))

		if err != nil {
			next := filepath.Dir(searchPath)

			if !os.IsNotExist(err) || next == searchPath {
				return nil, err
			}

			searchPath = next
			continue
		}

		defer f.Close()

		decoder := json.NewDecoder(f)
		var decoded map[string]*json.RawMessage

		result := new(packageInfo)
		result.Path = searchPath

		if err := decoder.Decode(&decoded); err != nil {
			return nil, err
		}

		scripts_json := decoded["scripts"]

		if scripts_json == nil {
			return result, nil
		}

		if err := json.Unmarshal(*scripts_json, &result.Scripts); err != nil {
			return nil, err
		}

		return result, nil
	}
}

func showUsage() {
	fmt.Println("Usage: pqr <command> [<args>...]")
}

func main() {
	if len(os.Args) < 2 {
		showUsage()
		os.Exit(1)
	}

	scriptName := os.Args[1]
	scriptArgs := os.Args[2:]

	wd, err := os.Getwd()

	if err != nil {
		panic(err)
	}

	info, err := getPackageInfo(wd)

	if err != nil {
		if !os.IsNotExist(err) {
			panic(err)
		}

		fmt.Fprintf(os.Stderr, "No package.json found at any level above %s\n", wd)
		os.Exit(1)
	}

	commandText, ok := info.Scripts[scriptName]

	if !ok {
		fmt.Fprintf(os.Stderr, "No script named %s in %s/package.json\n", scriptName, info.Path)
		os.Exit(1)
	}

	commandArgs := append([]string{"-c", commandText + " \"$@\"", "sh"}, scriptArgs...)

	var commandEnv []string

	// : is impossible to escape in $PATH
	if !strings.ContainsRune(info.Path, ':') {
		extendPath := filepath.Join(info.Path, "node_modules/.bin")

		// There’s no need to check for an empty $PATH here, as sh wouldn’t be found in that case
		commandEnv = append(os.Environ(), "PATH=" + extendPath + ":" + os.Getenv("PATH"))
	}

	command := exec.Command("sh", commandArgs...)
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	command.Dir = info.Path
	command.Env = commandEnv

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt)
	signal.Notify(signals, syscall.SIGTERM)
	signal.Notify(signals, os.Kill)

	go func() {
		<- signals
		signal.Stop(signals)
	}()

	if err := command.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Script failed: %s\n", err)
		os.Exit(1)
	}
}

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type packageInfo struct {
	path string
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
		result := new(packageInfo)

		if err := decoder.Decode(result); err != nil {
			return nil, err
		}

		result.path = searchPath
		return result, nil
	}
}

func showUsage() {
	fmt.Println("Usage: pqr <command> [<args>...]")
}

func main() {
	if (len(os.Args) < 2) {
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
		fmt.Fprintf(os.Stderr, "No script named %s in %s/package.json\n", scriptName, info.path)
		os.Exit(1)
	}

	commandArgs := append([]string{"-c", commandText + " \"$@\"", "sh"}, scriptArgs...)

	var commandEnv []string

	// : is impossible to escape in $PATH
	if !strings.ContainsRune(info.path, ':') {
		extendPath := filepath.Join(info.path, "node_modules/.bin")

		// There’s no need to check for an empty $PATH here, as sh wouldn’t be found in that case
		commandEnv = append(os.Environ(), "PATH=" + extendPath + ":" + os.Getenv("PATH"))
	}

	command := exec.Command("sh", commandArgs...)
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	command.Dir = info.path
	command.Env = commandEnv
	command.Start()

	if err := command.Wait(); err != nil {
		fmt.Fprintf(os.Stderr, "Script failed: %s\n", err)
		os.Exit(1)
	}
}

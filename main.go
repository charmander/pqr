package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

type packageInfo struct {
	Path string
	Scripts map[string]string
}

func getPackageInfo(searchPath string) (packageInfo, error) {
	for {
		f, err := os.Open(filepath.Join(searchPath, "package.json"))

		if err != nil {
			next := filepath.Dir(searchPath)

			if !os.IsNotExist(err) || next == searchPath {
				return packageInfo{}, err
			}

			searchPath = next
			continue
		}

		defer f.Close()

		decoder := json.NewDecoder(f)
		var decoded map[string]*json.RawMessage

		result := packageInfo{Path: searchPath}

		if err := decoder.Decode(&decoded); err != nil {
			return packageInfo{}, err
		}

		scripts_json := decoded["scripts"]

		if scripts_json == nil {
			return result, nil
		}

		if err := json.Unmarshal(*scripts_json, &result.Scripts); err != nil {
			return packageInfo{}, err
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

	commandArgs := append([]string{"sh", "-c", "--", commandText + " \"$@\"", "sh"}, scriptArgs...)

	// : is impossible to escape in $PATH
	if !strings.ContainsRune(info.Path, ':') {
		extendPath := filepath.Join(info.Path, "node_modules/.bin")

		envPath := os.Getenv("PATH")

		var extendedPath string

		if envPath == "" {
			extendedPath = extendPath
		} else {
			extendedPath = extendPath + ":" + envPath
		}

		os.Setenv("PATH", extendedPath)
	}

	err = os.Chdir(info.Path)

	if err != nil {
		panic(err)
	}

	err = syscall.Exec("/bin/sh", commandArgs, os.Environ())
	fmt.Fprintf(os.Stderr, "exec failed: %s\n", err)
	os.Exit(1)
}

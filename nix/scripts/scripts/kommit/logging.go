package main

import (
	"fmt"
	"os"
)

var verboseLogging = os.Getenv("KOMMIT_DEBUG") != ""

func debugf(format string, a ...any) {
	if verboseLogging {
		fmt.Fprintf(os.Stderr, "[debug] "+format+"\n", a...)
	}
}

func statusf(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "[ok] "+format+"\n", a...)
}

func warnf(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "[warn] "+format+"\n", a...)
}

func errorf(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "[error] "+format+"\n", a...)
}

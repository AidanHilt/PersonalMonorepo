package main

import (
	"regexp"
	"strings"
)

// matchGlob supports '*' (any run of non-slash chars), '?' (single non-slash
// char), and '**' (any run of chars, including slashes). Patterns are
// matched against forward-slash-separated relative paths.
func matchGlob(pattern, path string) bool {
	re, err := globToRegexp(pattern)
	if err != nil {
		warnf("invalid glob pattern %q: %v", pattern, err)
		return false
	}
	return re.MatchString(path)
}

func globToRegexp(pattern string) (*regexp.Regexp, error) {
	var b strings.Builder
	b.WriteString("^")
	runes := []rune(pattern)
	for i := 0; i < len(runes); i++ {
		c := runes[i]
		switch c {
		case '*':
			if i+1 < len(runes) && runes[i+1] == '*' {
				b.WriteString(".*")
				i++
				if i+1 < len(runes) && runes[i+1] == '/' {
					i++
				}
			} else {
				b.WriteString("[^/]*")
			}
		case '?':
			b.WriteString("[^/]")
		case '.', '+', '(', ')', '|', '^', '$', '{', '}', '[', ']', '\\':
			b.WriteString("\\")
			b.WriteRune(c)
		default:
			b.WriteRune(c)
		}
	}
	b.WriteString("$")
	return regexp.Compile(b.String())
}

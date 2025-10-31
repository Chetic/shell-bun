package pattern

import (
	"path/filepath"
	"strings"
)

// MatchSet returns all candidates that satisfy the provided pattern expression.
// Patterns can be comma-separated, support glob wildcards, and fall back to
// case-insensitive substring matching when no wildcards are present.
func MatchSet(pattern string, candidates []string) []string {
	patterns := splitPatterns(pattern)
	if len(patterns) == 0 {
		return nil
	}

	var result []string
	seen := make(map[string]struct{})

	for _, pat := range patterns {
		for _, candidate := range candidates {
			if _, ok := seen[candidate]; ok {
				continue
			}
			if matches(pat, candidate) {
				seen[candidate] = struct{}{}
				result = append(result, candidate)
			}
		}
	}

	return result
}

// MatchActions returns all action names that satisfy the provided pattern.
// The literal "all" returns every available action.
func MatchActions(pattern string, actions []string) []string {
	trimmed := strings.TrimSpace(pattern)
	if trimmed == "all" {
		return append([]string(nil), actions...)
	}
	return MatchSet(pattern, actions)
}

func splitPatterns(pattern string) []string {
	var patterns []string
	for _, part := range strings.Split(pattern, ",") {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			patterns = append(patterns, trimmed)
		}
	}
	return patterns
}

func matches(pattern, candidate string) bool {
	if pattern == "" {
		return false
	}

	if pattern == candidate {
		return true
	}

	if strings.Contains(pattern, "*") {
		ok, err := filepath.Match(pattern, candidate)
		if err == nil && ok {
			return true
		}
	}

	lp := strings.ToLower(pattern)
	lc := strings.ToLower(candidate)
	return strings.Contains(lc, lp)
}

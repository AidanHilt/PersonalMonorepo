// Package config holds the operator-wide defaults for miura, parsed from
// command-line flags with environment-variable fallbacks. These are the
// "op default" values referenced throughout docs/function.md: values a
// Function may override per-instance, but which must be configured once
// at the operator level when a Function's spec leaves them unset.
package config

import (
	"flag"
	"os"
	"strconv"
	"time"
)

// Config carries the operator-wide defaults supplied at startup.
type Config struct {
	// DefaultRegistry is the container registry used for ko builds when
	// spec.build.registry is unset.
	DefaultRegistry string
	// DefaultPushSecret is the Secret name (in the Function's namespace)
	// holding registry push credentials when spec.build.pushSecretRef is
	// unset. Expected to be of type kubernetes.io/dockerconfigjson (key
	// .dockerconfigjson).
	DefaultPushSecret string
	// DefaultDomain is appended to a Function's name to form the default
	// hostname when spec.triggers.http.hostname is unset.
	DefaultDomain string
	// DefaultGatewayName is the Istio Gateway name used when
	// spec.triggers.http.gateway.name is unset.
	DefaultGatewayName string
	// DefaultGatewayNamespace is the Istio Gateway namespace used when
	// spec.triggers.http.gateway.namespace is unset.
	DefaultGatewayNamespace string
	// DefaultPollInterval is used when spec.source.pollInterval is unset.
	DefaultPollInterval time.Duration
	// DefaultBaseImage is the ko base image used when spec.build.baseImage
	// is unset.
	DefaultBaseImage string
	// KoImage is the image used to run `ko build` inside the build Job.
	KoImage string
	// GitImage is the image used to clone source inside the build Job's
	// init container.
	GitImage string
	// DefaultMaxScale is used when spec.runtime.maxScale is unset.
	DefaultMaxScale int32
	// BuildHistoryLimit caps the number of entries kept in
	// status.builds.
	BuildHistoryLimit int
}

// defaults holds the hardcoded fallback values used when neither a flag
// nor its corresponding environment variable is set.
var defaults = Config{
	DefaultRegistry:         "",
	DefaultPushSecret:       "",
	DefaultDomain:           "",
	DefaultGatewayName:      "",
	DefaultGatewayNamespace: "",
	DefaultPollInterval:     5 * time.Minute,
	DefaultBaseImage:        "cgr.dev/chainguard/static:latest",
	KoImage:                 "ghcr.io/ko-build/ko:latest",
	GitImage:                "alpine/git:latest",
	DefaultMaxScale:         10,
	BuildHistoryLimit:       5,
}

// envString returns the value of the named environment variable, or def
// if it is unset or empty.
func envString(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

// envDuration returns the named environment variable parsed as a
// time.Duration, or def if it is unset, empty, or fails to parse.
func envDuration(name string, def time.Duration) time.Duration {
	v := os.Getenv(name)
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return def
	}
	return d
}

// envInt32 returns the named environment variable parsed as an int32, or
// def if it is unset, empty, or fails to parse.
func envInt32(name string, def int32) int32 {
	v := os.Getenv(name)
	if v == "" {
		return def
	}
	n, err := strconv.ParseInt(v, 10, 32)
	if err != nil {
		return def
	}
	return int32(n)
}

// envInt returns the named environment variable parsed as an int, or def
// if it is unset, empty, or fails to parse.
func envInt(name string, def int) int {
	v := os.Getenv(name)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

// int32Value implements flag.Value so an int32 field can be registered
// with fs.Var alongside the string/duration/int flags above.
type int32Value int32

func (v *int32Value) String() string {
	if v == nil {
		return "0"
	}
	return strconv.FormatInt(int64(*v), 10)
}

func (v *int32Value) Set(s string) error {
	n, err := strconv.ParseInt(s, 10, 32)
	if err != nil {
		return err
	}
	*v = int32Value(n)
	return nil
}

// ParseFlags registers miura's operator-wide flags on fs (each with an
// environment-variable fallback, applied before flag.Parse so an explicit
// flag always wins) and returns a Config populated once fs.Parse(args) is
// called by the caller.
//
// Flag/env pairs:
//
//	--default-registry          MIURA_DEFAULT_REGISTRY
//	--default-push-secret       MIURA_DEFAULT_PUSH_SECRET
//	--default-domain            MIURA_DEFAULT_DOMAIN
//	--default-gateway-name      MIURA_DEFAULT_GATEWAY_NAME
//	--default-gateway-namespace MIURA_DEFAULT_GATEWAY_NAMESPACE
//	--default-poll-interval     MIURA_DEFAULT_POLL_INTERVAL
//	--default-base-image        MIURA_DEFAULT_BASE_IMAGE
//	--ko-image                  MIURA_KO_IMAGE
//	--git-image                 MIURA_GIT_IMAGE
//	--default-max-scale         MIURA_DEFAULT_MAX_SCALE
//	--build-history-limit       MIURA_BUILD_HISTORY_LIMIT
func ParseFlags(fs *flag.FlagSet) *Config {
	cfg := &Config{}

	fs.StringVar(&cfg.DefaultRegistry, "default-registry",
		envString("MIURA_DEFAULT_REGISTRY", defaults.DefaultRegistry),
		"Default container registry for ko builds when spec.build.registry is unset.")
	fs.StringVar(&cfg.DefaultPushSecret, "default-push-secret",
		envString("MIURA_DEFAULT_PUSH_SECRET", defaults.DefaultPushSecret),
		"Default registry push Secret name when spec.build.pushSecretRef is unset.")
	fs.StringVar(&cfg.DefaultDomain, "default-domain",
		envString("MIURA_DEFAULT_DOMAIN", defaults.DefaultDomain),
		"Default domain appended to a Function's name when spec.triggers.http.hostname is unset.")
	fs.StringVar(&cfg.DefaultGatewayName, "default-gateway-name",
		envString("MIURA_DEFAULT_GATEWAY_NAME", defaults.DefaultGatewayName),
		"Default Istio Gateway name when spec.triggers.http.gateway.name is unset.")
	fs.StringVar(&cfg.DefaultGatewayNamespace, "default-gateway-namespace",
		envString("MIURA_DEFAULT_GATEWAY_NAMESPACE", defaults.DefaultGatewayNamespace),
		"Default Istio Gateway namespace when spec.triggers.http.gateway.namespace is unset.")
	fs.DurationVar(&cfg.DefaultPollInterval, "default-poll-interval",
		envDuration("MIURA_DEFAULT_POLL_INTERVAL", defaults.DefaultPollInterval),
		"Default source poll interval when spec.source.pollInterval is unset.")
	fs.StringVar(&cfg.DefaultBaseImage, "default-base-image",
		envString("MIURA_DEFAULT_BASE_IMAGE", defaults.DefaultBaseImage),
		"Default ko base image when spec.build.baseImage is unset.")
	fs.StringVar(&cfg.KoImage, "ko-image",
		envString("MIURA_KO_IMAGE", defaults.KoImage),
		"Image used to run `ko build` inside the build Job.")
	fs.StringVar(&cfg.GitImage, "git-image",
		envString("MIURA_GIT_IMAGE", defaults.GitImage),
		"Image used to clone source inside the build Job's init container.")
	cfg.DefaultMaxScale = envInt32("MIURA_DEFAULT_MAX_SCALE", defaults.DefaultMaxScale)
	fs.Var((*int32Value)(&cfg.DefaultMaxScale), "default-max-scale",
		"Default spec.runtime.maxScale when unset.")
	fs.IntVar(&cfg.BuildHistoryLimit, "build-history-limit",
		envInt("MIURA_BUILD_HISTORY_LIMIT", defaults.BuildHistoryLimit),
		"Number of entries kept in status.builds.")

	return cfg
}

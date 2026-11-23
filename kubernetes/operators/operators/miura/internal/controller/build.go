package controller

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"path"
	"sort"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	miurav1alpha1 "miura/api/v1alpha1"
)

const (
	buildJobTTLSeconds   int32 = 600
	buildJobBackoffLimit int32 = 1

	cloneContainerName = "clone"
	buildContainerName = "build"

	workspaceVolumeName  = "workspace"
	workspaceMountPath   = "/workspace"
	checkoutDir          = workspaceMountPath + "/checkout"
	pushSecretVolumeName = "push-secret"
	dockerConfigMountDir = "/docker-config"

	buildResultBuilding  = "Building"
	buildResultSucceeded = "Succeeded"
	buildResultFailed    = "Failed"

	// requeueBuildPoll is how often an in-progress build Job's status is
	// re-checked.
	requeueBuildPoll = 5 * time.Second
)

// buildSpecHash derives a deterministic, name-safe hash from the
// resolved commit and the parts of the Function's spec that affect the
// built image. Embedding it (truncated) in the build Job's name means
// the Job's identity alone captures "this exact build": a change to any
// of these fields produces a different name, and so a new Job/build,
// without needing a dedicated status field to remember the last-built
// spec. This implements docs/function.md's "any change to source, ref,
// path, or build.* triggers an immediate rebuild" rule.
func buildSpecHash(commit string, fn *miurav1alpha1.Function) string {
	type hashInput struct {
		Commit          string            `json:"commit"`
		SourcePath      string            `json:"sourcePath"`
		MainPackage     string            `json:"mainPackage"`
		BaseImage       string            `json:"baseImage"`
		Env             map[string]string `json:"env,omitempty"`
		Registry        string            `json:"registry"`
		ImageRepository string            `json:"imageRepository"`
		PushSecretRef   string            `json:"pushSecretRef"`
	}
	in := hashInput{
		Commit:          commit,
		SourcePath:      fn.Spec.Source.Path,
		MainPackage:     fn.Spec.Build.MainPackage,
		BaseImage:       fn.Spec.Build.BaseImage,
		Env:             fn.Spec.Build.Env,
		Registry:        fn.Spec.Build.Registry,
		ImageRepository: fn.Spec.Build.ImageRepository,
	}
	if fn.Spec.Build.PushSecretRef != nil {
		in.PushSecretRef = fn.Spec.Build.PushSecretRef.Name
	}
	// encoding/json sorts map keys, so this marshal is stable across
	// calls for equal input.
	b, _ := json.Marshal(in)
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])[:10]
}

// buildJobName returns the deterministic Job name for fn's current
// build: "<name>-build-<hash10>". fn.Name is capped at 40 characters by
// a CEL validation rule in api/v1alpha1, so this always fits the
// 63-character DNS label limit ("-build-" is 7 chars, the hash 10).
func buildJobName(fn *miurav1alpha1.Function, hash string) string {
	return fmt.Sprintf("%s-build-%s", fn.Name, hash)
}

// reconcileBuild ensures a build Job exists for fn's currently resolved
// commit and build spec, and updates the Built condition and
// status.image/status.builds from that Job's observed state. It returns
// a requeue duration while a build is still in progress.
func (r *FunctionReconciler) reconcileBuild(ctx context.Context, fn *miurav1alpha1.Function) (time.Duration, error) {
	logger := log.FromContext(ctx)

	commit := fn.Status.Source.ResolvedCommit
	hash := buildSpecHash(commit, fn)
	jobName := buildJobName(fn, hash)

	var job batchv1.Job
	err := r.Get(ctx, client.ObjectKey{Namespace: fn.Namespace, Name: jobName}, &job)
	switch {
	case apierrors.IsNotFound(err):
		newJob := r.desiredBuildJob(fn, jobName, commit)
		if err := controllerutil.SetControllerReference(fn, newJob, r.Scheme); err != nil {
			return 0, fmt.Errorf("set owner reference on build job %s: %w", jobName, err)
		}
		if err := r.Create(ctx, newJob); err != nil && !apierrors.IsAlreadyExists(err) {
			return 0, fmt.Errorf("create build job %s: %w", jobName, err)
		}
		logger.Info("created build job", "job", jobName, "commit", commit)

		meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
			Type:               miurav1alpha1.ConditionBuilt,
			Status:             metav1.ConditionFalse,
			Reason:             miurav1alpha1.ReasonBuilding,
			Message:            fmt.Sprintf("build job %s started for commit %s", jobName, commit),
			ObservedGeneration: fn.Generation,
		})
		r.upsertBuildStatus(fn, miurav1alpha1.FunctionBuildStatus{
			Commit:    commit,
			StartTime: &metav1.Time{Time: time.Now()},
			Result:    buildResultBuilding,
			JobName:   jobName,
		})
		return requeueBuildPoll, nil
	case err != nil:
		return 0, fmt.Errorf("get build job %s: %w", jobName, err)
	}

	return r.observeBuildJob(ctx, fn, &job)
}

// observeBuildJob inspects an existing build Job's status and updates
// the Built condition, status.image (only on success — a failed build
// leaves the previous image serving unchanged), and status.builds.
func (r *FunctionReconciler) observeBuildJob(ctx context.Context, fn *miurav1alpha1.Function, job *batchv1.Job) (time.Duration, error) {
	logger := log.FromContext(ctx)

	switch {
	case job.Status.Succeeded > 0:
		image, readErr := r.readBuildImage(ctx, job)
		if readErr != nil {
			logger.Error(readErr, "build job succeeded but its image could not be read", "job", job.Name)
			meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
				Type:               miurav1alpha1.ConditionBuilt,
				Status:             metav1.ConditionFalse,
				Reason:             miurav1alpha1.ReasonBuildFailed,
				Message:            fmt.Sprintf("build job %s succeeded but its image could not be read: %v", job.Name, readErr),
				ObservedGeneration: fn.Generation,
			})
			r.upsertBuildStatus(fn, miurav1alpha1.FunctionBuildStatus{
				Commit:         fn.Status.Source.ResolvedCommit,
				StartTime:      job.Status.StartTime,
				CompletionTime: job.Status.CompletionTime,
				Result:         buildResultFailed,
				JobName:        job.Name,
			})
			return 0, nil
		}

		fn.Status.Image = image
		meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
			Type:               miurav1alpha1.ConditionBuilt,
			Status:             metav1.ConditionTrue,
			Reason:             miurav1alpha1.ReasonBuildSucceeded,
			Message:            fmt.Sprintf("built %s", image),
			ObservedGeneration: fn.Generation,
		})
		r.upsertBuildStatus(fn, miurav1alpha1.FunctionBuildStatus{
			Commit:         fn.Status.Source.ResolvedCommit,
			Image:          image,
			StartTime:      job.Status.StartTime,
			CompletionTime: job.Status.CompletionTime,
			Result:         buildResultSucceeded,
			JobName:        job.Name,
		})
		return 0, nil

	case jobFailed(job):
		logger.Info("build job failed", "job", job.Name)
		meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
			Type:               miurav1alpha1.ConditionBuilt,
			Status:             metav1.ConditionFalse,
			Reason:             miurav1alpha1.ReasonBuildFailed,
			Message:            fmt.Sprintf("build job %s failed", job.Name),
			ObservedGeneration: fn.Generation,
		})
		r.upsertBuildStatus(fn, miurav1alpha1.FunctionBuildStatus{
			Commit:         fn.Status.Source.ResolvedCommit,
			StartTime:      job.Status.StartTime,
			CompletionTime: job.Status.CompletionTime,
			Result:         buildResultFailed,
			JobName:        job.Name,
		})
		return 0, nil

	default:
		meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
			Type:               miurav1alpha1.ConditionBuilt,
			Status:             metav1.ConditionFalse,
			Reason:             miurav1alpha1.ReasonBuilding,
			Message:            fmt.Sprintf("build job %s is running", job.Name),
			ObservedGeneration: fn.Generation,
		})
		return requeueBuildPoll, nil
	}
}

// jobFailed reports whether job has reached a terminal failure (the
// JobFailed condition, set once its backoffLimit is exhausted) rather
// than merely being mid-retry.
func jobFailed(job *batchv1.Job) bool {
	for _, c := range job.Status.Conditions {
		if c.Type == batchv1.JobFailed && c.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}

// readBuildImage finds the build Job's terminated "build" container and
// returns the image reference it wrote to /dev/termination-log.
func (r *FunctionReconciler) readBuildImage(ctx context.Context, job *batchv1.Job) (string, error) {
	var pods corev1.PodList
	if err := r.List(ctx, &pods, client.InNamespace(job.Namespace), client.MatchingLabels{"job-name": job.Name}); err != nil {
		return "", fmt.Errorf("list build job pods: %w", err)
	}

	for _, pod := range pods.Items {
		for _, cs := range pod.Status.ContainerStatuses {
			if cs.Name != buildContainerName {
				continue
			}
			if cs.State.Terminated == nil || cs.State.Terminated.ExitCode != 0 {
				continue
			}
			if cs.State.Terminated.Message == "" {
				return "", fmt.Errorf("pod %s/%s container %s terminated successfully but wrote no termination message",
					pod.Namespace, pod.Name, buildContainerName)
			}
			return cs.State.Terminated.Message, nil
		}
	}
	return "", fmt.Errorf("no successfully terminated %s container found for job %s/%s", buildContainerName, job.Namespace, job.Name)
}

// upsertBuildStatus records entry in fn.Status.Builds, replacing any
// existing entry for the same JobName (so re-observing the same Job
// doesn't grow history) or otherwise prepending it as the newest entry,
// then caps the list at the operator's configured build history limit.
func (r *FunctionReconciler) upsertBuildStatus(fn *miurav1alpha1.Function, entry miurav1alpha1.FunctionBuildStatus) {
	for i, existing := range fn.Status.Builds {
		if existing.JobName == entry.JobName {
			fn.Status.Builds[i] = entry
			return
		}
	}
	fn.Status.Builds = append([]miurav1alpha1.FunctionBuildStatus{entry}, fn.Status.Builds...)
	limit := r.Config.BuildHistoryLimit
	if limit > 0 && len(fn.Status.Builds) > limit {
		fn.Status.Builds = fn.Status.Builds[:limit]
	}
}

// desiredBuildJob builds the batch/v1 Job that clones fn's resolved
// commit and builds it with ko. See IMPLEMENTERS.md for the full design
// rationale.
func (r *FunctionReconciler) desiredBuildJob(fn *miurav1alpha1.Function, jobName, commit string) *batchv1.Job {
	registry := fn.Spec.Build.Registry
	if registry == "" {
		registry = r.Config.DefaultRegistry
	}
	imageRepo := fn.Spec.Build.ImageRepository
	if imageRepo == "" {
		imageRepo = fmt.Sprintf("%s/%s", fn.Namespace, fn.Name)
	}
	baseImage := fn.Spec.Build.BaseImage
	if baseImage == "" {
		baseImage = r.Config.DefaultBaseImage
	}
	pushSecret := r.Config.DefaultPushSecret
	if fn.Spec.Build.PushSecretRef != nil && fn.Spec.Build.PushSecretRef.Name != "" {
		pushSecret = fn.Spec.Build.PushSecretRef.Name
	}
	sourcePath := fn.Spec.Source.Path
	if sourcePath == "" {
		sourcePath = "."
	}
	mainPackage := fn.Spec.Build.MainPackage
	if mainPackage == "" {
		mainPackage = "."
	}
	workDir := path.Join(checkoutDir, sourcePath)

	buildEnv := []corev1.EnvVar{
		{Name: "KO_DOCKER_REPO", Value: registry + "/" + imageRepo},
		{Name: "KO_DEFAULTBASEIMAGE", Value: baseImage},
		{Name: "DOCKER_CONFIG", Value: dockerConfigMountDir},
	}
	for _, k := range sortedKeys(fn.Spec.Build.Env) {
		buildEnv = append(buildEnv, corev1.EnvVar{Name: k, Value: fn.Spec.Build.Env[k]})
	}

	cloneScript := fmt.Sprintf(
		"set -eu; git clone --quiet %q %q; cd %q; git checkout --quiet %q",
		fn.Spec.Source.URL, checkoutDir, checkoutDir, commit,
	)
	// `ko build --bare` uses KO_DOCKER_REPO verbatim as the destination
	// repository (no importpath-derived suffix) and pushes by default;
	// its stdout on success is the resulting image@digest reference,
	// which is what status.image/status.builds[].image are expected to
	// hold.
	buildScript := fmt.Sprintf(
		`set -eu; image=$(ko build --bare %q); printf '%%s' "$image" >/dev/termination-log`,
		mainPackage,
	)

	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: fn.Namespace,
			Labels: map[string]string{
				"miura.io/function": fn.Name,
			},
		},
		Spec: batchv1.JobSpec{
			TTLSecondsAfterFinished: int32Ptr(buildJobTTLSeconds),
			BackoffLimit:            int32Ptr(buildJobBackoffLimit),
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{
						"miura.io/function": fn.Name,
					},
				},
				Spec: corev1.PodSpec{
					RestartPolicy: corev1.RestartPolicyNever,
					Volumes: []corev1.Volume{
						{
							Name:         workspaceVolumeName,
							VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}},
						},
						{
							Name: pushSecretVolumeName,
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName: pushSecret,
									Items: []corev1.KeyToPath{
										{Key: ".dockerconfigjson", Path: "config.json"},
									},
								},
							},
						},
					},
					InitContainers: []corev1.Container{
						{
							Name:    cloneContainerName,
							Image:   r.Config.GitImage,
							Command: []string{"sh", "-c", cloneScript},
							VolumeMounts: []corev1.VolumeMount{
								{Name: workspaceVolumeName, MountPath: workspaceMountPath},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:                     buildContainerName,
							Image:                    r.Config.KoImage,
							Command:                  []string{"sh", "-c", buildScript},
							WorkingDir:               workDir,
							Env:                      buildEnv,
							TerminationMessagePolicy: corev1.TerminationMessageReadFile,
							VolumeMounts: []corev1.VolumeMount{
								{Name: workspaceVolumeName, MountPath: workspaceMountPath},
								{Name: pushSecretVolumeName, MountPath: dockerConfigMountDir, ReadOnly: true},
							},
						},
					},
				},
			},
		},
	}
}

// int32Ptr returns a pointer to a copy of v — batch/v1 JobSpec fields
// like TTLSecondsAfterFinished/BackoffLimit take *int32, and a local
// helper avoids depending on k8s.io/utils/ptr purely for this.
func int32Ptr(v int32) *int32 {
	return &v
}

// sortedKeys returns m's keys in sorted order, so generated env vars
// (and the build-spec hash above) are deterministic across reconciles.
func sortedKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

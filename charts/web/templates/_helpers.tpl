{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "web.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "web.labels" -}}
helm.sh/chart: {{ include "web.chart" . }}
{{ include "web.selectorLabels" . }}
{{- if .Values.global.image.tag }}
app.kubernetes.io/version: {{ .Values.global.image.tag | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use. Empty means the namespace default.
*/}}
{{- define "web.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "web.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- .Values.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{- define "web.image" -}}
{{- $image := .Values.global.image -}}
{{- $repository := required "global.image.repository is required" $image.repository -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $repository $image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (required "global.image.tag or global.image.digest is required" $image.tag) -}}
{{- end -}}
{{- end }}

{{- define "web.componentName" -}}
{{- printf "%s-%s" (include "web.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "web.componentLabels" -}}
{{ include "web.labels" .root }}
app.kubernetes.io/component: {{ .component | quote }}
{{- end }}

{{- define "web.componentSelectorLabels" -}}
{{ include "web.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component | quote }}
{{- end }}

{{- define "web.validateName" -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" (toString .name)) }}
{{- fail (printf "%s name %q must be a DNS label" .kind (toString .name)) }}
{{- end }}
{{- end }}

{{/*
Pod template metadata. The checksum covers env and envFrom so a change to either
always rolls the pods.
*/}}
{{- define "web.podMetadata" -}}
{{- $root := .root -}}
{{- $workload := .workload -}}
{{- $annotations := mergeOverwrite (deepCopy (default (dict) $root.Values.global.podAnnotations)) (default (dict) $workload.podAnnotations) -}}
{{- $labels := mergeOverwrite (deepCopy (default (dict) $root.Values.global.podLabels)) (default (dict) $workload.podLabels) -}}
{{- $env := dict
  "env" (concat (default (list) $root.Values.global.env) (default (list) $workload.env))
  "envFrom" (concat (default (list) $root.Values.global.envFrom) (default (list) $workload.envFrom))
-}}
{{- $_ := set $annotations "checksum/env" (toYaml $env | sha256sum) -}}
labels:
{{- include "web.componentSelectorLabels" (dict "root" $root "component" .component) | nindent 2 }}
{{- with $labels }}
{{- toYaml . | nindent 2 }}
{{- end }}
annotations:
{{- toYaml $annotations | nindent 2 }}
{{- end }}

{{/*
Topology spread: a workload list (even empty) wins, then global, then, when
.spread is set, one spreading the component's pods across nodes.
*/}}
{{- define "web.topologySpreadConstraints" -}}
{{- $constraints := .workload.topologySpreadConstraints -}}
{{- if kindIs "invalid" $constraints -}}
{{- $constraints = .root.Values.global.topologySpreadConstraints -}}
{{- if and (not $constraints) .spread -}}
{{- $constraints = list (dict
  "maxSkew" 1
  "topologyKey" "kubernetes.io/hostname"
  "whenUnsatisfiable" "ScheduleAnyway"
  "nodeTaintsPolicy" "Honor"
  "labelSelector" (dict "matchLabels" (include "web.componentSelectorLabels" (dict "root" .root "component" .component) | fromYaml))
) -}}
{{- end -}}
{{- end -}}
{{- with $constraints }}
topologySpreadConstraints:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "web.podSpecCommon" -}}
{{- $root := .root -}}
{{- $workload := .workload -}}
{{- with $root.Values.global.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with include "web.serviceAccountName" $root }}
serviceAccountName: {{ . }}
{{- end }}
automountServiceAccountToken: {{ $root.Values.serviceAccount.automountServiceAccountToken }}
{{- with $root.Values.global.podSecurityContext }}
securityContext:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with $workload.terminationGracePeriodSeconds }}
terminationGracePeriodSeconds: {{ . }}
{{- end }}
{{- with default $root.Values.global.priorityClassName $workload.priorityClassName }}
priorityClassName: {{ . | quote }}
{{- end }}
{{- with default $root.Values.global.dnsConfig $workload.dnsConfig }}
dnsConfig:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- $nodeSelector := mergeOverwrite (deepCopy (default (dict) $root.Values.global.nodeSelector)) (default (dict) $workload.nodeSelector) -}}
{{- with $nodeSelector }}
nodeSelector:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- $tolerations := default $root.Values.global.tolerations $workload.tolerations -}}
{{- with $tolerations }}
tolerations:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- $affinity := mergeOverwrite (deepCopy (default (dict) $root.Values.global.affinity)) (default (dict) $workload.affinity) -}}
{{- with $affinity }}
affinity:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- include "web.topologySpreadConstraints" . }}
{{- with $workload.initContainers }}
initContainers:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- $volumes := concat (include "web.volumes" . | fromYamlArray) (default (list) $root.Values.global.extraVolumes) (default (list) $workload.extraVolumes) -}}
{{- with $volumes }}
volumes:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Main container fields shared by every workload. Templates add ports, probes and lifecycle.
*/}}
{{- define "web.containerCommon" -}}
{{- $root := .root -}}
{{- $workload := .workload -}}
image: {{ include "web.image" $root }}
imagePullPolicy: {{ $root.Values.global.image.pullPolicy }}
{{- with $root.Values.global.securityContext }}
securityContext:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with $workload.command }}
command:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with $workload.args }}
args:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with $workload.resources }}
resources:
{{- toYaml . | nindent 2 }}
{{- end }}
env:
{{- include "web.env" . | nindent 2 }}
{{- include "web.envFrom" . }}
{{- $mounts := concat (include "web.volumeMounts" $root | fromYamlArray) (default (list) $root.Values.global.extraVolumeMounts) (default (list) $workload.extraVolumeMounts) -}}
{{- with $mounts }}
volumeMounts:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "web.defaultEnv" -}}
- name: APP_VERSION
  value: {{ .root.Values.global.appVersion | default .root.Values.global.image.tag | quote }}
- name: CONTAINER_ROLE
  value: {{ .role | quote }}
{{- end }}

{{- define "web.validateEnv" -}}
{{- $reserved := list "APP_VERSION" "CONTAINER_ROLE" -}}
{{- range concat (default (list) .root.Values.global.env) (default (list) .workload.env) -}}
{{- if has .name $reserved -}}
{{- fail (printf "env var %s is chart-owned and cannot be overridden through values" .name) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Chart-owned env, then .extra and NODE_OPTIONS (each skipped when env already
defines the name), then global env, then workload env.
*/}}
{{- define "web.env" -}}
{{- include "web.validateEnv" . -}}
{{- $userEnv := concat (default (list) .root.Values.global.env) (default (list) .workload.env) -}}
{{- $defined := list -}}
{{- range $userEnv }}
{{- $defined = append $defined .name -}}
{{- end -}}
{{- $extra := default (list) .extra -}}
{{- if and (dig "node" "maxOldSpaceFromLimit" false .workload) (dig "resources" "limits" "memory" "" .workload) -}}
{{- $extra = append $extra (dict "name" "NODE_OPTIONS" "value" (printf "--max-old-space-size=%d" (include "web.maxOldSpaceMiB" .workload.resources.limits.memory | int))) -}}
{{- end -}}
{{- include "web.defaultEnv" (dict "root" .root "role" .role) }}
{{- range $extra }}
{{- if not (has .name $defined) }}
- {{ toYaml . | nindent 2 | trim }}
{{- end }}
{{- end }}
{{- with $userEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
75% of a Kubernetes memory quantity, in MiB.
*/}}
{{- define "web.maxOldSpaceMiB" -}}
{{- $quantity := toString . -}}
{{- if not (regexMatch "^[0-9]+(Ki|Mi|Gi|Ti|k|M|G|T)?$" $quantity) -}}
{{- fail (printf "node.maxOldSpaceFromLimit cannot parse memory limit %q; use an integer with Ki, Mi, Gi, Ti, k, M, G or T" $quantity) -}}
{{- end -}}
{{- $multipliers := dict "" 1 "Ki" 1024 "Mi" 1048576 "Gi" 1073741824 "Ti" 1099511627776 "k" 1000 "M" 1000000 "G" 1000000000 "T" 1000000000000 -}}
{{- $amount := regexReplaceAll "[^0-9]+$" $quantity "" | float64 -}}
{{- $unit := regexReplaceAll "^[0-9]+" $quantity "" -}}
{{- divf (mulf $amount (index $multipliers $unit) 0.75) 1048576 | floor | int -}}
{{- end }}

{{- define "web.envFrom" -}}
{{- $envFrom := concat (default (list) .root.Values.global.envFrom) (default (list) .workload.envFrom) -}}
{{- with $envFrom }}
envFrom:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "web.readOnlyRootFilesystem" -}}
{{- if dig "readOnlyRootFilesystem" false (default (dict) .Values.global.securityContext) }}true{{ end -}}
{{- end }}

{{- define "web.writableVolumeName" -}}
{{- printf "writable-%s" (regexReplaceAll "[^a-z0-9]+" (trimAll "/" . | lower) "-") | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "web.volumeMounts" -}}
{{- range .Values.global.secretVolumes }}
{{- $volume := . -}}
{{- range .items }}
- name: {{ $volume.name }}
  mountPath: {{ $volume.mountPath | default "/" | trimSuffix "/" }}/{{ .key }}
  subPath: {{ .key }}
  readOnly: true
{{- end }}
{{- end }}
{{- if include "web.readOnlyRootFilesystem" . }}
{{- range .Values.global.writablePaths }}
- name: {{ include "web.writableVolumeName" . }}
  mountPath: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{- define "web.volumes" -}}
{{- range .root.Values.global.secretVolumes }}
- name: {{ .name }}
  secret:
    secretName: {{ .name }}
    items:
{{- toYaml .items | nindent 6 }}
{{- end }}
{{- if include "web.readOnlyRootFilesystem" .root }}
{{- range .root.Values.global.writablePaths }}
- name: {{ include "web.writableVolumeName" . }}
  emptyDir: {}
{{- end }}
{{- end }}
{{- end }}

{{- define "web.hpa" -}}
{{- $autoscaling := .autoscaling -}}
{{- if not (or $autoscaling.targetCPUUtilizationPercentage $autoscaling.targetMemoryUtilizationPercentage) }}
{{- fail (printf "%s.autoscaling needs targetCPUUtilizationPercentage or targetMemoryUtilizationPercentage" .path) }}
{{- end }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name }}
  labels:
    {{- include "web.componentLabels" (dict "root" .root "component" .component) | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .name }}
  minReplicas: {{ $autoscaling.minReplicas }}
  maxReplicas: {{ $autoscaling.maxReplicas }}
  metrics:
  {{- with $autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ . }}
  {{- end }}
  {{- with $autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ . }}
  {{- end }}
  {{- with $autoscaling.behavior }}
  behavior:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}

{{/*
PodDisruptionBudget, only when more than one pod is guaranteed.
*/}}
{{- define "web.pdb" -}}
{{- $autoscaling := default (dict) .workload.autoscaling -}}
{{- $replicas := ternary (default 1 $autoscaling.minReplicas) (default 1 .workload.replicas) (and (kindIs "map" $autoscaling) (eq true $autoscaling.enabled)) -}}
{{- if gt (int $replicas) 1 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  labels:
    {{- include "web.componentLabels" (dict "root" .root "component" .component) | nindent 4 }}
spec:
  minAvailable: {{ default 1 .workload.minAvailable }}
  selector:
    matchLabels:
      {{- include "web.componentSelectorLabels" (dict "root" .root "component" .component) | nindent 6 }}
{{- end }}
{{- end }}

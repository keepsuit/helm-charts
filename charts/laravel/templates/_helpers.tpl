{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "laravel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "laravel.fullname" -}}
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
{{- define "laravel.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "laravel.labels" -}}
helm.sh/chart: {{ include "laravel.chart" . }}
{{ include "laravel.selectorLabels" . }}
{{- if .Values.global.image.tag }}
app.kubernetes.io/version: {{ .Values.global.image.tag | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "laravel.selectorLabels" -}}
app.kubernetes.io/name: {{ include "laravel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Create the name of the service account to use
*/}}
{{- define "laravel.serviceAccountName" -}}
{{- template "laravel.fullname" . }}
{{- end }}

{{- define "laravel.image" -}}
{{- printf "%s:%s" (required "global.image.repository is required" .Values.global.image.repository) (required "global.image.tag is required" .Values.global.image.tag) -}}
{{- end }}

{{- define "laravel.servicePort" -}}
{{- default .port .service.port -}}
{{- end }}

{{- define "laravel.componentName" -}}
{{- printf "%s-%s" (include "laravel.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "laravel.componentLabels" -}}
{{ include "laravel.labels" .root }}
app.kubernetes.io/component: {{ .component | quote }}
{{- end }}

{{- define "laravel.componentSelectorLabels" -}}
{{ include "laravel.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component | quote }}
{{- end }}

{{- define "laravel.appSelectorLabels" -}}
app.kubernetes.io/name: {{ include "laravel.name" . }}-app
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "laravel.appPodLabels" -}}
{{ include "laravel.appSelectorLabels" . }}
app.kubernetes.io/component: "app"
{{- end }}

{{- define "laravel.mergeMap" -}}
{{- $global := default (dict) .global -}}
{{- $local := default (dict) .local -}}
{{- toYaml (mergeOverwrite (deepCopy $global) $local) -}}
{{- end }}

{{- define "laravel.concatList" -}}
{{- concat (default (list) .global) (default (list) .local) | toYaml -}}
{{- end }}

{{- define "laravel.podMetadata" -}}
{{- $annotations := mergeOverwrite (deepCopy (default (dict) .root.Values.global.podAnnotations)) (default (dict) .workload.podAnnotations) -}}
{{- $labels := mergeOverwrite (deepCopy (default (dict) .root.Values.global.podLabels)) (default (dict) .workload.podLabels) -}}
{{- if $labels }}
labels:
{{ include "laravel.componentSelectorLabels" (dict "root" .root "component" .component) | nindent 2 }}
{{- toYaml $labels | nindent 2 }}
{{- else }}
labels:
{{ include "laravel.componentSelectorLabels" (dict "root" .root "component" .component) | nindent 2 }}
{{- end }}
{{- if $annotations }}
annotations:
{{- toYaml $annotations | nindent 2 }}
{{- end }}
{{- end }}

{{- define "laravel.podSpecCommon" -}}
{{- $root := .root -}}
{{- $workload := .workload -}}
{{- with $root.Values.global.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end }}
serviceAccountName: {{ include "laravel.serviceAccountName" $root }}
{{- with $root.Values.global.podSecurityContext }}
securityContext:
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
{{- $topologySpreadConstraints := default $root.Values.global.topologySpreadConstraints $workload.topologySpreadConstraints -}}
{{- with $topologySpreadConstraints }}
topologySpreadConstraints:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "laravel.defaultEnv" -}}
- name: APP_VERSION
  value: {{ .root.Values.global.image.tag | quote }}
- name: CONTAINER_ROLE
  value: {{ .role | quote }}
{{- end }}

{{- define "laravel.validateEnv" -}}
{{- $reserved := list "APP_VERSION" "CONTAINER_ROLE" "REVERB_SCALING_ENABLED" "AUTORUN_LARAVEL_OPTIMIZE" -}}
{{- range concat (default (list) .root.Values.global.env) (default (list) .workload.env) -}}
{{- if has .name $reserved -}}
{{- fail (printf "env var %s is chart-owned and cannot be overridden through values" .name) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "laravel.env" -}}
{{- include "laravel.validateEnv" . -}}
{{- include "laravel.defaultEnv" (dict "root" .root "role" .role) }}
{{- with .extra }}
{{ toYaml . }}
{{- end }}
{{- with .root.Values.global.env }}
{{ toYaml . }}
{{- end }}
{{- with .workload.env }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "laravel.envFrom" -}}
{{- $envFrom := concat (default (list) .root.Values.global.envFrom) (default (list) .workload.envFrom) -}}
{{- with $envFrom }}
envFrom:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "laravel.secretVolumeMounts" -}}
{{- range .Values.global.secretVolumes }}
{{- $volume := . -}}
{{- range .items }}
- name: {{ $volume.name }}
  mountPath: {{ $volume.mountPath | default "/" | trimSuffix "/" }}/{{ .key }}
  subPath: {{ .key }}
  readOnly: true
{{- end }}
{{- end }}
{{- end }}

{{- define "laravel.secretVolumes" -}}
{{- range .Values.global.secretVolumes }}
- name: {{ .name }}
  secret:
    secretName: {{ .name }}
    items:
{{- toYaml .items | nindent 6 }}
{{- end }}
{{- end }}

{{- define "laravel.workerCommand" -}}
{{- $root := .root -}}
{{- $worker := .worker -}}
{{- $queue := default "default" $worker.queue -}}
{{- if $root.Values.global.workerCommand.useWrapper -}}
command:
  - {{ $root.Values.global.workerCommand.binary | quote }}
args:
  - {{ $worker.type | quote }}
{{- if or (eq $worker.type "queue") (eq $worker.type "combined") }}
  - {{ printf "--queue=%s" $queue | quote }}
{{- end }}
{{- else if eq $worker.type "combined" -}}
{{- fail "workers with type=combined require global.workerCommand.useWrapper=true" -}}
{{- else if eq $worker.type "queue" -}}
args: ["php", "artisan", "queue:work", "--queue={{ $queue }}"]
{{- else if eq $worker.type "horizon" -}}
args: ["php", "artisan", "horizon"]
{{- else if eq $worker.type "scheduler" -}}
args: ["php", "artisan", "schedule:work"]
{{- end -}}
{{- end }}

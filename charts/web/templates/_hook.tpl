{{/*
Deploy hook Job. .key is preDeploy or postDeploy; .component names the Job.
*/}}
{{- define "web.hookJob" -}}
{{- $root := .root -}}
{{- $hook := index $root.Values.hooks .key -}}
{{- $command := join " && " (default (list) $hook.commands) -}}
{{- $command = required (printf "hooks.%s.commands must contain at least one command when hooks.%s.enabled is true" .key .key) $command -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "web.fullname" $root }}-{{ .component }}
  labels:
    {{- include "web.componentLabels" (dict "root" $root "component" .component) | nindent 4 }}
  annotations:
    "helm.sh/hook": {{ .phases | quote }}
    {{- with .weight }}
    "helm.sh/hook-weight": {{ . | quote }}
    {{- end }}
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  {{- range $key := list "backoffLimit" "activeDeadlineSeconds" "ttlSecondsAfterFinished" }}
  {{- if not (kindIs "invalid" (index $hook $key)) }}
  {{ $key }}: {{ index $hook $key }}
  {{- end }}
  {{- end }}
  template:
    metadata:
      {{- include "web.podMetadata" (dict "root" $root "workload" $hook "component" .component) | trim | nindent 6 }}
    spec:
      restartPolicy: Never
      {{- include "web.podSpecCommon" (dict "root" $root "workload" $hook "component" .component) | trim | nindent 6 }}
      containers:
        - name: {{ .component }}-job
          {{- include "web.containerCommon" (dict "root" $root "workload" (merge (dict "command" (list "sh" "-c" $command)) $hook) "role" .component) | trim | nindent 10 }}
{{- end }}

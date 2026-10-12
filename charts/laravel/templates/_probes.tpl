{{- define "laravel.appProbes" -}}
{{- $app := .Values.app -}}
{{- $health := $app.healthCheck -}}
{{- $handler := dict "httpGet" (dict "path" $health.path "port" (default $app.port $health.port)) -}}
{{- if $app.octane.enabled -}}
{{- $handler = dict "exec" (dict "command" (list "php" "artisan" "octane:status")) -}}
{{- end -}}
{{- $defaults := dict
  "startupProbe" (dict "periodSeconds" 2 "timeoutSeconds" 5 "failureThreshold" 60)
  "readinessProbe" (dict "initialDelaySeconds" 0 "periodSeconds" 5 "timeoutSeconds" $health.timeoutSeconds "failureThreshold" $health.failureThreshold)
  "livenessProbe" (dict "initialDelaySeconds" $health.initialDelaySeconds "periodSeconds" $health.periodSeconds "timeoutSeconds" $health.timeoutSeconds "failureThreshold" $health.failureThreshold)
-}}
{{- range $name := list "startupProbe" "readinessProbe" "livenessProbe" -}}
{{- $override := index $app $name -}}
{{- if not (and (kindIs "bool" $override) (eq $override false)) -}}
{{- $probe := mergeOverwrite (deepCopy $handler) (deepCopy (index $defaults $name)) -}}
{{- if kindIs "map" $override -}}
{{- $handlers := list "httpGet" "exec" "tcpSocket" "grpc" -}}
{{- $handlerCount := 0 -}}
{{- range $key := $handlers -}}
{{- if hasKey $override $key -}}
{{- $handlerCount = add1 $handlerCount -}}
{{- end -}}
{{- end -}}
{{- if gt $handlerCount 1 -}}
{{- fail (printf "app.%s must specify at most one probe handler" $name) -}}
{{- end -}}
{{- if eq $handlerCount 1 -}}
{{- range $key := $handlers -}}
{{- $_ := unset $probe $key -}}
{{- end -}}
{{- end -}}
{{- $probe = mergeOverwrite $probe (deepCopy $override) -}}
{{- end }}
{{ $name }}:
{{ toYaml $probe | indent 2 }}
{{- end -}}
{{- end -}}
{{- end -}}

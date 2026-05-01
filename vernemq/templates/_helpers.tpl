{{/* vernemq/templates/_helpers.tpl */}}

{{/*
Return the name of the chart, allowing override via values.nameOverride.
*/}}
{{- define "vernemq.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified release name, allowing override via values.fullnameOverride.
*/}}
{{- define "vernemq.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "vernemq.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart label value (name-version), with '+' replaced.
*/}}
{{- define "vernemq.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{/*
Common labels applied to all resources.
*/}}
{{- define "vernemq.labels" -}}
app.kubernetes.io/name: {{ include "vernemq.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "vernemq.chart" . }}
{{- end -}}

{{/*
Selector labels used by Services/StatefulSet selectors.
We keep name constant to "vernemq" to simplify client selectors.
*/}}
{{- define "vernemq.selectorLabels" -}}
app.kubernetes.io/name: vernemq
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name helper.
*/}}
{{- define "vernemq.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "vernemq.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

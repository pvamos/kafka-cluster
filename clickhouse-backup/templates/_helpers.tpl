{{- define "clickhouse-backup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clickhouse-backup.fullname" -}}
{{- $name := default (include "clickhouse-backup.name" .) .Values.fullnameOverride -}}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

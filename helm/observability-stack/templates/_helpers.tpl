{{/*
Expand the name of the chart.
*/}}
{{- define "observability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "observability.fullname" -}}
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

{{- define "observability.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability.namespace" -}}
{{- default .Release.Namespace .Values.namespace.name }}
{{- end }}

{{- define "observability.labels" -}}
helm.sh/chart: {{ include "observability.chart" . }}
{{ include "observability.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: observability-stack
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "observability.selectorLabels" -}}
app.kubernetes.io/name: {{ include "observability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "observability.grafana.fullname" -}}
{{- printf "%s-grafana" (include "observability.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability.prometheus.fullname" -}}
{{- printf "%s-prometheus" (include "observability.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability.nodeExporter.fullname" -}}
{{- printf "%s-node-exporter" (include "observability.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability.grafana.labels" -}}
{{ include "observability.labels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{- define "observability.prometheus.labels" -}}
{{ include "observability.labels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{- define "observability.nodeExporter.labels" -}}
{{ include "observability.labels" . }}
app.kubernetes.io/component: node-exporter
{{- end }}

{{- define "observability.grafana.selectorLabels" -}}
{{ include "observability.selectorLabels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{- define "observability.prometheus.selectorLabels" -}}
{{ include "observability.selectorLabels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{- define "observability.nodeExporter.selectorLabels" -}}
{{ include "observability.selectorLabels" . }}
app.kubernetes.io/component: node-exporter
{{- end }}

{{- define "observability.image" -}}
{{- $registry := .image.registry | default .global.imageRegistry -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry .image.repository .image.tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository .image.tag -}}
{{- end -}}
{{- end }}

{{- define "observability.grafana.secretName" -}}
{{- if .Values.grafana.existingSecret }}
{{- .Values.grafana.existingSecret }}
{{- else }}
{{- printf "%s-admin" (include "observability.grafana.fullname" .) }}
{{- end }}
{{- end }}

{{- define "observability.imagePullSecrets" -}}
{{- $secrets := .Values.global.imagePullSecrets | default list -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

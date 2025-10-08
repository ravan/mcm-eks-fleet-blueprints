{{/*
Expand the name of the chart.
*/}}
{{- define "ack-pod-identity-association.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated to 40 chars to allow for suffixes like -bootstrap-identity (23 chars)
*/}}
{{- define "ack-pod-identity-association.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 40 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 40 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 40 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ack-pod-identity-association.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ack-pod-identity-association.labels" -}}
helm.sh/chart: {{ include "ack-pod-identity-association.chart" . }}
{{ include "ack-pod-identity-association.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ack-pod-identity-association.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.controllerName }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Bootstrap service account name
*/}}
{{- define "ack-pod-identity-association.bootstrap.serviceAccountName" -}}
{{- if .Values.hook.bootstrap.serviceAccountName }}
{{- .Values.hook.bootstrap.serviceAccountName }}
{{- else }}
{{- include "ack-pod-identity-association.fullname" . }}-bootstrap-sa
{{- end }}
{{- end }}

{{/*
Cleanup service account name
*/}}
{{- define "ack-pod-identity-association.cleanup.serviceAccountName" -}}
{{- if .Values.hook.cleanup.serviceAccountName }}
{{- .Values.hook.cleanup.serviceAccountName }}
{{- else }}
{{- include "ack-pod-identity-association.fullname" . }}-cleanup-sa
{{- end }}
{{- end }}

{{/*
Construct Role ARN from components or use provided roleArn
*/}}
{{- define "ack-pod-identity-association.roleArn" -}}
{{- if .Values.podIdentity.roleArn }}
{{- .Values.podIdentity.roleArn }}
{{- else if and .Values.podIdentity.awsAccountId .Values.podIdentity.roleName }}
{{- printf "arn:aws:iam::%s:role/%s" .Values.podIdentity.awsAccountId .Values.podIdentity.roleName }}
{{- else }}
{{- fail "Either podIdentity.roleArn or both podIdentity.awsAccountId and podIdentity.roleName must be set" }}
{{- end }}
{{- end }}

{{/*
Get namespace for pod identity association
*/}}
{{- define "ack-pod-identity-association.namespace" -}}
{{- .Values.podIdentity.namespace | default .Release.Namespace }}
{{- end }}

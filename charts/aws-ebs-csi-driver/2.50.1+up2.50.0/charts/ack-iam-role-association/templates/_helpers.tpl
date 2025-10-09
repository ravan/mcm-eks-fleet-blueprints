{{/*
Expand the name of the chart.
*/}}
{{- define "ack-iam-role-association.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated to 40 chars to allow for suffixes like -iam-role-hook (15 chars)
*/}}
{{- define "ack-iam-role-association.fullname" -}}
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
{{- define "ack-iam-role-association.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ack-iam-role-association.labels" -}}
helm.sh/chart: {{ include "ack-iam-role-association.chart" . }}
{{ include "ack-iam-role-association.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ack-iam-role-association.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.controllerName }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name for IAM role hook
*/}}
{{- define "ack-iam-role-association.serviceAccountName" -}}
{{- if .Values.hook.serviceAccountName }}
{{- .Values.hook.serviceAccountName }}
{{- else }}
{{- include "ack-iam-role-association.fullname" . }}-iam-role-sa
{{- end }}
{{- end }}

{{/*
Service account name for cleanup hook
*/}}
{{- define "ack-iam-role-association.cleanup.serviceAccountName" -}}
{{- if .Values.hook.cleanup.serviceAccountName }}
{{- .Values.hook.cleanup.serviceAccountName }}
{{- else }}
{{- include "ack-iam-role-association.fullname" . }}-cleanup-sa
{{- end }}
{{- end }}

{{/*
IAM Role CRD resource name
*/}}
{{- define "ack-iam-role-association.roleCrdName" -}}
{{- printf "%s-iam-role" (include "ack-iam-role-association.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Construct assume role policy document as JSON
*/}}
{{- define "ack-iam-role-association.assumeRolePolicyDocument" -}}
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "{{ .Values.iamRole.trustPolicy.servicePrincipal }}"
      },
      "Action": {{ .Values.iamRole.trustPolicy.actions | toJson }}
    }
  ]
}
{{- end }}

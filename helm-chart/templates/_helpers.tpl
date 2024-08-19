{{/*
Expand the name of the chart
*/}}
{{- define "generic-application.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name
*/}}
{{- define "generic-application.fullname" -}}
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
Create chart name and version as used by the chart label
*/}}
{{- define "generic-application.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "generic-application.labels" -}}
helm.sh/chart: {{ include "generic-application.chart" . }}
{{ include "generic-application.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{/*
Selector labels
*/}}
{{- define "generic-application.selectorLabels" -}}
app.kubernetes.io/name: {{ include "generic-application.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if eq .Values.pod.workloadIdentity true }}
azure.workload.identity/use: "true"
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "generic-application.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "generic-application.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service
*/}}
{{- define "generic-application.serviceName" -}}
{{- $service_index := ternary .serviceIndex 0 (hasKey . "serviceIndex") }}
{{- if (index .Values.services $service_index).name }}
  {{- printf "%s-%s" (include "generic-application.fullname" $) (index .Values.services $service_index).name }}
{{- else }}
  {{- if le (len .Values.services) 1 }}
    {{- include "generic-application.fullname" . }}
  {{- else }}
    {{- printf "%s-%d" (include "generic-application.fullname" $) $service_index }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Pod annotations
*/}}
{{- define "generic-application.podAnnotations" -}}
{{- if or .Values.podAnnotations .Values.vaultAgent.enabled }}
  {{- if .Values.podAnnotations }}
    {{- toYaml .Values.podAnnotations }}
  {{- end }}
  {{- if .Values.vaultAgent.enabled -}}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/agent-inject-status: "update"
vault.hashicorp.com/agent-configmap: "{{ include "generic-application.fullname" . }}-vault-agent"
    {{- if .Values.vaultAgent.securityContext.runAsUser }}
vault.hashicorp.com/agent-run-as-user: "{{ .Values.vaultAgent.securityContext.runAsUser }}"
    {{- end }}
    {{- if .Values.vaultAgent.securityContext.runAsGroup }}
vault.hashicorp.com/agent-run-as-group: "{{ .Values.vaultAgent.securityContext.runAsGroup }}"
    {{- end }}
  {{- end }}
{{- else -}}
{}
{{- end }}
{{- end }}

{{/*
Container image
*/}}
{{- define "generic-application.container.image" -}}
{{- $registryName := ternary (printf "%s/" .imageRoot.registry) "" (not (empty .imageRoot.registry)) }}
{{- $imageRepository := .imageRoot.repository }}
{{- $imageTag := ternary (printf ":%s" .imageRoot.tag) "" (not (empty .imageRoot.tag)) }}
{{- printf "%s%s%s" $registryName $imageRepository $imageTag }}
{{- end }}

{{/*
Create the name of the Vault role to use
*/}}
{{- define "generic-application.vaultRole" -}}
{{- default (include "generic-application.fullname" .) .Values.vault.role }}
{{- end }}

{{/*
Create the Vault secret path to use
*/}}
{{- define "generic-application.vaultSecretPath" -}}
{{- default (printf "secret/%s" (include "generic-application.fullname" .)) .Values.vault.engines.kv.secretPath }}
{{- end }}

{{/*
Vault agent config
*/}}
{{- define "generic-application.vaultAgentConfig" }}
exit_after_auth = {{ ternary true false .configInit }}
pid_file = "/home/vault/pidfile"
auto_auth {
  method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
      role = "{{ include "generic-application.vaultRole" . }}"
    }
  }
  sink "file" {
    config = {
      path = "/vault/secrets/.vault-token"
    }
  }
}
vault {
  address = "{{ .Values.vault.address }}"
}
{{- if and .Values.vault.engines.db.enabled .Values.vaultAgent.db.template.dataSources }}
  {{- if eq .Values.vaultAgent.db.template.type "generic" }}
template {
  contents = <<EOF
databases:
    {{- range .Values.vaultAgent.db.template.dataSources }}
      {{- $id := default .name .id }}
  - id: {{ $id }}
    name: {{ .name }}
    engine: {{ .engine }}
    hostname: {{ .hostname }}
    port: {{ .port }}
    options: {{ .options }}
    {{`{{- with secret `}}"database/creds/{{ .hostname | trimSuffix "." }}-{{ .port }}-{{ .name }}-{{ .mode }}"{{` }}`}}
    username: {{`{{ .Data.username }}`}}
    password: {{`{{ .Data.password }}`}}
    {{`{{- end }}`}}
    {{- end }}
EOF
  destination = "/vault/secrets/application.yaml"
}
  {{- else if eq .Values.vaultAgent.db.template.type "quarkus" }}
template {
  contents = <<EOF
quarkus.vault.url={{ .Values.vault.address }}
quarkus.vault.authentication.kubernetes.role={{ include "generic-application.vaultRole" . }}
    {{- range .Values.vaultAgent.db.template.dataSources }}
      {{- $id := default .name .id }}
quarkus.vault.credentials-provider.{{ $id }}.credentials-mount={{ .engine }}
quarkus.vault.credentials-provider.{{ $id }}.credentials-role={{ .hostname | trimSuffix "." }}-{{ .port }}-{{ .name }}-{{ .mode }}
quarkus.datasource.{{ $id }}.db-kind={{ .engine }}
quarkus.datasource.{{ $id }}.credentials-provider={{ $id }}
quarkus.datasource.{{ $id }}.jdbc.url=jdbc:{{ .engine }}://{{ .hostname }}:{{ .port }}/{{ .name }}{{ ternary (printf "?%s" .options) "" (not (empty .options)) }}
    {{- end }}
EOF
  destination = "/vault/secrets/application.properties"
}
  {{- else if eq .Values.vaultAgent.db.template.type "solochain" }}
template {
  contents = <<EOF
  {{- range .Values.vaultAgent.db.template.dataSources }}
DBUrl=jdbc:{{ .engine }}://{{ .hostname }}:{{ .port }}/{{ .name }}{{ ternary (printf "?%s" .options) "" (not (empty .options)) }}
{{`{{- with secret `}}"database/creds/{{ .hostname | trimSuffix "." }}-{{ .port }}-{{ .name }}-{{ .mode }}"{{` }}`}}
DBUserName={{`{{ .Data.username }}`}}
DBPassword={{`{{ .Data.password }}`}}
{{`{{- end }}`}}
  {{- end }}
EOF
  destination = "/vault/secrets/application.properties"
}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Chart name, truncated to 63 chars.
*/}}
{{- define "openegiz.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified release prefix, truncated to 42 chars so component suffixes
(up to 21 chars, e.g. "-ditto-things-search") stay within Kubernetes' 63-char
DNS label limit.
*/}}
{{- define "openegiz.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 42 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 42 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 42 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart label value.
*/}}
{{- define "openegiz.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to all resources.
*/}}
{{- define "openegiz.labels" -}}
helm.sh/chart: {{ include "openegiz.chart" . }}
app.kubernetes.io/name: {{ include "openegiz.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "openegiz.name" . }}
{{- end -}}

{{/*
Component selector labels. Usage: include "openegiz.componentSelectorLabels" (dict "context" . "component" "mongodb")
*/}}
{{- define "openegiz.componentSelectorLabels" -}}
app.kubernetes.io/name: {{ include "openegiz.name" .context }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Component full labels. Usage: include "openegiz.componentLabels" (dict "context" . "component" "mongodb")
*/}}
{{- define "openegiz.componentLabels" -}}
{{ include "openegiz.labels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Component resource names (all strictly derived from release fullname).
*/}}
{{- define "openegiz.secretName" -}}
{{- if .Values.credentials.existingSecret -}}
{{- .Values.credentials.existingSecret -}}
{{- else -}}
{{- printf "%s-credentials" (include "openegiz.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "openegiz.mongodb.fullname" -}}
{{- printf "%s-mongodb" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.influxdb.fullname" -}}
{{- printf "%s-influxdb" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.mosquitto.fullname" -}}
{{- printf "%s-mosquitto" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.telegraf.fullname" -}}
{{- printf "%s-telegraf" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.ditto.cluster.fullname" -}}
{{- printf "%s-ditto-cluster" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.ditto.policies.fullname" -}}
{{- printf "%s-ditto-policies" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.ditto.things.fullname" -}}
{{- printf "%s-ditto-things" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.ditto.thingsSearch.fullname" -}}
{{- printf "%s-ditto-things-search" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.ditto.connectivity.fullname" -}}
{{- printf "%s-ditto-connectivity" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.ditto.gateway.fullname" -}}
{{- printf "%s-ditto-gateway" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.ditto.nginx.fullname" -}}
{{- printf "%s-ditto-nginx" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.extendedApi.fullname" -}}
{{- printf "%s-extended-api" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.grafana.fullname" -}}
{{- printf "%s-grafana" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.sceneServer.fullname" -}}
{{- printf "%s-scene-server" (include "openegiz.fullname" .) -}}
{{- end -}}

{{- define "openegiz.init.fullname" -}}
{{- printf "%s-init" (include "openegiz.fullname" .) -}}
{{- end -}}

{{/*
StorageClass helper: component override > global.storageClass > cluster default.
*/}}
{{- define "openegiz.storageClass" -}}
{{- $sc := default .context.Values.global.storageClass .storageClass -}}
{{- if $sc -}}
storageClassName: {{ $sc | quote }}
{{- end -}}
{{- end -}}

{{/*
Shared JAVA_TOOL_OPTIONS for all five Eclipse Ditto services.
Matches deploy/compose/docker-compose.yml (split-brain resolver, heartbeat pause,
and 20-entry header blocklist preventing HTTP Authorization leakage into MQTT).
*/}}
{{- define "openegiz.ditto.javaToolOptions" -}}
-XX:ActiveProcessorCount=2 -XX:+ExitOnOutOfMemoryError -XX:+UseContainerSupport -XX:+UseStringDeduplication -Xss512k -XX:+UseG1GC -XX:MaxGCPauseMillis=150 -Dpekko.coordinated-shutdown.exit-jvm=on -Dpekko.cluster.shutdown-after-unsuccessful-join-seed-nodes=180s -Dpekko.cluster.failure-detector.threshold=15.0 -Dpekko.cluster.failure-detector.expected-response-after=10s -Dpekko.cluster.failure-detector.acceptable-heartbeat-pause=60s -Dditto.cluster.sbr.auto-enable-after=0s -Dpekko.cluster.split-brain-resolver.down-all-when-unstable=off -Dditto.protocol.blocklist.0=raw-request-uri -Dditto.protocol.blocklist.1=cache-control -Dditto.protocol.blocklist.2=connection -Dditto.protocol.blocklist.3=timeout-access -Dditto.protocol.blocklist.4=accept-encoding -Dditto.protocol.blocklist.5=x-forwarded-scheme -Dditto.protocol.blocklist.6=x-forwarded-port -Dditto.protocol.blocklist.7=x-forwarded-for -Dditto.protocol.blocklist.8=forwarded=for -Dditto.protocol.blocklist.9=sec-fetch-mode -Dditto.protocol.blocklist.10=sec-fetch-site -Dditto.protocol.blocklist.11=authorization -Dditto.protocol.blocklist.12=accept-language -Dditto.protocol.blocklist.13=host -Dditto.protocol.blocklist.14=via -Dditto.protocol.blocklist.15=sec-ch-ua -Dditto.protocol.blocklist.16=sec-ch-ua-mobile -Dditto.protocol.blocklist.17=sec-ch-ua-platform -Dditto.protocol.blocklist.18=sec-fetch-dest -Dditto.protocol.blocklist.19=user-agent
{{- end -}}

{{/* 광고 주소. 브로커가 클라이언트에게 알려 주는 자기 주소라 클러스터 안에서 풀리는 DNS여야 한다. */}}
{{- define "kafka-self.advertisedHost" -}}
{{ .Values.name }}-0.{{ .Values.headlessServiceName }}.{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}

{{- define "kafka-self.bootstrap" -}}
{{ include "kafka-self.advertisedHost" . }}:{{ .Values.port }}
{{- end -}}

{{- define "kafka-self.labels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "kafka-self.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "dozy-service.name" -}}{{ .Release.Name }}{{- end -}}

{{- define "dozy-service.labels" -}}
app.kubernetes.io/name: {{ include "dozy-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: dozy
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "dozy-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dozy-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* 필수 값과 금지 값 검사. 클라우드에서 위험하거나 비어 있으면 렌더링 단계에서 실패시킨다 */}}
{{- define "dozy-service.validate" -}}
{{- if not .Values.image.repository }}{{ fail "image.repository가 필요하다" }}{{ end -}}
{{- if not .Values.image.tag }}{{ fail "image.tag가 필요하다 (X.Y.Z 또는 sha-<7자리>)" }}{{ end -}}
{{- if has (toString .Values.image.tag) (list "latest" "main" "master") }}{{ fail (printf "image.tag에 %s는 쓸 수 없다. 버전 또는 sha-<7자리>로 고정한다" .Values.image.tag) }}{{ end -}}
{{- if not .Values.profile }}{{ fail "profile이 필요하다 (SPRING_PROFILES_ACTIVE)" }}{{ end -}}
{{- if has "local" (splitList "," (replace " " "" .Values.profile)) }}{{ fail "local 프로필은 인증을 우회하므로 클라우드에서 쓸 수 없다" }}{{ end -}}
{{- if hasKey .Values.env "SPRING_PROFILES_ACTIVE" }}{{ fail "env에 SPRING_PROFILES_ACTIVE를 넣지 말고 profile로 지정한다" }}{{ end -}}
{{- if hasKey .Values.config "SPRING_PROFILES_ACTIVE" }}{{ fail "config에 SPRING_PROFILES_ACTIVE를 넣지 말고 profile로 지정한다" }}{{ end -}}
{{- range $s := .Values.secretEnv }}{{ if not (has $s.key $.Values.externalSecret.items) }}{{ fail (printf "secretEnv의 %s는 externalSecret.items에 없는 키(%s)를 가리킨다" $s.name $s.key) }}{{ end }}{{ end -}}
{{- range $v := .Values.secretVolumes }}{{ range $i := $v.items }}{{ if not (has $i.key $.Values.externalSecret.items) }}{{ fail (printf "secretVolumes의 %s는 externalSecret.items에 없는 키(%s)를 가리킨다" $v.name $i.key) }}{{ end }}{{ end }}{{ end -}}
{{- end -}}

{{/* env/config 값을 템플릿으로 풀고, 비면 실패시킨다. generated 값 누락(render-config.sh를 안 돌림)을 기동 실패 대신 렌더링 단계에서 잡는다 */}}
{{- define "dozy-service.render" -}}
{{- $r := tpl (toString .value) .root -}}
{{- if eq $r "" }}{{ fail (printf "%s 값이 비었다. releases/generated/ 값이 빠졌는지 확인한다(scripts/render-config.sh)" .key) }}{{ end -}}
{{- $r -}}
{{- end -}}

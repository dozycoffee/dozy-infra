# dozy-service 차트와 releases/ 값을 helm template으로 렌더링해서 검증한다.
# 필요한 것: helm, ruby (macOS 기본 ruby로 충분하다). 클러스터와 GCP 자격 증명은 필요 없다.
#
#   ruby charts/dozy-service/tests/render_test.rb

# 로케일이 없는 환경(LANG 미설정)에서도 한글 출력을 비교할 수 있게 한다
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"
require "json"
require "fileutils"

CHART = File.expand_path("..", __dir__)
ROOT = File.expand_path("../../..", __dir__)
FIXTURES = File.join(CHART, "tests", "fixtures", "generated")
RELEASES = File.join(ROOT, "releases")

module Helm
  # 최소 필수 값. 개별 테스트가 --set으로 덮어쓴다
  BASE = { "image.repository" => "ghcr.io/dozycoffee/dozy-test", "image.tag" => "1.2.3", "profile" => "prod" }.freeze

  # [문서 배열, 오류 문자열, 성공 여부]
  def helm(release: "svc", values: [], set: {}, base: true, show_only: nil, namespace: "app")
    cmd = ["helm", "template", release, CHART, "-n", namespace]
    values.each { |f| cmd.push("-f", f) }
    (base ? BASE.merge(set) : set).each { |k, v| cmd.push("--set", "#{k}=#{v}") }
    cmd.push("-s", show_only) if show_only
    out, err, status = Open3.capture3(*cmd)
    docs = status.success? ? YAML.load_stream(out).compact : []
    [docs, err, status.success?]
  end

  def render(**opts)
    docs, err, ok = helm(**opts)
    assert ok, "helm template 실패: #{err}"
    docs
  end

  def fails(**opts)
    _, err, ok = helm(**opts)
    refute ok, "렌더링이 실패해야 한다"
    err
  end

  def find(docs, kind)
    docs.find { |d| d["kind"] == kind }
  end

  def container(docs)
    find(docs, "Deployment")["spec"]["template"]["spec"]["containers"][0]
  end

  def env_of(docs)
    container(docs)["env"].each_with_object({}) { |e, h| h[e["name"]] = e["value"] || e["valueFrom"] }
  end
end

class DozyServiceChartTest < Minitest::Test
  include Helm

  # ---- 기본 리소스

  def test_default_resources
    kinds = render.map { |d| d["kind"] }.sort
    # 허용 대상이 없어도 NetworkPolicy는 만들어(전부 차단) 우연히 열리지 않게 한다
    assert_equal %w[Deployment NetworkPolicy Service ServiceAccount], kinds
  end

  def test_release_name_is_service_name
    docs = render(release: "inventory")
    assert_equal "inventory", find(docs, "Deployment")["metadata"]["name"]
    assert_equal "inventory", find(docs, "Service")["metadata"]["name"]
    assert_equal "inventory", find(docs, "ServiceAccount")["metadata"]["name"]
  end

  def test_image_is_pinned_reference
    assert_equal "ghcr.io/dozycoffee/dozy-test:1.2.3", container(render)["image"]
  end

  def test_service_targets_named_port
    docs = render(set: { "port" => 8082 })
    svc = find(docs, "Service")
    assert_equal 8082, svc["spec"]["ports"][0]["port"]
    assert_equal "http", svc["spec"]["ports"][0]["targetPort"]
    assert_equal 8082, container(docs)["ports"][0]["containerPort"]
    assert_equal "8082", env_of(docs)["SERVER_PORT"]
  end

  def test_service_selector_matches_pod_labels
    docs = render
    labels = find(docs, "Deployment")["spec"]["template"]["metadata"]["labels"]
    assert_equal labels, find(docs, "Service")["spec"]["selector"]
    assert_equal labels, find(docs, "Deployment")["spec"]["selector"]["matchLabels"]
  end

  # ---- 프로필과 이미지 검사

  def test_profile_becomes_spring_profiles_active
    assert_equal "prod", env_of(render)["SPRING_PROFILES_ACTIVE"]
  end

  def test_rejects_local_profile
    assert_match(/local/, fails(set: { "profile" => "local" }))
  end

  def test_rejects_local_in_profile_list
    assert_match(/local/, fails(set: { "profile" => "prod\\,local" }))
    assert_match(/local/, fails(set: { "profile" => "local\\,prod" }))
  end

  def test_allows_profile_with_local_in_the_name
    # 이름이 local로 시작하는 다른 프로필까지 막지는 않는다
    assert_equal "localish", env_of(render(set: { "profile" => "localish" }))["SPRING_PROFILES_ACTIVE"]
  end

  def test_requires_profile
    assert_match(/profile/, fails(set: { "profile" => "" }))
  end

  def test_rejects_overriding_profile_through_env
    assert_match(/SPRING_PROFILES_ACTIVE/, fails(set: { "env.SPRING_PROFILES_ACTIVE" => "local" }))
    assert_match(/SPRING_PROFILES_ACTIVE/, fails(set: { "config.SPRING_PROFILES_ACTIVE" => "local" }))
  end

  def test_requires_image_tag
    assert_match(/image\.tag/, fails(set: { "image.tag" => "" }))
  end

  def test_requires_image_repository
    assert_match(/image\.repository/, fails(set: { "image.repository" => "" }))
  end

  def test_rejects_floating_tags
    %w[latest main master].each do |tag|
      assert_match(/#{tag}/, fails(set: { "image.tag" => tag }), tag)
    end
  end

  def test_accepts_sha_and_version_tags
    assert_equal "x:sha-4422791", container(render(set: { "image.repository" => "x", "image.tag" => "sha-4422791" }))["image"]
    assert_equal "x:0.1.1", container(render(set: { "image.repository" => "x", "image.tag" => "0.1.1" }))["image"]
  end

  def test_pull_secrets
    assert_nil find(render, "Deployment")["spec"]["template"]["spec"]["imagePullSecrets"]
    docs = render(set: { "imagePullSecrets[0]" => "ghcr-pull" })
    assert_equal [{ "name" => "ghcr-pull" }], find(docs, "Deployment")["spec"]["template"]["spec"]["imagePullSecrets"]
  end

  # ---- 환경변수와 설정

  def test_env_values_are_templated
    docs = render(set: { "db.host" => "10.1.2.3", "env.DB_HOST" => "\\{\\{ .Values.db.host \\}\\}" })
    assert_equal "10.1.2.3", env_of(docs)["DB_HOST"]
  end

  def test_rejects_empty_env_value
    # generated 값이 빠졌을 때 빈 값으로 조용히 기동하지 않게 한다
    err = fails(set: { "env.DB_HOST" => "\\{\\{ .Values.db.host \\}\\}" })
    assert_match(/DB_HOST/, err)
    assert_match(/generated/, err)
  end

  def test_rejects_empty_config_value
    assert_match(/KAFKA/, fails(set: { "config.KAFKA" => "\\{\\{ .Values.kafka.bootstrapServers \\}\\}" }))
  end

  def test_config_creates_configmap_and_env_from
    docs = render(set: { "config.CORS" => "https://a.test" })
    assert_equal({ "CORS" => "https://a.test" }, find(docs, "ConfigMap")["data"])
    assert_equal [{ "configMapRef" => { "name" => "svc" } }], container(docs)["envFrom"]
  end

  def test_no_configmap_when_config_empty
    docs = render
    assert_nil find(docs, "ConfigMap")
    assert_nil container(docs)["envFrom"]
  end

  def test_config_change_rolls_pods
    a = find(render(set: { "config.A" => "1" }), "Deployment")["spec"]["template"]["metadata"]["annotations"]["checksum/config"]
    b = find(render(set: { "config.A" => "2" }), "Deployment")["spec"]["template"]["metadata"]["annotations"]["checksum/config"]
    refute_nil a
    refute_equal a, b
  end

  def test_jvm_options_default_and_override
    assert_match(/MaxRAMPercentage=75/, env_of(render)["JAVA_TOOL_OPTIONS"])
    assert_equal "-Xmx1g", env_of(render(set: { "jvm.options" => "-Xmx1g" }))["JAVA_TOOL_OPTIONS"]
  end

  # ---- 비밀값

  def test_external_secret_references_secret_manager_ids
    docs = render(release: "auth", set: { "externalSecret.items[0]" => "db-password", "externalSecret.items[1]" => "signing-keys" })
    es = find(docs, "ExternalSecret")
    assert_equal "external-secrets.io/v1", es["apiVersion"]
    assert_equal({ "name" => "gcp-secret-manager", "kind" => "ClusterSecretStore" }, es["spec"]["secretStoreRef"])
    assert_equal "auth", es["spec"]["target"]["name"]
    assert_equal [{ "secretKey" => "db-password", "remoteRef" => { "key" => "dozy-auth-db-password" } },
                  { "secretKey" => "signing-keys", "remoteRef" => { "key" => "dozy-auth-signing-keys" } }], es["spec"]["data"]
  end

  def test_secret_prefix_follows_values
    docs = render(set: { "externalSecret.secretPrefix" => "team", "externalSecret.items[0]" => "db-password" })
    assert_equal "team-svc-db-password", find(docs, "ExternalSecret")["spec"]["data"][0]["remoteRef"]["key"]
  end

  def test_no_external_secret_without_items
    assert_nil find(render, "ExternalSecret")
  end

  def test_secret_env_reads_from_secret_key
    docs = render(set: { "externalSecret.items[0]" => "db-password", "secretEnv[0].name" => "DB_PASSWORD", "secretEnv[0].key" => "db-password" })
    assert_equal({ "secretKeyRef" => { "name" => "svc", "key" => "db-password" } }, env_of(docs)["DB_PASSWORD"])
  end

  def test_secret_value_never_appears_as_plain_env
    docs = render(set: { "externalSecret.items[0]" => "db-password", "secretEnv[0].name" => "DB_PASSWORD", "secretEnv[0].key" => "db-password" })
    entry = container(docs)["env"].find { |e| e["name"] == "DB_PASSWORD" }
    refute entry.key?("value")
  end

  def test_secret_env_must_reference_declared_item
    assert_match(/db-password/, fails(set: { "secretEnv[0].name" => "DB_PASSWORD", "secretEnv[0].key" => "db-password" }))
  end

  def test_secret_volume_is_read_only_file_mount
    docs = render(set: { "externalSecret.items[0]" => "signing-keys", "secretVolumes[0].name" => "signing-keys",
                         "secretVolumes[0].mountPath" => "/secrets/signing-keys", "secretVolumes[0].items[0].key" => "signing-keys",
                         "secretVolumes[0].items[0].path" => "dozy-2026-10.pem" })
    mount = container(docs)["volumeMounts"].find { |m| m["name"] == "signing-keys" }
    assert_equal({ "name" => "signing-keys", "mountPath" => "/secrets/signing-keys", "readOnly" => true }, mount)
    vol = find(docs, "Deployment")["spec"]["template"]["spec"]["volumes"].find { |v| v["name"] == "signing-keys" }
    assert_equal "svc", vol["secret"]["secretName"]
    assert_equal 0o400, vol["secret"]["defaultMode"]
    assert_equal [{ "key" => "signing-keys", "path" => "dozy-2026-10.pem" }], vol["secret"]["items"]
  end

  def test_secret_volume_must_reference_declared_item
    err = fails(set: { "secretVolumes[0].name" => "k", "secretVolumes[0].mountPath" => "/k", "secretVolumes[0].items[0].key" => "nope",
                       "secretVolumes[0].items[0].path" => "k.pem" })
    assert_match(/nope/, err)
  end

  # ---- 보안과 종료

  def test_runs_as_non_root_with_locked_down_container
    docs = render
    pod = find(docs, "Deployment")["spec"]["template"]["spec"]
    assert_equal true, pod["securityContext"]["runAsNonRoot"]
    assert_equal 10001, pod["securityContext"]["runAsUser"]
    assert_equal "RuntimeDefault", pod["securityContext"]["seccompProfile"]["type"]
    sc = container(docs)["securityContext"]
    assert_equal false, sc["allowPrivilegeEscalation"]
    assert_equal true, sc["readOnlyRootFilesystem"]
    assert_equal ["ALL"], sc["capabilities"]["drop"]
  end

  def test_tmp_is_writable
    docs = render
    assert_includes container(docs)["volumeMounts"], { "name" => "tmp", "mountPath" => "/tmp" }
    vols = find(docs, "Deployment")["spec"]["template"]["spec"]["volumes"]
    assert_equal({ "name" => "tmp", "emptyDir" => {} }, vols.find { |v| v["name"] == "tmp" })
  end

  def test_probes_use_actuator_health_groups
    c = container(render)
    assert_equal "/actuator/health/liveness", c["livenessProbe"]["httpGet"]["path"]
    assert_equal "/actuator/health/readiness", c["readinessProbe"]["httpGet"]["path"]
    assert_equal "/actuator/health/liveness", c["startupProbe"]["httpGet"]["path"]
    assert_equal "http", c["readinessProbe"]["httpGet"]["port"]
  end

  def test_probe_path_can_be_overridden
    c = container(render(set: { "probes.readiness.path" => "/actuator/health" }))
    assert_equal "/actuator/health", c["readinessProbe"]["httpGet"]["path"]
  end

  def test_startup_probe_allows_slow_boot
    sp = container(render)["startupProbe"]
    assert_operator sp["periodSeconds"] * sp["failureThreshold"], :>=, 120, "Flyway와 JVM 기동을 기다릴 수 있어야 한다"
  end

  def test_graceful_shutdown_window_exceeds_spring_timeout
    docs = render
    pod = find(docs, "Deployment")["spec"]["template"]["spec"]
    pre_stop = container(docs)["lifecycle"]["preStop"]["exec"]["command"]
    assert_equal %w[sleep 5], pre_stop
    assert_operator pod["terminationGracePeriodSeconds"], :>, 30 + 5, "Spring 종료 대기(30초)와 preStop보다 길어야 한다"
  end

  def test_resources_requests_equal_limits
    r = container(render)["resources"]
    assert_equal r["requests"], r["limits"]
  end

  # ---- 선택 리소스

  def test_service_account_workload_identity_annotation
    assert_nil find(render, "ServiceAccount")["metadata"]["annotations"]
    docs = render(set: { "serviceAccount.gcpServiceAccount" => "x@p.iam.gserviceaccount.com" })
    assert_equal "x@p.iam.gserviceaccount.com", find(docs, "ServiceAccount")["metadata"]["annotations"]["iam.gke.io/gcp-service-account"]
  end

  def test_service_account_can_be_skipped
    docs = render(set: { "serviceAccount.create" => false })
    assert_nil find(docs, "ServiceAccount")
    assert_equal "default", find(docs, "Deployment")["spec"]["template"]["spec"]["serviceAccountName"]
  end

  def test_network_policy_denies_all_without_allowed_sources
    np = find(render, "NetworkPolicy")
    assert_equal [], np["spec"]["ingress"], "허용 대상이 없는데 전부 열리면 안 된다"
  end

  def test_network_policy_allows_listed_namespaces_and_pods
    docs = render(set: { "networkPolicy.allowedNamespaces[0]" => "app", "networkPolicy.allowedPods[0].app\\.kubernetes\\.io/name" => "inventory" })
    rule = find(docs, "NetworkPolicy")["spec"]["ingress"][0]
    assert_equal [{ "namespaceSelector" => { "matchLabels" => { "kubernetes.io/metadata.name" => "app" } } },
                  { "podSelector" => { "matchLabels" => { "app.kubernetes.io/name" => "inventory" } } }], rule["from"]
    assert_equal [{ "port" => 8080, "protocol" => "TCP" }], rule["ports"]
  end

  def test_network_policy_selects_only_this_service
    sel = find(render(release: "wms"), "NetworkPolicy")["spec"]["podSelector"]["matchLabels"]
    assert_equal "wms", sel["app.kubernetes.io/name"]
  end

  def test_network_policy_can_be_disabled
    assert_nil find(render(set: { "networkPolicy.enabled" => false }), "NetworkPolicy")
  end

  def test_hpa_off_by_default_and_owns_replicas_when_on
    assert_nil find(render, "HorizontalPodAutoscaler")
    assert_equal 2, find(render(set: { "replicas" => 2 }), "Deployment")["spec"]["replicas"]
    docs = render(set: { "hpa.enabled" => true, "hpa.maxReplicas" => 5 })
    assert_equal 5, find(docs, "HorizontalPodAutoscaler")["spec"]["maxReplicas"]
    refute find(docs, "Deployment")["spec"].key?("replicas"), "HPA가 켜지면 replicas를 고정하지 않는다"
  end

  def test_pdb_off_by_default
    assert_nil find(render, "PodDisruptionBudget")
    docs = render(set: { "pdb.enabled" => true })
    assert_equal 1, find(docs, "PodDisruptionBudget")["spec"]["minAvailable"]
  end

  def test_not_exposed_by_default
    assert_nil find(render, "Ingress")
  end

  def test_ingress_exposes_only_listed_paths
    docs = render(set: { "ingress.enabled" => true, "ingress.host" => "auth.dozy.kr", "ingress.paths[0]" => "/api" })
    rule = find(docs, "Ingress")["spec"]["rules"][0]
    assert_equal "auth.dozy.kr", rule["host"]
    assert_equal ["/api"], rule["http"]["paths"].map { |p| p["path"] }
    assert_equal "svc", rule["http"]["paths"][0]["backend"]["service"]["name"]
  end
end

# releases/의 실제 값을 가짜 generated 값(fixtures)과 함께 렌더링해서 검사한다
class ReleasesTest < Minitest::Test
  include Helm

  # 서비스별로 기동에 필요한 환경변수(각 저장소의 설정 문서 기준)
  REQUIRED_ENV = {
    "auth" => %w[AUTH_DB_URL AUTH_DB_USERNAME AUTH_DB_PASSWORD AUTH_ISSUER_BASE_URL AUTH_CORS_ALLOWED_ORIGINS AUTH_APP_URL_INTERNAL
                 AUTH_APP_URL_PARTNER AUTH_MAIL_SENDER AUTH_MAIL_FROM AUTH_SIGNING_KEYS_DIR AUTH_SIGNING_ACTIVE_KID BOOTSTRAP_OWNER_EMAIL],
    "inventory" => %w[DB_HOST DB_PORT DB_NAME DB_USERNAME DB_PASSWORD KAFKA_BOOTSTRAP_SERVERS AUTH_ISSUER_BASE_URI],
    "wms" => %w[DB_HOST DB_PORT DB_NAME DB_USERNAME DB_PASSWORD KAFKA_BOOTSTRAP_SERVERS AUTH_ISSUER_BASE_URI],
    "catalog" => %w[DB_HOST DB_PORT DB_NAME DB_USERNAME DB_PASSWORD KAFKA_BOOTSTRAP_SERVERS DOZY_AUTH_ISSUER_BASE_URI STORE_BASE_URL
                    DOZY_AUTH_CLIENT_SECRET CATALOG_CORS_ALLOWED_ORIGINS],
  }.freeze

  def index
    @index ||= YAML.load_file(File.join(RELEASES, "index.yaml"))
  end

  def service_names
    index["services"].map { |s| s["name"] }
  end

  def render_release(name)
    render(release: name, base: false, namespace: index["namespace"],
           values: [File.join(RELEASES, "common.yaml"), File.join(RELEASES, "#{name}.yaml"),
                    File.join(FIXTURES, "common.yaml"), File.join(FIXTURES, "#{name}.yaml")])
  end

  def test_index_and_release_files_match
    files = Dir[File.join(RELEASES, "*.yaml")].map { |f| File.basename(f, ".yaml") } - %w[index common]
    assert_equal files.sort, service_names.sort
    assert_equal service_names.uniq, service_names, "같은 서비스가 두 번 있다"
  end

  def test_every_service_has_fixture_values
    service_names.each { |n| assert File.exist?(File.join(FIXTURES, "#{n}.yaml")), "#{n}의 fixtures/generated가 없다" }
  end

  def test_auth_is_deployed_before_the_services_that_validate_its_tokens
    waves = index["services"].to_h { |s| [s["name"], s["wave"]] }
    (service_names - ["auth"]).each { |n| assert_operator waves["auth"], :<, waves[n], "#{n}보다 auth가 먼저여야 한다" }
  end

  def test_every_release_renders
    service_names.each { |n| refute_empty render_release(n), n }
  end

  def test_images_are_pinned_and_from_ghcr
    service_names.each do |n|
      image = container(render_release(n))["image"]
      assert_match(%r{\Aghcr\.io/dozycoffee/dozy-[a-z-]+:(\d+\.\d+\.\d+|sha-[0-9a-f]{7})\z}, image, n)
    end
  end

  def test_no_release_uses_local_profile
    service_names.each do |n|
      profile = env_of(render_release(n))["SPRING_PROFILES_ACTIVE"]
      refute_includes profile.split(","), "local", n
    end
  end

  def test_required_env_is_present
    service_names.each do |n|
      env = env_of(render_release(n))
      missing = REQUIRED_ENV.fetch(n) - env.keys
      assert_empty missing, "#{n}에 필요한 환경변수가 없다"
    end
  end

  def test_database_password_comes_from_secret_not_values
    service_names.each do |n|
      env = env_of(render_release(n))
      pass = env["DB_PASSWORD"] || env["AUTH_DB_PASSWORD"]
      assert pass.is_a?(Hash) && pass["secretKeyRef"], "#{n}의 DB 비밀번호는 Secret 참조여야 한다"
    end
  end

  def test_no_secret_like_value_in_releases_files
    Dir[File.join(RELEASES, "*.yaml")].each do |f|
      text = File.read(f)
      refute_match(/BEGIN [A-Z ]*PRIVATE KEY/, text, f)
      text.scan(/^\s*[A-Z_]*(PASSWORD|SECRET|TOKEN)[A-Z_]*:\s*(\S.*)$/).each do |_, value|
        flunk "#{f}에 비밀값처럼 보이는 평문 값이 있다: #{value}"
      end
    end
  end

  def test_secret_items_exist_in_terraform_services_default
    # releases가 가져오려는 Secret Manager 항목은 terraform의 services 선언에도 있어야 한다
    tf = File.read(File.join(ROOT, "terraform", "stacks", "gcp", "variables.tf"))
    service_names.each do |n|
      values = YAML.load_file(File.join(RELEASES, "#{n}.yaml"))
      block = tf[/^\s*#{n}\s*=\s*\{.*?\n\s*\}/m]
      refute_nil block, "terraform services 기본값에 #{n}이 없다"
      (values.dig("externalSecret", "items") || []).each do |item|
        assert_includes block, "\"#{item}\"", "#{n}의 비밀값 #{item}이 terraform services에 선언되지 않았다"
      end
    end
  end

  def test_auth_is_single_replica_with_signing_key_mounted
    docs = render_release("auth")
    assert_equal 1, find(docs, "Deployment")["spec"]["replicas"]
    assert_equal "/secrets/signing-keys", env_of(docs)["AUTH_SIGNING_KEYS_DIR"]
    mount = container(docs)["volumeMounts"].find { |m| m["name"] == "signing-keys" }
    assert_equal "/secrets/signing-keys", mount["mountPath"]
  end

  def test_auth_signing_key_file_name_matches_active_kid
    docs = render_release("auth")
    kid = env_of(docs)["AUTH_SIGNING_ACTIVE_KID"]
    vol = find(docs, "Deployment")["spec"]["template"]["spec"]["volumes"].find { |v| v["name"] == "signing-keys" }
    assert_equal ["#{kid}.pem"], vol["secret"]["items"].map { |i| i["path"] }, "kid와 파일 이름이 다르면 기동에 실패한다"
  end

  def test_inventory_port_matches_service
    docs = render_release("inventory")
    assert_equal 8082, find(docs, "Service")["spec"]["ports"][0]["port"]
    assert_equal "8082", env_of(docs)["SERVER_PORT"]
  end

  def test_service_to_service_urls_match_service_ports
    ports = service_names.to_h { |n| [n, find(render_release(n), "Service")["spec"]["ports"][0]["port"]] }
    { "inventory" => ["WMS_BASE_URL", "wms"], "wms" => ["INVENTORY_BASE_URL", "inventory"] }.each do |svc, (var, target)|
      assert_equal "http://#{target}:#{ports[target]}", env_of(render_release(svc))[var], "#{svc}의 #{var}"
    end
  end

  def test_kafka_address_is_the_headless_pod_dns
    env = env_of(render_release("inventory"))
    assert_equal "kafka-0.kafka-headless.kafka.svc.cluster.local:9092", env["KAFKA_BOOTSTRAP_SERVERS"]
  end

  def test_release_without_generated_values_fails
    docs, err, ok = helm(release: "wms", base: false, values: [File.join(RELEASES, "common.yaml"), File.join(RELEASES, "wms.yaml")])
    refute ok, "generated 값 없이 렌더링되면 빈 값으로 기동한다"
    assert_empty docs
    assert_match(/generated/, err)
  end
end

# deploy.sh와 render-config.sh. 클러스터 대신 --dry-run과 가짜 terraform을 쓴다
class ScriptsTest < Minitest::Test
  DEPLOY = File.join(ROOT, "scripts", "deploy.sh")
  RENDER = File.join(ROOT, "scripts", "render-config.sh")

  def deploy(*args)
    Open3.capture3(DEPLOY, "--dry-run", "--generated", FIXTURES, *args)
  end

  def test_deploy_dry_run_renders_in_index_order
    out, err, status = deploy
    assert status.success?, err
    order = out.scan(/^# --- (\S+) \(wave (\d+)\)/)
    assert_equal "auth", order.first[0]
    assert_equal %w[auth catalog inventory wms], order.map(&:first).sort
    waves = order.map { |_, w| w.to_i }
    assert_equal waves.sort, waves, "wave 오름차순이어야 한다"
  end

  def test_deploy_only_one_service
    out, err, status = deploy("--only", "wms")
    assert status.success?, err
    assert_equal ["wms"], out.scan(/^# --- (\S+)/).flatten
  end

  def test_deploy_rejects_unknown_service
    _, err, status = deploy("--only", "nope")
    refute status.success?
    assert_match(/nope/, err)
  end

  def test_deploy_requires_generated_values
    Dir.mktmpdir do |dir|
      _, err, status = Open3.capture3(DEPLOY, "--dry-run", "--generated", dir)
      refute status.success?
      assert_match(/render-config/, err)
    end
  end

  def test_deploy_rejects_unknown_option
    _, _, status = Open3.capture3(DEPLOY, "--nope")
    refute status.success?
  end

  # 가짜 terraform: `terraform -chdir=<dir> output -json`에 고정 JSON을 돌려준다
  def with_fake_terraform(json)
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(dir, "out.json"), json)
      File.write(File.join(bin, "terraform"), "#!/bin/sh\ncat '#{File.join(dir, "out.json")}'\n")
      FileUtils.chmod(0o755, File.join(bin, "terraform"))
      yield dir, { "PATH" => "#{bin}:#{ENV["PATH"]}" }
    end
  end

  def tf_output(extra = {})
    wrap = ->(v) { { "value" => v } }
    {
      "secret_ids" => wrap.({ "auth/db-password" => "dozy-auth-db-password", "wms/db-password" => "dozy-wms-db-password" }),
      "database_connections" => wrap.({
        "auth" => { "engine" => "postgres", "host" => "10.9.0.3", "port" => 5432, "name" => "auth", "user" => "auth" },
        "wms" => { "engine" => "mysql", "host" => "10.9.0.4", "port" => 3306, "name" => "dozy_wms", "user" => "wms" },
      }),
    }.merge(extra).to_json
  end

  def render_config(json, env = {})
    with_fake_terraform(json) do |dir, path_env|
      out = File.join(dir, "generated")
      stdout, err, status = Open3.capture3(path_env.merge("DOZY_GENERATED_DIR" => out).merge(env), RENDER)
      files = Dir[File.join(out, "*.yaml")].to_h { |f| [File.basename(f, ".yaml"), YAML.load_file(f)] }
      yield files, stdout, err, status
    end
  end

  def test_render_config_writes_common_and_per_service_values
    render_config(tf_output, "DOZY_DOMAIN" => "dozy.kr", "DOZY_OWNER_EMAIL" => "o@example.test") do |files, _, err, status|
      assert status.success?, err
      assert_equal %w[auth common wms], files.keys.sort
      assert_equal "dozy.kr", files["common"]["domain"]
      assert_equal "https://auth.dozy.kr", files["common"]["auth"]["issuerBaseUri"]
      assert_equal "o@example.test", files["common"]["auth"]["bootstrapOwnerEmail"]
      assert_equal "dozy", files["common"]["externalSecret"]["secretPrefix"]
      assert_equal "kafka-0.kafka-headless.kafka.svc.cluster.local:9092", files["common"]["kafka"]["bootstrapServers"]
      assert_equal({ "engine" => "mysql", "host" => "10.9.0.4", "port" => 3306, "name" => "dozy_wms", "user" => "wms" }, files["wms"]["db"])
    end
  end

  def test_render_config_never_writes_passwords
    json = tf_output("database_passwords" => { "sensitive" => true, "value" => { "auth" => "s3cr3t-pass", "wms" => "s3cr3t-pass2" } })
    render_config(json, "DOZY_DOMAIN" => "dozy.kr") do |files, _, _, status|
      assert status.success?
      refute_match(/s3cr3t/, files.to_yaml)
    end
  end

  def test_render_config_output_feeds_the_chart
    # 만들어진 값으로 wms가 실제로 렌더링된다
    with_fake_terraform(tf_output) do |dir, path_env|
      out = File.join(dir, "generated")
      _, err, status = Open3.capture3(path_env.merge("DOZY_GENERATED_DIR" => out, "DOZY_DOMAIN" => "dozy.kr"), RENDER)
      assert status.success?, err
      cmd = ["helm", "template", "wms", CHART, "-f", File.join(RELEASES, "common.yaml"), "-f", File.join(RELEASES, "wms.yaml"),
             "-f", File.join(out, "common.yaml"), "-f", File.join(out, "wms.yaml")]
      _, err, status = Open3.capture3(*cmd)
      assert status.success?, err
    end
  end

  def test_render_config_requires_domain
    Dir.mktmpdir do |dir|
      render_config(tf_output, "HOME" => dir, "DOZY_DOMAIN" => "") do |_, _, err, status|
        # 도메인 환경변수가 없어도 dns tfvars가 있으면 통과할 수 있으므로, 실패 시에는 도메인을 안내해야 한다
        assert_match(/도메인/, err) unless status.success?
      end
    end
  end

  def test_render_config_rejects_managed_kafka
    render_config(tf_output, "DOZY_DOMAIN" => "dozy.kr", "KAFKA_MODE" => "managed") do |_, _, err, status|
      refute status.success?
      assert_match(/managed/, err)
    end
  end

  def test_render_config_fails_when_stack_is_down
    render_config("{}", "DOZY_DOMAIN" => "dozy.kr") do |files, _, err, status|
      refute status.success?
      assert_match(/스택/, err)
      assert_empty files
    end
  end

  def test_render_config_fails_on_missing_output
    render_config({ "secret_ids" => { "value" => { "a/b" => "dozy-a-b" } } }.to_json, "DOZY_DOMAIN" => "dozy.kr") do |_, _, err, status|
      refute status.success?
      assert_match(/database_connections/, err)
    end
  end
end

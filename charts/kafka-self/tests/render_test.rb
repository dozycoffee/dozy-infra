# kafka-self 차트를 helm template으로 렌더링해서 결과를 검증한다.
# 필요한 것: helm, ruby (macOS 기본 ruby로 충분하다). 클러스터와 GCP 자격 증명은 필요 없다.
#
#   ruby charts/kafka-self/tests/render_test.rb

# 로케일이 없는 환경(LANG 미설정)에서도 한글 출력을 비교할 수 있게 한다
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "minitest/autorun"
require "open3"
require "yaml"

CHART = File.expand_path("..", __dir__)
ROOT = File.expand_path("../../..", __dir__)
TEST_TOPICS = File.join(CHART, "tests", "values-topics.yaml")
REAL_TOPICS = File.join(ROOT, "topics", "topics.yaml")

class KafkaSelfRenderTest < Minitest::Test
  # helm template을 실행하고 [문서 배열, 오류 문자열, 성공 여부]를 돌려준다
  def helm(values: [], set: {}, namespace: "kafka", show_only: nil)
    cmd = ["helm", "template", "kafka", CHART, "-n", namespace]
    values.each { |f| cmd.push("-f", f) }
    set.each { |k, v| cmd.push("--set", "#{k}=#{v}") }
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

  def find(docs, kind, name = nil)
    docs.find { |d| d["kind"] == kind && (name.nil? || d["metadata"]["name"] == name) }
  end

  def env_of(statefulset)
    container = statefulset["spec"]["template"]["spec"]["containers"][0]
    container["env"].each_with_object({}) { |e, h| h[e["name"]] = e["value"] }
  end

  # ---- 브로커

  def test_single_broker_statefulset_with_headless_service
    sts = find(render, "StatefulSet", "kafka")
    assert_equal 1, sts["spec"]["replicas"], "단일 브로커여야 한다"
    assert_equal "kafka-headless", sts["spec"]["serviceName"]
    assert_equal "apache/kafka:3.9.1", sts["spec"]["template"]["spec"]["containers"][0]["image"]
  end

  def test_headless_service_resolves_before_ready
    svc = find(render, "Service", "kafka-headless")
    assert_equal "None", svc["spec"]["clusterIP"], "헤드리스여야 파드 DNS가 생긴다"
    assert_equal true, svc["spec"]["publishNotReadyAddresses"], "Ready 전에도 광고 주소가 풀려야 한다"
    assert_equal [9092], svc["spec"]["ports"].map { |p| p["port"] }
  end

  def test_advertised_listener_is_the_pod_dns_not_localhost
    env = env_of(find(render, "StatefulSet"))
    assert_equal "PLAINTEXT://kafka-0.kafka-headless.kafka.svc.cluster.local:9092", env["KAFKA_ADVERTISED_LISTENERS"]
    refute_includes env["KAFKA_ADVERTISED_LISTENERS"], "localhost", "localhost면 연결 후 통신이 실패한다"
  end

  def test_advertised_listener_follows_the_release_namespace
    env = env_of(find(render(namespace: "streaming"), "StatefulSet"))
    assert_equal "PLAINTEXT://kafka-0.kafka-headless.streaming.svc.cluster.local:9092", env["KAFKA_ADVERTISED_LISTENERS"]
  end

  def test_topic_auto_creation_is_disabled
    env = env_of(find(render, "StatefulSet"))
    assert_equal "false", env["KAFKA_AUTO_CREATE_TOPICS_ENABLE"], "토픽은 선언해서 만든다. 자동 생성은 꺼야 한다"
  end

  def test_internal_topics_use_replication_factor_one
    env = env_of(find(render, "StatefulSet"))
    assert_equal "1", env["KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR"]
    assert_equal "1", env["KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR"]
    assert_equal "1", env["KAFKA_TRANSACTION_STATE_LOG_MIN_ISR"]
  end

  def test_kraft_single_node_roles_and_quorum
    env = env_of(find(render, "StatefulSet"))
    assert_equal "broker,controller", env["KAFKA_PROCESS_ROLES"]
    assert_equal "1@localhost:9093", env["KAFKA_CONTROLLER_QUORUM_VOTERS"]
  end

  def test_heap_is_smaller_than_the_memory_limit
    sts = find(render, "StatefulSet")
    env = env_of(sts)
    assert_equal "-Xms1g -Xmx1g", env["KAFKA_HEAP_OPTS"]
    limits = sts["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]
    assert_equal "2Gi", limits["memory"], "힙(1GB)보다 컨테이너 limit이 커야 한다"
  end

  def test_autopilot_friendly_requests_equal_limits
    res = find(render, "StatefulSet")["spec"]["template"]["spec"]["containers"][0]["resources"]
    assert_equal res["requests"], res["limits"], "Autopilot은 requests 기준으로 과금하고 limits와 맞춘다"
  end

  def test_runs_as_non_root_with_dropped_capabilities
    pod = find(render, "StatefulSet")["spec"]["template"]["spec"]
    assert_equal true, pod["securityContext"]["runAsNonRoot"]
    assert_equal 1000, pod["securityContext"]["fsGroup"], "PVC를 UID 1000이 쓸 수 있어야 한다"
    sc = pod["containers"][0]["securityContext"]
    assert_equal false, sc["allowPrivilegeEscalation"]
    assert_equal ["ALL"], sc["capabilities"]["drop"]
  end

  def test_probes_check_the_client_port
    container = find(render, "StatefulSet")["spec"]["template"]["spec"]["containers"][0]
    %w[startupProbe readinessProbe livenessProbe].each do |probe|
      assert_equal "client", container[probe]["tcpSocket"]["port"], "#{probe}가 client 포트를 봐야 한다"
    end
  end

  def test_data_dir_is_a_subpath_so_lost_and_found_is_not_in_the_log_dir
    # ext4 디스크 루트에는 lost+found가 있고, Kafka는 로그 디렉터리의 그 폴더를 토픽으로 읽다가 기동에 실패한다(2026-10-27 GKE에서 확인)
    sts = find(render, "StatefulSet")
    c = sts["spec"]["template"]["spec"]["containers"][0]
    mount = c["volumeMounts"].find { |m| m["name"] == "data" }
    assert_equal "kafka", mount["subPath"]
    assert_equal mount["mountPath"], env_of(sts)["KAFKA_LOG_DIRS"]
  end

  def test_persistent_volume_claim_defaults
    pvc = find(render, "StatefulSet")["spec"]["volumeClaimTemplates"][0]
    assert_equal "data", pvc["metadata"]["name"]
    assert_equal "10Gi", pvc["spec"]["resources"]["requests"]["storage"]
    assert_nil pvc["spec"]["storageClassName"], "비우면 클러스터 기본 StorageClass를 써야 한다"
  end

  def test_storage_size_and_class_are_configurable
    pvc = find(render(set: { "storage.size" => "50Gi", "storage.storageClassName" => "premium-rwo" }), "StatefulSet")["spec"]["volumeClaimTemplates"][0]
    assert_equal "50Gi", pvc["spec"]["resources"]["requests"]["storage"]
    assert_equal "premium-rwo", pvc["spec"]["storageClassName"]
  end

  # ---- 네트워크 정책

  def test_network_policy_allows_only_app_namespace_and_topic_job
    np = find(render, "NetworkPolicy", "kafka")
    assert_equal ["Ingress"], np["spec"]["policyTypes"]
    from = np["spec"]["ingress"][0]["from"]
    namespaces = from.map { |f| f.dig("namespaceSelector", "matchLabels", "kubernetes.io/metadata.name") }.compact
    assert_equal ["app"], namespaces
    assert from.any? { |f| f.dig("podSelector", "matchLabels", "app.kubernetes.io/component") == "topic-init" }, "토픽 생성 Job은 접속할 수 있어야 한다"
    assert_equal [9092], np["spec"]["ingress"][0]["ports"].map { |p| p["port"] }
  end

  def test_network_policy_allowed_namespaces_are_configurable
    np = find(render(set: { "networkPolicy.allowedNamespaces" => "{app,observability}" }), "NetworkPolicy")
    namespaces = np["spec"]["ingress"][0]["from"].map { |f| f.dig("namespaceSelector", "matchLabels", "kubernetes.io/metadata.name") }.compact
    assert_equal %w[app observability], namespaces
  end

  def test_network_policy_can_be_disabled
    assert_nil find(render(set: { "networkPolicy.enabled" => "false" }), "NetworkPolicy")
  end

  # ---- 토픽

  def test_no_topic_resources_without_topics
    docs = render
    assert_nil find(docs, "Job")
    assert_nil find(docs, "ConfigMap")
  end

  def topic_lines(docs)
    find(docs, "ConfigMap", "kafka-topics")["data"]["topics.tsv"].lines.map { |l| l.chomp.split("\t", -1) }
  end

  def test_topics_become_tab_separated_lines
    lines = topic_lines(render(values: [TEST_TOPICS]))
    assert_equal [["test.plain", "3", "1", ""],
                  ["test.compact", "1", "1", "cleanup.policy=compact"],
                  ["test.retained", "2", "1", "cleanup.policy=delete,retention.ms=604800000"]], lines
  end

  def test_replication_factor_defaults_to_one
    assert topic_lines(render(values: [TEST_TOPICS])).all? { |l| l[2] == "1" }
  end

  def test_topics_job_is_a_post_install_and_upgrade_hook
    job = find(render(values: [TEST_TOPICS]), "Job", "kafka-topics-init")
    assert_equal "post-install,post-upgrade", job["metadata"]["annotations"]["helm.sh/hook"]
    assert_equal "before-hook-creation", job["metadata"]["annotations"]["helm.sh/hook-delete-policy"]
  end

  def test_topics_job_targets_the_broker_and_skips_existing_topics
    job = find(render(values: [TEST_TOPICS]), "Job")
    container = job["spec"]["template"]["spec"]["containers"][0]
    bootstrap = container["env"].find { |e| e["name"] == "BOOTSTRAP" }["value"]
    assert_equal "kafka-0.kafka-headless.kafka.svc.cluster.local:9092", bootstrap
    script = container["args"].join("\n")
    assert_includes script, "--if-not-exists", "이미 있는 토픽을 다시 만들려다 실패하면 안 된다"
    assert_includes script, "kafka-broker-api-versions.sh", "브로커가 뜰 때까지 기다려야 한다"
  end

  def test_topics_job_pod_is_labeled_for_the_network_policy
    job = find(render(values: [TEST_TOPICS]), "Job")
    labels = job["spec"]["template"]["metadata"]["labels"]
    assert_equal "topic-init", labels["app.kubernetes.io/component"]
  end

  def test_topics_job_runs_as_non_root_and_mounts_the_topic_list
    pod = find(render(values: [TEST_TOPICS]), "Job")["spec"]["template"]["spec"]
    assert_equal true, pod["securityContext"]["runAsNonRoot"]
    assert_equal "kafka-topics", pod["volumes"][0]["configMap"]["name"]
    assert_equal "/config", pod["containers"][0]["volumeMounts"][0]["mountPath"]
  end

  def test_non_numeric_partitions_fail_rendering_with_a_clear_message
    _docs, err, ok = helm(set: { "topics[0].name" => "t", "topics[0].partitions" => "TBD" })
    refute ok, "TBD 파티션은 렌더링에 실패해야 한다"
    assert_includes err, "partitions는 숫자여야 한다"
    assert_includes err, "TBD"
  end

  def test_invalid_cleanup_policy_fails_rendering
    _docs, err, ok = helm(set: { "topics[0].name" => "t", "topics[0].partitions" => "1", "topics[0].cleanupPolicy" => "purge" })
    refute ok
    assert_includes err, "cleanupPolicy"
  end

  def test_non_numeric_retention_fails_rendering
    _docs, err, ok = helm(set: { "topics[0].name" => "t", "topics[0].partitions" => "1", "topics[0].retentionMs" => "7d" })
    refute ok
    assert_includes err, "retentionMs"
  end

  def test_partitions_must_be_at_least_one
    _docs, err, ok = helm(set: { "topics[0].name" => "t", "topics[0].partitions" => "0" })
    refute ok
    assert_includes err, "1 이상"
  end
end

# 저장소의 실제 토픽 선언(topics/topics.yaml)이 약속한 형식을 지키는지 본다
class TopicsFileTest < Minitest::Test
  def setup
    @topics = YAML.load_file(REAL_TOPICS)["topics"]
  end

  def test_every_topic_has_a_name_and_an_owner
    @topics.each do |t|
      refute_nil t["name"], "name이 없는 토픽이 있다: #{t}"
      refute_nil t["owner"], "#{t["name"]}에 owner가 없다"
    end
  end

  def test_topic_names_are_unique
    names = @topics.map { |t| t["name"] }
    assert_equal names.uniq, names
  end

  def test_every_dlt_topic_has_its_source_topic_declared
    names = @topics.map { |t| t["name"] }
    @topics.select { |t| t["name"].end_with?(".dlt") }.each do |t|
      source = t["name"].sub(/\.dlt\z/, "")
      assert_includes names, source, "#{t["name"]}의 원 토픽 #{source}가 선언되어 있어야 한다"
    end
  end

  def test_product_topic_consumed_by_wms_is_compacted
    product = @topics.find { |t| t["name"] == "dozy.inventory.product" }
    assert_equal "compact", product["cleanupPolicy"], "wms는 처음부터 읽어 상품 사본을 채우므로 압축이 필요하다"
  end

  def test_warehouse_access_keeps_the_settings_wms_used_to_create
    topic = @topics.find { |t| t["name"] == "dozy.wms.warehouse-access" }
    assert_equal 3, topic["partitions"]
    assert_equal "compact", topic["cleanupPolicy"]
    assert_equal 1, topic["replicationFactor"]
  end

  def test_unresolved_partitions_block_rendering_until_decided
    unresolved = @topics.reject { |t| t["partitions"].is_a?(Integer) }.map { |t| t["name"] }
    out, err, status = Open3.capture3("helm", "template", "kafka", CHART, "-n", "kafka", "-f", REAL_TOPICS)
    if unresolved.empty?
      assert status.success?, "모든 파티션이 정해졌는데 렌더링이 실패했다: #{err}"
    else
      refute status.success?, "TBD(#{unresolved.join(", ")})가 남았는데 렌더링이 성공했다"
      assert_includes err, "partitions는 숫자여야 한다"
    end
    refute_nil out
  end
end

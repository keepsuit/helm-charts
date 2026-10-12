require 'json'
require 'minitest/autorun'
require 'open3'
require 'tempfile'
require 'yaml'

class LaravelAppConfigurationTest < Minitest::Test
  CHART = File.expand_path('../charts/laravel', __dir__)
  PROBES = %w[startupProbe readinessProbe livenessProbe].freeze

  def render(app = {}, valid = true)
    values = {
      'global' => { 'image' => { 'repository' => 'example/app', 'tag' => 'test' } },
      'app' => app
    }
    Tempfile.create(['laravel-values', '.json']) do |file|
      file.write(JSON.generate(values))
      file.flush
      output, error, status = Open3.capture3('helm', 'template', 'verify', CHART, '-f', file.path)
      unless valid
        refute status.success?, 'Invalid values should fail rendering'
        assert_match(/schema|probe handler/, error)
        return
      end
      assert status.success?, error
      documents = YAML.load_stream(output)
      return documents.find { |doc| doc['kind'] == 'Deployment' && doc['metadata']['name'].end_with?('-app') }
    end
  end

  def container(deployment)
    deployment.dig('spec', 'template', 'spec', 'containers', 0)
  end

  def test_generated_defaults_for_classic_and_octane
    [false, true].each do |octane|
      deployment = render('octane' => { 'enabled' => octane })
      app = container(deployment)
      handler = octane ? { 'exec' => { 'command' => %w[php artisan octane:status] } } :
        { 'httpGet' => { 'path' => '/healthcheck', 'port' => 8080 } }
      assert_equal handler.merge('periodSeconds' => 2, 'timeoutSeconds' => 5, 'failureThreshold' => 60), app['startupProbe']
      assert_equal handler.merge('initialDelaySeconds' => 0, 'periodSeconds' => 5, 'timeoutSeconds' => 5, 'failureThreshold' => 3), app['readinessProbe']
      assert_equal handler.merge('initialDelaySeconds' => 30, 'periodSeconds' => 30, 'timeoutSeconds' => 5, 'failureThreshold' => 3), app['livenessProbe']
      refute deployment['spec'].key?('progressDeadlineSeconds')
      assert_equal octane, app.key?('lifecycle')
    end
  end

  def test_timing_overrides_keep_handlers_and_allow_zero_delay
    [false, true].each do |octane|
      app = container(render('octane' => { 'enabled' => octane },
        'startupProbe' => { 'periodSeconds' => 5, 'failureThreshold' => 120 },
        'readinessProbe' => { 'timeoutSeconds' => 8, 'successThreshold' => 2 },
        'livenessProbe' => { 'initialDelaySeconds' => 0 }))
      assert_equal 5, app['startupProbe']['periodSeconds']
      assert_equal 120, app['startupProbe']['failureThreshold']
      assert app['startupProbe'].key?(octane ? 'exec' : 'httpGet')
      assert_equal 8, app['readinessProbe']['timeoutSeconds']
      assert_equal 2, app['readinessProbe']['successThreshold']
      assert_equal 0, app['livenessProbe']['initialDelaySeconds']
    end
  end

  def test_handler_overrides_replace_instead_of_merging
    handlers = {
      'exec' => { 'command' => ['test', '-f', '/tmp/ready'] },
      'httpGet' => { 'port' => 'http', 'path' => '/up' },
      'tcpSocket' => { 'port' => 8080 },
      'grpc' => { 'port' => 9000 }
    }
    [false, true].each do |octane|
      PROBES.each do |probe|
        handlers.each do |kind, handler|
          app = container(render('octane' => { 'enabled' => octane }, probe => { kind => handler }))
          assert_equal [kind], app[probe].keys & handlers.keys
          assert_equal handler, app[probe][kind]
          assert app[probe].key?('failureThreshold')
        end
      end
    end
  end

  def test_disable_individual_probes_or_all_health_checks
    [false, true].each do |octane|
      PROBES.each do |probe|
        app = container(render('octane' => { 'enabled' => octane }, probe => false))
        refute app.key?(probe)
        (PROBES - [probe]).each { |other| assert app.key?(other) }
      end
      app = container(render('octane' => { 'enabled' => octane }, 'healthCheck' => { 'enabled' => false }))
      PROBES.each { |probe| refute app.key?(probe) }
      assert_equal octane, app.key?('lifecycle')
    end
  end

  def test_empty_and_null_overrides_retain_defaults
    [nil, {}].each do |override|
      app = container(render(PROBES.to_h { |probe| [probe, override] }))
      PROBES.each { |probe| assert app[probe].key?('httpGet') }
    end
  end

  def test_progress_deadline_and_argument_boundaries
    extra = ['--server=roadrunner', '--rr-config=/app/custom config.yaml', '--name="quoted"', '$(literal)']
    deployment = render('progressDeadlineSeconds' => 900, 'octane' => { 'enabled' => true, 'extraArgs' => extra })
    assert_equal 900, deployment['spec']['progressDeadlineSeconds']
    assert_equal %w[php artisan octane:start --port=8080 --host=0.0.0.0 --workers=auto --log-level=info] + extra,
      container(deployment)['args']
    refute container(render('octane' => { 'extraArgs' => extra })).key?('args')
  end

  def test_invalid_values_are_rejected
    [
      { 'startupProbe' => true },
      { 'startupProbe' => { 'periodSeconds' => 0 } },
      { 'startupProbe' => { 'failureThreshold' => -1 } },
      { 'startupProbe' => { 'successThreshold' => 2 } },
      { 'livenessProbe' => { 'successThreshold' => 2 } },
      { 'readinessProbe' => { 'exec' => { 'command' => [] } } },
      { 'startupProbe' => { 'httpGet' => { 'port' => 'http' }, 'exec' => { 'command' => ['true'] } } },
      { 'progressDeadlineSeconds' => 0 },
      { 'octane' => { 'extraArgs' => [500] } }
    ].each { |values| render(values, false) }
  end
end

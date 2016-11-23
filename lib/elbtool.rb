require 'elbtool/version'
require 'trollop'
require 'aws-sdk'
require 'net/http'
require 'byebug'

class Elbtool
  def self.run
    Elbtool.new.run
  end

  def run
    return register if opts[:register]
    deregister
    puts 'Done'
  end

  private

  def register
    elb.register_instances_with_load_balancer(
      instances: [{ instance_id: instance_id }],
      load_balancer_name: load_balancer_name
    )

    print 'Waiting for instance to become healthy...'

    register_timeout.times do
      return if instance_health.state == 'InService'
      print '.'
      sleep 1
    end

    h_o = instance_health

    fail "Instance failed to enter state 'InService' within #{register_timeout} seconds \n" \
         "(state: #{h_o.state}; reason_code: #{h_o.reason_code}; description: #{h_o.description})"
  end

  def deregister
    elb.deregister_instances_from_load_balancer(
      instances: [{ instance_id: instance_id }],
      load_balancer_name: load_balancer_name
    )

    print 'Waiting for instance to deregister...'

    deregister_timeout.times do
      return unless instance_health
      print '.'
      sleep 1
    end

    h_o = instance_health

    fail "Instance failed to deregister within #{deregister_timeout} seconds \n" \
         "(state: #{h_o.state}; reason_code: #{h_o.reason_code}; description: #{h_o.description})"
  end

  def instance_id
    @instance_id ||=
      opts[:instance_id] || begin
        uri = URI 'http://169.254.169.254/2016-06-30/meta-data/instance-id'
        Net::HTTP.start(uri.host, uri.port, open_timeout: 1) { |http| http.get uri.path }.body
      rescue Net::OpenTimeout
        puts '`instance_id` could not be retrieved from instance metadata. Please specify ' \
             '--instance-id if you are not running on an ec2 instance.'
        exit 1
      end
  end

  def instance_health
    elb.describe_instance_health(load_balancer_name: load_balancer_name).instance_states.find do |i|
      i['instance_id'] == instance_id
    end
  end

  def elb
    @elb ||= Aws::ElasticLoadBalancing::Client.new
  end

  def load_balancer_name
    @load_balancer_name ||= (opts[:register] || opts[:deregister])
  end

  def register_timeout
    @register_timeout ||= begin
      return opts[:register_timeout] if opts[:register_timeout]
      health_check_obj = elb.describe_load_balancers(
        load_balancer_names: [load_balancer_name]
      ).load_balancer_descriptions.first.health_check

      # Base the register_timeout on the existing load balancer configuration
      health_check_obj.interval * health_check_obj.healthy_threshold + 15
    end
  end

  def deregister_timeout
    @deregister_timeout ||= begin
      return opts[:deregister_timeout] if opts[:deregister_timeout]
      c_d = elb.describe_load_balancer_attributes(
        load_balancer_name: load_balancer_name
      ).load_balancer_attributes.connection_draining
      (c_d.enabled ? c_d.timeout : 0) + 5
    end
  end

  def opts
    @opts ||= Trollop.options do
      opt :register, 'Register node with the specified ELB', short: 'r', type: String
      opt :deregister, 'De-register node from the specified ELB', short: 'd', type: String
      opt :instance_id, 'Instance ID (retrieved from local metadata by default)',
          short: 'i',
          type: String
      opt :register_timeout,
          'Registration timeout in seconds (defaults to `interval` * `healthy_threshold` + 15)',
          type: Integer
      opt :deregister_timeout,
          'De-registration timeout in seconds (defaults to `connection_draining` timeout + 5)',
          type: Integer
    end

    return @opts if @opts[:register] || @opts[:deregister]
    Trollop.die 'Please specify either --register or --deregister'
  end
end

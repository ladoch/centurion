require_relative 'docker_server_group'
require 'uri'

module Centurion::DeployDSL
  def on_each_docker_host(&block)
    build_server_group.tap { |hosts| hosts.each { |host| block.call(host) } }
  end

  def env_vars(new_vars)
    current = fetch(:env_vars, {})
    new_vars.each_pair do |new_key, new_value|
      current[new_key.to_s] = new_value.to_s
    end
    set(:env_vars, current)
  end

  def host(hostname, options = {}) 
    host = {
      hostname: hostname,
      options: host_options(options)
    }

    current = fetch(:hosts, [])
    current << host
    set(:hosts, current)
  end

  def memory(memory)
    set(:memory, memory)
  end

  def cpu_shares(cpu_shares)
    set(:cpu_shares, cpu_shares)
  end

  def command(command)
    set(:command, command)
  end

  def localhost
    # DOCKER_HOST is like 'tcp://127.0.0.1:2375'
    docker_host_uri = URI.parse(ENV['DOCKER_HOST'] || "tcp://127.0.0.1")
    host_and_port = [docker_host_uri.host, docker_host_uri.port].compact.join(':')
    host(host_and_port)
  end

  def host_port(port, options)
    validate_options_keys(options, [ :host_ip, :container_port, :type ])
    require_options_keys(options,  [ :container_port ])

    add_to_bindings(
      options[:host_ip],
      options[:container_port],
      port,
      options[:type] || 'tcp'
    )
  end

  def public_port_for(port_bindings)
    # {'80/tcp'=>[{'HostIp'=>'0.0.0.0', 'HostPort'=>'80'}]}
    first_port_binding = port_bindings.values.first
    first_port_binding.first['HostPort']
  end

  def host_volume(volume, options)
    validate_options_keys(options, [ :container_volume ])
    require_options_keys(options,  [ :container_volume ])

    binds            = fetch(:binds, [])
    container_volume = options[:container_volume]

    binds << "#{volume}:#{container_volume}"
    set(:binds, binds)
  end

  def get_current_tags_for(image)
    build_server_group.inject([]) do |memo, target_server|
      tags = target_server.current_tags_for(image)
      memo += [{ server: target_server.hostname, tags: tags }] if tags
      memo
    end
  end

  def registry(type)
    set(:registry, type.to_s)
  end

  private

  def build_server_group
    hosts, docker_path = fetch(:hosts, []), fetch(:docker_path)
    Centurion::DockerServerGroup.new(hosts, docker_path, build_tls_params)
  end

  def host_options(options = {})
    validate_options_keys(options, [ :env_vars, :port_bindings ])

    return {}.tap do |hostOptions|
      hostOptions[:env_vars] = options[:env_vars] if options[:env_vars]

      if options[:port_bindings]
        validate_options_keys(options[:port_bindings], [ :container_port, :port, :type, :host_ip ])
        require_options_keys(options[:port_bindings], [ :container_port, :port ])

        hostOptions[:port_bindings] = port_bindings = {}
        options[:port_bindings].each do |port, params|
          binding = host_port_binding_from(
            params[:host_ip],
            params[:container_port],
            port,
            params[:type] || 'tcp'
          )

          port_bindings[binding[:container_port]] = [ binding[:binding] ]
        end
      end
    end
  end

  def host_port_binding_from(host_ip, container_port, port, type='tcp')
    return { container_port: "#{container_port.to_s}/#{type}" }.tap do |binding|
      binding[:binding] = { 'HostPort' => port.to_s }.tap do |b|
        b['HostIp'] = host_ip if host_ip
      end
    end
  end

  def add_to_bindings(host_ip, container_port, port, type='tcp')
    set(:port_bindings, fetch(:port_bindings, {}).tap do |bindings|
      binding = host_port_binding_from(host_ip, container_port, port, type)
      bindings[binding[:container_port]] = [ binding[:binding] ]
    end)
  end

  def validate_options_keys(options, valid_keys)
    unless options.keys.all? { |k| valid_keys.include?(k) }
      raise ArgumentError.new('Options passed with invalid key!')
    end
  end

  def require_options_keys(options, required_keys)
    missing = required_keys.reject { |k| options.keys.include?(k) }

    unless missing.empty?
      raise ArgumentError.new("Options must contain #{missing.inspect}")
    end
  end

  def tls_paths_available?
    Centurion::DockerViaCli.tls_keys.all? { |key| fetch(key).present? }
  end

  def build_tls_params
    return {} unless fetch(:tlsverify)
    {
      tls: fetch(:tlsverify || tls_paths_available?),
      tlscacert: fetch(:tlscacert),
      tlscert: fetch(:tlscert),
      tlskey: fetch(:tlskey)
    }
  end
end

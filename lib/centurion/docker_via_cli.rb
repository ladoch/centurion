require 'pty'
require_relative 'logging'

module Centurion; end

class Centurion::DockerViaCli
  include Centurion::Logging

  def initialize(hostname, port, docker_path, tls_args = {})
    @docker_host = "tcp://#{hostname}:#{port}"
    @docker_path = docker_path
    @tls_args = tls_args
  end

  def login(registry_user, registry_email, registry_password)
    info "Authorize host in registry to pull images."
    params = "-e #{registry_email} -u #{registry_user} -p #{registry_password} https://registry.hub.docker.com"
    echo(build_command(:login, params))
  end

  def logout
    info "Authorize host in registry to pull images."
    params = "https://registry.hub.docker.com"
    echo(build_command(:logout, params))    
  end

  def pull(image, tag='latest')
    info 'Using CLI to pull'
    echo(build_command(:pull, "#{image}:#{tag}"))
  end

  def tail(container_id)
    info "Tailing the logs on #{container_id}"
    echo(build_command(:logs, container_id))
  end

  def attach(container_id)
    echo(build_command(:attach, container_id))
  end

  private

  def self.tls_keys
    [:tlsverify, :tlscacert, :tlscert, :tlskey]
  end

  def tls_parameters
    return '' if @tls_args.nil? || @tls_args == {}

    tls_flags = ''

    if @tls_args[:tls] == true
      tls_flags << ' --tls=true'
    end

    self.class.tls_keys.each do |key|
      tls_flags << " --#{key}=#{@tls_args[key]}" if @tls_args[key]
    end

    tls_flags
  end

  def build_command(action, destination)
    command = "#{@docker_path} -H=#{@docker_host}"
    command << tls_parameters
    command << case action
               when :pull then ' pull '
               when :logs then ' logs -f '
               when :attach then ' attach '
               when :login then ' login '  
               when :logout then   ' logout ' 
               end
    command << destination
    command
  end
end

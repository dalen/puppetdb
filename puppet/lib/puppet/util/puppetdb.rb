require 'puppet/util'
require 'puppet/util/logging'
require 'puppet/util/puppetdb/command_names'
require 'puppet/util/puppetdb/command'
require 'puppet/util/puppetdb/config'
require 'digest/sha1'
require 'time'
require 'fileutils'
require 'puppet/network/resolver'

# Here we do a ugly monkey patch of puppet
module Puppet::Network::Resolver
  # Iterate through the list of servers that service this hostname
  # and yield each server/port since SRV records have ports in them
  # It will override whatever masterport setting is already set.
  def self.each_srv_record(domain, service_name = :puppet, &block)
    if (domain.nil? or domain.empty?)
      Puppet.debug "Domain not known; skipping SRV lookup"
      return
    end

    Puppet.debug "Searching for SRV records for domain: #{domain}"

    case service_name
    when :puppet then service = '_x-puppet'
    when :ca     then service = '_x-puppet-ca'
    when :report then service = '_x-puppet-report'
    when :file   then service = '_x-puppet-fileserver'
    when :db     then service = '_x-puppet-db'
    end
    srv_record = "#{service}._tcp.#{domain}"

    resolver = Resolv::DNS.new
    records = resolver.getresources(srv_record, Resolv::DNS::Resource::IN::SRV)
    Puppet.debug "Found #{records.size} SRV records for: #{srv_record}"

    if records.size == 0 && service_name != :puppet
      # Try the generic :puppet service if no SRV records were found
      # for the specific service.
      each_srv_record(domain, :puppet, &block)
    else
      each_priority(records) do |priority, records|
        while next_rr = records.delete(find_weighted_server(records))
          Puppet.debug "Yielding next server of #{next_rr.target.to_s}:#{next_rr.port}"
          yield next_rr.target.to_s, next_rr.port
        end
      end
    end
  end
end

module Puppet::Util::Puppetdb

  def self.server
    config.server
  end

  def self.port
    config.port
  end

  def self.config
    @config ||= Puppet::Util::Puppetdb::Config.load
    @config
  end

  # This magical stuff is needed so that the indirector termini will make requests to
  # the correct host/port, because this module gets mixed in to our indirector
  # termini.
  module ClassMethods
    def server
      Puppet::Util::Puppetdb.server
    end

    def port
      Puppet::Util::Puppetdb.port
    end
  end

  def self.included(child)
    child.extend ClassMethods
  end

  ## Given an instance of ruby's Time class, this method converts it to a String
  ## that conforms to PuppetDB's wire format for representing a date/time.
  def self.to_wire_time(time)
    # The current implementation simply calls iso8601, but having this method
    # allows us to change that in the future if needed w/o being forced to
    # update all of the date objects elsewhere in the code.
    time.iso8601
  end


  # Public instance methods

  def submit_command(certname, payload, command_name, version)
    command = Puppet::Util::Puppetdb::Command.new(command_name, version, certname, payload)
    command.submit
  end

  private

  ## Private instance methods

  def config
    Puppet::Util::Puppetdb.config
  end


  def log_x_deprecation_header(response)
    if warning = response['x-deprecation']
      Puppet.deprecation_warning "Deprecation from PuppetDB: #{warning}"
    end
  end
  module_function :log_x_deprecation_header

end

require 'puppet/node'
require 'puppet/indirector/rest'
require 'puppet/util/puppetdb'

class Puppet::Node::Puppetdb < Puppet::Indirector::REST
  include Puppet::Util::Puppetdb

  use_srv_service(:db)

  def find(request)
  end

  def save(request)
  end

  def destroy(request)
    submit_command(request.key, request.key.to_pson, CommandDeactivateNode, 1)
  end
end

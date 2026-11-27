# frozen_string_literal: true

require 'ipaddr'
require 'socket'

module Monadic
  module Utils
    # Whether a host the server is asked to fetch from is on the public
    # internet: every address it resolves to must be one. Loopback, private,
    # link-local, shared (100.64.0.0/10), unspecified, reserved and
    # multicast addresses are refused, and so are the names of this machine
    # and of the Docker host.
    module PublicAddress
      class Refused < StandardError; end

      LOCAL_NAMES = %w[localhost host.docker.internal gateway.docker.internal docker.for.mac.localhost
                       docker.for.win.localhost].freeze
      NOT_PUBLIC = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
                      ::/96 ff00::/8 64:ff9b:1::/48].map { |range| IPAddr.new(range) }.freeze
      RESOLVE_TIMEOUT = 10

      module_function

      # Raises Refused unless host is a public name or address. resolver:
      # the addresses of a name (strings).
      def check!(host, resolver: method(:resolve))
        name = host.to_s.downcase.delete_prefix('[').delete_suffix(']').chomp('.')
        raise Refused, 'no host' if name.empty?
        raise Refused, 'a local name' if LOCAL_NAMES.include?(name) || name.end_with?('.localhost', '.internal')

        addresses = literal?(name) ? [name] : Array(resolver.call(name))
        raise Refused, 'the name does not resolve' if addresses.empty?
        raise Refused, 'not a public address' unless addresses.all? { |address| public?(address) }

        addresses
      end

      def public?(address)
        ip = IPAddr.new(address.to_s)
        ip = ip.native if ip.ipv6? && ip.ipv4_mapped?
        !(ip.loopback? || ip.private? || ip.link_local? || NOT_PUBLIC.any? { |range| range.family == ip.family && range.include?(ip) })
      rescue IPAddr::Error
        false
      end

      def literal?(name)
        IPAddr.new(name)
        true
      rescue IPAddr::Error
        false
      end

      def resolve(name)
        Addrinfo.getaddrinfo(name, nil, nil, :STREAM, timeout: RESOLVE_TIMEOUT).map(&:ip_address).uniq
      rescue SocketError, IOError, SystemCallError
        []
      end
    end
  end
end

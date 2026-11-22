# frozen_string_literal: true

# Loaded with -r into every Ruby process of the capability agreement check
# (the driver and the speech commands it starts). Two stops, each writing a
# line to the file named by MONADIC_TEST_NET_EVENTS:
#
# - A request through Net::HTTP or the http gem stops before it connects:
#   "request <host>", then the connection is refused, as it would be with no
#   network (code that looks for a local service at load time goes on without
#   it; the speech command does not retry a refusal).
# - An IP connection through Ruby's socket classes that gets past those
#   (TCPSocket, Socket.tcp, Socket#connect): "socket <host>", then refused.
#   The check fails on any such line.
#
# The stops are in place once this file has loaded (after bundler/setup);
# a program started outside Ruby, or a native extension, is not covered, nor
# is name resolution (a lookup can still go out; keys here are fake values).
# Nothing else of a request (headers, body, key) is written.
require "socket"
require "net/http"
require "http"

module CapabilityAgreementNoNetwork
  class Stopped < Errno::ECONNREFUSED; end

  EVENTS = ENV.fetch("MONADIC_TEST_NET_EVENTS")

  def self.stop(kind, host)
    File.open(EVENTS, "a") { |f| f.puts("#{kind} #{host}") }
    raise Stopped, "network is off in this test (#{host})"
  end

  module NetHTTP
    def request(*)
      CapabilityAgreementNoNetwork.stop("request", address)
    end
  end

  module HTTPClient
    def request(_verb, uri, *)
      CapabilityAgreementNoNetwork.stop("request", HTTP::URI.parse(uri.to_s).host)
    end
  end

  module TCPOpen
    def new(host, *)
      CapabilityAgreementNoNetwork.stop("socket", host)
    end

    def open(host, *)
      CapabilityAgreementNoNetwork.stop("socket", host)
    end
  end

  module SocketTCP
    def tcp(host, *)
      CapabilityAgreementNoNetwork.stop("socket", host)
    end
  end

  # A socket made by hand: only IP addresses are stopped (a local socket
  # file is not the network).
  module SocketConnect
    def connect(address, ...)
      CapabilityAgreementNoNetwork.stop_ip(address)
      super(address, ...)
    end

    def connect_nonblock(address, ...)
      CapabilityAgreementNoNetwork.stop_ip(address)
      super(address, ...)
    end
  end

  def self.stop_ip(address)
    info = address.is_a?(Addrinfo) ? address : Addrinfo.new(address)
    stop("socket", info.ip_address) if info.ip?
  end
end

Net::HTTP.prepend(CapabilityAgreementNoNetwork::NetHTTP)
HTTP::Client.prepend(CapabilityAgreementNoNetwork::HTTPClient)
TCPSocket.singleton_class.prepend(CapabilityAgreementNoNetwork::TCPOpen)
Socket.singleton_class.prepend(CapabilityAgreementNoNetwork::SocketTCP)
Socket.prepend(CapabilityAgreementNoNetwork::SocketConnect)
File.open(CapabilityAgreementNoNetwork::EVENTS, "a") { |f| f.puts("loaded #{File.basename($PROGRAM_NAME)}") }

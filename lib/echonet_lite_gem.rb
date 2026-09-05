# frozen_string_literal: true

require "json"
require "json_refs"
require "socket"
require "timeout"
require "singleton"

require "echonet_lite_gem/version"
require "echonet_lite_gem/asset_loader"
require "echonet_lite_gem/echonet_lite"
require "echonet_lite_gem/udp_manager"
require "echonet_lite_gem/echonet_node"
require "echonet_lite_gem/hems_controller"
require "echonet_lite_gem/ac_controller"
require "echonet_lite_gem/ewh_controller"

# require_relative "echonet_lite_gem/version"

module EchonetLiteGem
  class Error < StandardError; end
  # Your code goes here...
end

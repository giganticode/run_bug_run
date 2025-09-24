require 'net/http'

module RunBugRun
  module Sandboxing
    NETWORK_CHECK_URL = 'www.google.com'
    SANDBOX_HOME = '/home/sandbox'.freeze
    SANDBOX_HOSTNAME = 'rbr_sandbox'.freeze

    class SandboxingError < StandardError; end

    class << self
      def check_not_in_sandbox!(network_check: true)
        in_sandbox =
          begin
            check_in_sandbox!(network_check: true)
            true
          rescue SandboxingError
            false
          end
        raise SandboxingError, "sandbox detected" if in_sandbox
      end

      def check_in_sandbox!(network_check: false)
        raise_not_in_sandbox! unless File.directory?(SANDBOX_HOME)
        raise_not_in_sandbox! unless ENV['RBR_IN_SANDBOX'] == '1'
        raise_not_in_sandbox! unless Dir['/home/*'] == [SANDBOX_HOME]
        raise_not_in_sandbox! unless Socket.gethostname == SANDBOX_HOSTNAME
        raise_not_in_sandbox! if network_check && can_connect_to_network?
      end

      private

      def raise_not_in_sandbox!
        raise SandboxingError, 'failed to detect sandbox...aborting'
      end

      def can_connect_to_network?
        # FIXME: a ping would be more appropriate
        begin
          Net::HTTP.new(NETWORK_CHECK_URL).head('/')
          true
        rescue Socket::ResolutionError
          false
        end
      end
    end
  end
end
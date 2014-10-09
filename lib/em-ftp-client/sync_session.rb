begin
  require 'fiber'

  module EventMachine
    module FtpClient
      class Error < StandardError
        attr_accessor :response
      end

      class SyncSession < Session
        def initialize(url, options={})
          f = Fiber.current

          super url, options do |conn|
            f.resume(conn)
          end

          yield_with_error_handling
        end

        def pwd
          f = Fiber.current
          super do |arg|
            f.resume(arg)
          end

          yield_with_error_handling
        end

        def cwd(dir)
          f = Fiber.current
          super dir do
            f.resume
          end

          yield_with_error_handling
        end

        def list
          f = Fiber.current
          super do |data|
            f.resume(data)
          end

          yield_with_error_handling
        end

        def get(file)
          f = Fiber.current

          super file do |data|
            f.resume(data)
          end

          yield_with_error_handling
        end

        private

        def yield_with_error_handling
          f = Fiber.current

          error = nil
          control_connection.errback { |response|
            error = Error.new("FTP: #{response.code} #{response.body}")
            error.response = response
            f.resume
          }

          Fiber.yield.tap {
            raise error if error
          }
        end
      end
    end
  end
rescue LoadError
  # Could not load fiber support
end

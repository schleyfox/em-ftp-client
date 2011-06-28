begin
  require 'fiber'

  module EventMachine
    module FtpClient
      class SyncSession < Session
        def initialize(url, options={})
          f = Fiber.current
          super url, options do |conn|
            f.resume(conn)
          end

          Fiber.yield
        end

        def pwd
          f = Fiber.current
          super do |arg|
            f.resume(arg)
          end

          Fiber.yield
        end

        def cwd(dir)
          f = Fiber.current
          super dir do
            f.resume
          end

          Fiber.yield
        end

        def list
          f = Fiber.current
          super do |data|
            f.resume(data)
          end

          Fiber.yield
        end

        def get(file)
          f = Fiber.current

          super file do |data|
            f.resume(data)
          end

          Fiber.yield
        end
      end
    end
  end
rescue LoadError
  # Could not load fiber support
end

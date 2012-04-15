module EventMachine
  module FtpClient
    # Main class for interacting with a server
    class Session
      attr_accessor :username, :password, :port

      attr_reader :control_connection

      def initialize(url, options={}, &cb)
        self.username = options[:username] || "anonymous"
        self.password = options[:password] || "anonymous"
        self.port = options[:port] || 21

        @control_connection = EM.connect(url, port, ControlConnection)
        @control_connection.username = username
        @control_connection.password = password
        @control_connection.callback do
          cb.call(self)
        end
      end

      def pwd(&cb)
        control_connection.callback(&cb)
        control_connection.pwd
      end

      def cwd(dir, &cb)
        control_connection.callback(&cb)
        control_connection.cwd(dir)
      end

      def list(&cb)
        control_connection.callback do
          control_connection.callback(&cb)
          control_connection.list
        end
        control_connection.pasv
      end

      def stream(&cb); @stream = cb; end

      def get(file, &cb)
        control_connection.callback do |data_connection|
          data_connection.stream(&@stream) if @stream
          control_connection.callback(&cb)
          control_connection.retr file
        end
        control_connection.pasv
      end

      def put(file, &cb)
        filename = File.basename(file)
	      control_connection.callback do |data_connection|
          data_connection.send_file(file)
          control_connection.callback(&cb)
          control_connection.stor filename
        end
        control_connection.pasv
      end
    end
  end
end


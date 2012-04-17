module EventMachine
  module FtpClient
    class DataConnection < Connection
      include Deferrable

      def on_connect(&blk); @on_connect = blk; end

      def stream(&blk); @stream = blk; end

      def post_init
        @buf = ''
      end

      def connection_completed
        @on_connect.call(self) if @on_connect
      end

      def receive_data(data)
        @buf += data
        if @stream
          @stream.call(@buf)
          @buf = ''
        end
      end
      
      def send_file(filename)
	      send_file_data(filename)
        close_connection_after_writing
      end

      def unbind
        succeed(@buf)
      end
    end
  end
end

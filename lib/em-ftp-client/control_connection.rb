module EventMachine
  module FtpClient
    class ControlConnection < Connection
      include Protocols::LineText2
  
      attr_accessor :username, :password

      attr_reader :responder

      class InvalidResponseFormat < RuntimeError; end

      class Response
        attr_reader :code, :body, :parent
        def initialize(code=nil, body=nil)
          @code = code
          @body = body
          @empty = true
          @complete = false
        end

        def complete?
          @complete
        end

        def mark?
          code && code[0,1] == "1"
        end

        def success?
          complete? && code && (code[0,1] == "2" || code[0,1] == "3")
        end

        def failure?
          complete? && code && (code[0,1] == "4" || code[0,1] == "5")
        end

        def <<(line)
          # For an empty response
          if @empty
            # If the response is a valid format
            if line =~ /^[1-5]\d{2}( |-)/
              # If the response is multiline
              if line[3,1] == '-'
                @code, @body = line.chomp.split('-', 2)
              # If the response is single line
              elsif line[3,1] == ' '
                @code, @body = line.chomp.split(' ', 2)
                @complete = true
              end
              @empty = false
            else
              raise InvalidResponseFormat.new(line.chomp)
            end
          # If the response is a continuation of a multiline response
          else
            # If this response is terminal
            if line[0..3] == "#{code} "
              @body += "\n#{line.chomp.split(' ', 2)[1]}"
              @complete = true
            # Otherwise continue hoping and wishing for it to be terminated
            else
              @body += "\n#{line.chomp}"
            end
          end

          line
        end
      end
  
      def initialize
      end

      def post_init
        @data_connection = nil
        @response = Response.new
        @responder = nil
      end
  
      def connection_completed
        @responder = :receive_greetings
        @connected = true
      end

      def unbind
        error(Errno::ETIMEDOUT.new) unless @connected
      end

      def error(e)
        @errback.call(e) if @errback
      end

      def receive_line(line)
        # get a new fresh response ready
        if @response.complete?
          @response = Response.new
        end
        @response << line
        if @response.complete?
          # Keep the @response since it is needed in data_connection_closed
          # dispatch appropriately
          if @response.success?
            send(@responder, @response, @data_connection) if @responder
          elsif @response.mark?
            #maybe notice the mark or something
          elsif @response.failure?
            error(@response)
          end
        end
      rescue InvalidResponseFormat => e
        @response = Response.new
        error(e)
      end

      def data_connection_closed(data)
        @data_buffer = data
        data_connection = @data_connection
        @data_connection = nil
        send(@responder, nil, data_connection) if @responder and @response.complete?
      end

      def callback(&blk)
        @callback = blk
      end

      def errback(&blk)
        @errback = blk
      end

      def call_callback(*args)
        old_callback = @callback
        @callback = nil
        old_callback.call(*args) if old_callback
      end

      def call_errback(*args)
        @errback.call(*args) if @errback
        @errback = nil
      end

      # commands
      def user(name)
        send_data("USER #{name}\r\n")
        @responder = :user_response
      end

      def pass(word)
        send_data("PASS #{word}\r\n")
        @responder = :password_response
      end

      def type(t)
        send_data("TYPE #{t}\r\n")
        @responder = :type_response
      end

      def cwd(dir)
        send_data("CWD #{dir}\r\n")
        @responder = :cwd_response
      end

      def pwd
        send_data("PWD\r\n")
        @responder = :pwd_response
      end

      def pasv
        send_data("PASV\r\n")
        @responder = :pasv_response
      end

      def retr(file)
        send_data("RETR #{file}\r\n")
        @responder = :retr_response
      end

      def stor(filename)
        send_data("STOR #{filename}\r\n")
        @responder = :stor_response
      end
      
      def close
        if @data_connection
          raise "Can not close connection while data connection is still open"
        end
        send_data("QUIT\r\n")
        @responder = :close_response
      end

      def dele(filename)
        send_data("DELE #{filename}\r\n")
        @responder = :dele_response
      end

      def list
        send_data("LIST\r\n")
        @responder = :list_response
      end

      # handlers
      
      # Called after initial connection
      def receive_greetings(banner, data_connection)
        if banner.code == "220"
          user username
        end
      end

      # Called when a response for the USER verb is received
      def user_response(response, data_connection)
        pass password
      end

      # Called when a response for the PASS verb is received
      def password_response(response, data_connection)
        type "I"
      end

      # Called when a response for the TYPE verb is received
      def type_response(response, data_connection)
        @responder = nil
        call_callback
      end

      # Called when a response for the CWD or CDUP is received
      def cwd_response(response, data_connection)
        if response && response.code != "226"
          @responder = nil
          call_callback
        end
      end

      # Called when a response for the DELE is received
      def dele_response(response, data_connection)
        @responder = nil
        call_callback
      end

      # Called when a response for the PWD verb is received
      #
      # Calls out with the result to the callback given to pwd
      def pwd_response(response, data_connection)
        @responder = nil
        call_callback(response.body)
      end

      # Called when a response for the PASV verb is received
      #
      # Opens a new data connection and executes the callback
      def pasv_response(response, data_connection)
        @responder = nil
        if response.code == "227"
          if m = /(\d{1,3},\d{1,3},\d{1,3},\d{1,3}),(\d+),(\d+)/.match(response.body)
            # Create a new response for handling the next request on the control connection, since
            # currently @response is the response to pasv, and if the data connection completes
            # before the next control request, data_connection_closed must not use the pasv
            # response to check if the control response is complete (but get/list/etc response)
            @response = Response.new

            host_ip = m[1].gsub(",", ".")
            host_port = m[2].to_i*256 + m[3].to_i
            pasv_callback = @callback
            @data_connection = EM.connect(host_ip, host_port, DataConnection)
            @data_connection.on_connect &pasv_callback
            @data_connection.callback {|data| data_connection_closed(data) }
          end
        end
      end

      def retr_response(response, data_connection)
        if response && response.code != "226"
          data_connection.close_connection
          @responder = nil
          error(response)
        end

        if response && data_connection
          @response = response
          #well we still gots to wait for the file
        elsif data_connection
          #well we need to wait for a response
        else
          @responder = nil
          old_data_buffer = @data_buffer
          @data_buffer = nil
          call_callback(old_data_buffer)
        end
      end

      def stor_response(response, data_connection)
        if response && response.code != "226"
          data_connection.close_connection
          @responder = nil
          error(response)
        end

        @responder = nil
        @data_buffer = nil
        call_callback
      end

      def list_response(response, data_connection)
        if response && response.code != "226"
          data_connection.close_connection
          @responder = nil
          error(response)
        end

        if response && data_connection
          #well we still gots to wait for the file
        elsif data_connection
          #well we need to wait for a response
        else
          @responder = nil
          old_data_buffer = @data_buffer
          @data_buffer = nil
          # parse it into a real form
          file_list = old_data_buffer.split("\n").map do |line|
            ::Net::FTP::List.parse(line.strip)
          end
          call_callback(file_list)
        end
      end
      
      def close_response(response, data_connection)
        close_connection
        call_callback
      end
    end
  end
end

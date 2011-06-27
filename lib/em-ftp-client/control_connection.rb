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
      end

      def error(e)
        @errback.call(e) if @errback
      end

      def receive_line(line)
        @response << line
        if @response.complete?
          # get a new fresh response ready
          old_response = @response
          @response = Response.new

          # dispatch appropriately
          if old_response.success?
            send(@responder, old_response) if @responder
          elsif old_response.mark?
            #maybe notice the mark or something
          elsif old_response.failure?
            error(old_response)
          end
        end
      rescue InvalidResponseFormat => e
        @response = Response.new
        error(e)
      end

      def data_connection_closed(data)
        @data_buffer = data
        @data_connection = nil
        send(@responder) if @responder
      end

      def callback(&blk)
        @callback = blk
      end

      def errback(&blk)
        @errback = blk
      end

      def call_callback(*args)
        @callback.call(*args) if @callback
        @callback = nil
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

      # handlers
      
      # Called after initial connection
      def receive_greetings(banner)
        if banner.code == "220"
          user username
        end
      end

      # Called when a response for the USER verb is received
      def user_response(response)
        pass password
      end

      # Called when a response for the PASS verb is received
      def password_response(response)
        type "I"
      end

      # Called when a response for the TYPE verb is received
      def type_response(response)
        call_callback
        @responder = nil
      end

      # Called when a response for the CWD or CDUP is received
      def cwd_response(response)
        call_callback
        @responder = nil
      end

      # Called when a response for the PWD verb is received
      #
      # Calls out with the result to the callback given to pwd
      def pwd_response(response)
        call_callback(response.body)
        @responder = nil
      end

      # Called when a response for the PASV verb is received
      #
      # Opens a new data connection and executes the callback
      def pasv_response(response)
        if response.code = "227"
          if m = /(\d{1,3},\d{1,3},\d{1,3},\d{1,3}),(\d+),(\d+)/.match(response.body)
            host_ip = m[1].gsub(",", ".")
            host_port = m[2].to_i*256 + m[3].to_i
            pasv_callback = @callback
            @data_connection = EM::Connection.connect(host_ip, host_port, DataConnection)
            @data_connection.on_connect &pasv_callback
            @data_connection.callback {|data| data_connection_closed(data) }
          end
        end
        @responder = nil
      end

      def retr_response(response=nil)
        if response && response.code != "226"
          @data_connection.close_connection
          @responder = nil
          error(response)
        end

        if response && @data_connection
          #well we still gots to wait for the file
        elsif @data_connection
          #well we need to wait for a response
        else
          call_callback(@data_buffer)
          @data_buffer = nil
          @responder = nil
        end
      end

      def list_response(response)
        if response && response.code != "226"
          @data_connection.close_connection
          @responder = nil
          error(response)
        end

        if response && @data_connection
          #well we still gots to wait for the file
        elsif @data_connection
          #well we need to wait for a response
        else
          # parse it into a real form
          call_callback(@data_buffer)
          @data_buffer = nil
          @responder = nil
        end
      end
        
    end
  end
end

require File.join(File.dirname(__FILE__), "helper")

class ControlConnectionTest < Test::Unit::TestCase
  def setup
    @control_connection = EventMachine::FtpClient::ControlConnection.new(:foo)
  end

  context "Response" do
    setup do
      @response = EM::FtpClient::ControlConnection::Response.new
    end

    context "single line" do
      context "success response" do
        setup do
          @code = "200"
          @body = "OK Yeah"
          @response << "#{@code} #{@body}\r\n"
        end
  
        should "be complete" do
          assert @response.complete?
        end
  
        should "be successful" do
          assert @response.success?
          assert !@response.failure?
        end
  
        should "have code and body" do
          assert_equal @code, @response.code
          assert_equal @body, @response.body
        end
  
        should "not be a mark" do
          assert !@response.mark?
        end
      end
  
      context "failure response" do
        setup do
          @code = "500"
          @body = "No Soup For You"
          @response << "#{@code} #{@body}\r\n"
        end
  
        should "be complete" do
          assert @response.complete?
        end
  
        should "be a failure" do
          assert !@response.success?
          assert @response.failure?
        end
  
        should "have code and body" do
          assert_equal @code, @response.code
          assert_equal @body, @response.body
        end
  
        should "not be a mark" do
          assert !@response.mark?
        end
      end
  
      context "mark response" do
        setup do
          @code = "150"
          @body = "Roger that"
          @response << "#{@code} #{@body}\r\n"
        end
  
        should "be complete" do
          assert @response.complete?
        end
  
        should "not be a failure or a success" do
          assert !@response.success?
          assert !@response.failure?
        end
  
        should "have code and body" do
          assert_equal @code, @response.code
          assert_equal @body, @response.body
        end
  
        should "be a mark" do
          assert @response.mark?
        end
      end
    end

    context "multiline" do
      context "valid" do
        should "work" do
          @code = "226"
          @body = ["Oh yeah", "Its on", "And done"]
          @response << "#{@code}-#{@body[0]}\r\n"
          assert !@response.complete?
          @response << "#{@body[1]}\r\n"
          assert !@response.complete?
          @response << "#{@code} #{@body[2]}\r\n"
          assert @response.complete?
          assert_equal @code, @response.code
          assert_equal @body.join("\n"), @response.body
        end
      end

      context "attempted to be closed with a different code" do
        should "not complete" do
          @code = "226"
          @response << "#{@code}-Foo\r\n"
          assert !@response.complete?
          @response << "227 Done\r\n"
          assert !@response.complete?
        end
      end
    end
    
    context "invalid response" do
      should "raise an invalid response format error" do
        assert_raise EM::FtpClient::ControlConnection::InvalidResponseFormat do
          @response << "THIS IS SPARTA\r\n"
        end
      end
    end
  end

  def test_basic_login
    r = EM::FtpClient::ControlConnection::Response
    @control_connection.username = "kingsly"
    @control_connection.password = "password"

    @control_connection.stubs(:send_data => true)

    @control_connection.connection_completed
    assert_equal :receive_greetings, @control_connection.responder
    @control_connection.receive_greetings(r.new("220", "Come on in"))
    assert_equal :user_response, @control_connection.responder
    @control_connection.user_response(r.new("331", "Cool"))
    assert_equal :password_response, @control_connection.responder
    @control_connection.password_response(r.new("230", "Awesome"))
    assert_equal :type_response, @control_connection.responder
  end

  def test_protocol_interaction
    @control_connection.username = "kingsly"
    @control_connection.password = "password"

    @control_connection.connection_completed

    started = false
    working_dir = nil

    @data_host = "127.0.0.1"
    @data_port = 56789

    @data_host_string = "127,0,0,1,221,213"
    
    @data_connection = EM::FtpClient::DataConnection.new(:foo)
    EventMachine.expects(:connect).with(@data_host, @data_port, 
                                        EM::FtpClient::DataConnection).
                                   returns(@data_connection)

    pasv_callback_called = false

    [[nil, nil, "220 Come on in"],
     [nil, "USER kingsly", "331 Cool"],
     [nil, "PASS password", "230 Awesome"],
     [nil, "TYPE I", "200 So Say We All", lambda { started = true }],
     [[:pwd], "PWD", "257 \"/foo\"", lambda{|d| working_dir = d }],
     [[:pasv], "PASV", "227 =#{@data_host_string}", lambda{ pasv_callback_called }]].each do |set|
      @control_connection.expects(:send_data).with(set[1]+"\r\n") if set[1]
    end.each do |set|
      @control_connection.callback(&set[3]) if set[3]
      @control_connection.send(*set[0]) if set[0]
      @control_connection.receive_line(set[2]+"\r\n") if set[2]
    end

    # test RETR
    @control_connection.expects(:send_data).with("RETR foo.txt\r\n")
    @control_connection.retr("foo.txt")

    retr_completed = false
    @control_connection.callback {|data| assert_equal "Bar", data; retr_completed = true }
    assert !retr_completed
    @control_connection.receive_line("226 Hooray\r\n")
    assert !retr_completed
    @data_connection.receive_data("Bar")
    @data_connection.unbind
    assert retr_completed

    # test STOR
    @control_connection.expects(:send_data).with("STOR foo.txt\r\n")
    @control_connection.stor("foo.txt")

    stor_completed = false
    @control_connection.callback {stor_completed = true }
    assert !stor_completed
    @data_connection.unbind
    @control_connection.receive_line("226 Hooray\r\n")
    assert stor_completed

    assert started
    assert_equal "\"/foo\"", working_dir
  end
end


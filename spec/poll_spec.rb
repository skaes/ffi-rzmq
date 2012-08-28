require 'spec_helper'

module ZMQ

  describe Poller do

    context "when initializing" do
      include APIHelper

      it "should allocate a PollItems instance" do
        PollItems.should_receive(:new)
        Poller.new
      end

    end

    context "#register" do

      let(:pollable) { mock('pollable') }
      let(:poller) { Poller.new }
      let(:socket) { FFI::MemoryPointer.new(4) }
      let(:io) { stub(:fileno => fd) }
      let(:fd) { 1 }

      it "returns false when given a nil pollable" do
        poller.register(nil, ZMQ::POLLIN).should be_false
      end

      it "returns false when given 0 for +events+ (e.g. no registration)" do
        poller.register(pollable, 0).should be_false
      end

      it "returns the default registered event value when given a valid pollable" do
        poller.register(pollable).should == (ZMQ::POLLIN | ZMQ::POLLOUT)
      end

      it "returns the registered event value when given a pollable responding to socket (ZMQ::Socket)" do
        pollable.should_receive(:socket).and_return(socket)
        poller.register(pollable, ZMQ::POLLIN).should == ZMQ::POLLIN
      end

      it "returns the registered event value when given a pollable responding to file descriptor (IO, BasicSocket)" do
        pollable.should_receive(:fileno).and_return(fd)
        poller.register(pollable, ZMQ::POLLIN).should == ZMQ::POLLIN
      end

      it "returns the registered event value when given a pollable responding to io (SSLSocket)" do
        pollable.should_receive(:io).and_return(io)
        poller.register(pollable, ZMQ::POLLIN).should == ZMQ::POLLIN
      end

    end

    context "#deregister" do

      let(:pollable) { mock('pollable') }
      let(:poller) { Poller.new }
      let(:socket) { FFI::MemoryPointer.new(4) }
      let(:io) { stub(:fileno => fd) }
      let(:fd) { 1 }

      it "returns true when deregistered pollable from event" do
        pollable.should_receive(:socket).at_least(:once).and_return(socket)
        poller.register(pollable)
        poller.deregister(pollable, ZMQ::POLLIN).should be_true
      end

      it "returns false when pollable not registered" do
        poller.deregister(pollable, ZMQ::POLLIN).should be_false
      end

      it "returns false when pollable not registered for deregistered event" do
        pollable.should_receive(:socket).at_least(:once).and_return(socket)
        poller.register(pollable, ZMQ::POLLOUT)
        poller.deregister(pollable, ZMQ::POLLIN).should be_false
      end

      it "deletes pollable when no events left" do
        poller.register(pollable, ZMQ::POLLIN)
        poller.deregister(pollable, ZMQ::POLLIN).should be_true
        poller.size.should == 0
      end

      it "deletes closed pollable responding to socket (ZMQ::Socket)" do
        pollable.should_receive(:socket).and_return(socket)
        poller.register(pollable)
        pollable.should_receive(:socket).and_return(nil)
        poller.deregister(pollable, ZMQ::POLLIN).should be_true
        poller.size.should == 0
      end

      it "deletes closed pollable responding to fileno (IO, BasicSocket)" do
        pollable.should_receive(:fileno).and_return(fd)
        poller.register(pollable)
        pollable.should_receive(:closed?).and_return(true)
        poller.deregister(pollable, ZMQ::POLLIN).should be_true
        poller.size.should == 0
      end

      it "deletes closed pollable responding to io (SSLSocket)" do
        pollable.should_receive(:io).at_least(:once).and_return(io)
        poller.register(pollable)
        io.should_receive(:closed?).and_return(true)
        poller.deregister(pollable, ZMQ::POLLIN).should be_true
        poller.size.should == 0
      end

    end

    context "#delete" do

      before(:all) do
        @context = Context.new
      end

      before(:each) do
        @socket = @context.socket(XREQ)
        @socket.setsockopt(LINGER, 0)
        @poller = Poller.new
      end

      after(:each) do
        @socket.close
      end

      after(:all) do
        @context.terminate
      end

      it "should return false for an unregistered socket (i.e. not found)" do
        @poller.delete(@socket).should be_false
      end

      it "returns true for a sucessfully deleted socket when only 1 is registered" do
        socket1 = @context.socket(REP)
        socket1.setsockopt(LINGER, 0)

        @poller.register socket1
        @poller.delete(socket1).should be_true
        socket1.close
      end

      it "returns true for a sucessfully deleted socket when more than 1 is registered" do
        socket1 = @context.socket(REP)
        socket2 = @context.socket(REP)
        socket1.setsockopt(LINGER, 0)
        socket2.setsockopt(LINGER, 0)

        @poller.register socket1
        @poller.register socket2
        @poller.delete(socket2).should be_true
        socket1.close
        socket2.close
      end

      it "returns true for a successfully deleted socket when the socket has been previously closed" do
        socket1 = @context.socket(REP)
        socket1.setsockopt(LINGER, 0)

        @poller.register socket1
        socket1.close
        @poller.delete(socket1).should be_true
      end

    end


    context "poll" do
      include APIHelper

      before(:all) do
      end

      before(:each) do
        # Must recreate context for each test otherwise some poll tests fail.
        # This is likely due to a race condition in event handling when reusing
        # the same inproc inside the same context over and over. Making a new
        # context solves it.
        @context = Context.new
        endpoint = "inproc://poll_test"
        @socket = @context.socket(DEALER)
        @socket2 = @context.socket(ROUTER)
        @socket.setsockopt(LINGER, 0)
        @socket2.setsockopt(LINGER, 0)
        @socket.bind(endpoint)
        connect_to_inproc(@socket2, endpoint)

        @poller = Poller.new
      end

      after(:each) do
        @socket.close
        @socket2.close
        @context.terminate
      end

      it "returns 0 when there are no sockets to poll" do
        rc = @poller.poll(100)
        rc.should be_zero
      end

      it "returns 0 when there is a single socket to poll and no events" do
        @poller.register(@socket, 0)
        rc = @poller.poll(100)
        rc.should be_zero
      end

      it "returns 1 when there is a read event on a socket" do
        @poller.register_readable(@socket2)

        @socket.send_string('test')
        rc = @poller.poll(1000)
        rc.should == 1
      end

      it "returns 1 when there is a read event on one socket and the second socket has been removed from polling" do
        @poller.register_readable(@socket2)
        @poller.register_writable(@socket)

        @socket.send_string('test')
        @poller.deregister_writable(@socket)

        rc = @poller.poll(1000)
        rc.should == 1
      end

      it "works with ruby sockets" do
        server = TCPServer.new("127.0.0.1", 0)
        f, port, host, addr = server.addr
        client = TCPSocket.new("127.0.0.1", port)
        s = server.accept

        @poller.register(s, ZMQ::POLLIN)
        @poller.register(client, ZMQ::POLLOUT)

        client.send("message", 0)

        rc = @poller.poll
        rc.should == 2

        @poller.readables.should == [s]
        @poller.writables.should == [client]

        msg = s.recv_nonblock(7)
        msg.should == "message"
      end

      it "does not return readable socket after deregister" do
        server = TCPServer.new("127.0.0.1", 0)
        f, port, host, addr = server.addr
        client = TCPSocket.new("127.0.0.1", port)
        s = server.accept

        @poller.register(s, ZMQ::POLLIN)
        @poller.register(client, ZMQ::POLLOUT)

        @poller.deregister(s, ZMQ::POLLIN)
        @poller.deregister(client, ZMQ::POLLOUT)

        client.send("message", 0)

        rc = @poller.poll
        rc.should == 0

        @poller.readables.should == []
        @poller.writables.should == []
      end

      it "works with io objects" do
        r, w = IO.pipe
        @poller.register(r, ZMQ::POLLIN)
        @poller.register(w, ZMQ::POLLOUT)

        w.write("message")

        rc = @poller.poll
        rc.should == 2

        @poller.readables.should == [r]
        @poller.writables.should == [w]

        msg = r.read(7)
        msg.should == "message"
      end

      it "works with ssl sockets" do
        certificate = File.read('/Users/sensei/messenger/config/test.crt') + File.read('/Users/sensei/messenger/config/test.key')

        ctx = OpenSSL::SSL::SSLContext.new
        ctx.key  = OpenSSL::PKey::RSA.new(certificate)
        ctx.cert = OpenSSL::X509::Certificate.new(certificate)

        server = TCPServer.new("127.0.0.1", 0)
        f, port, host, addr = server.addr
        client = TCPSocket.new("127.0.0.1", port)
        s = server.accept

        client = OpenSSL::SSL::SSLSocket.new(client)
        server = OpenSSL::SSL::SSLSocket.new(s, ctx)

        Thread.new { client.connect }
        s = server.accept

        @poller.register_readable(s)
        @poller.register_writable(client)

        client.syswrite("message")

        rc = @poller.poll
        rc.should == 2

        @poller.readables.should == [s]
        @poller.writables.should == [client]

        msg = s.sysread(7)
        msg.should == "message"
      end
    end # poll


  end # describe Poll


end # module ZMQ

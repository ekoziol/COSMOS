# encoding: ascii-8bit

# Copyright 2014 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

require 'spec_helper'
require 'cosmos/packet_logs/packet_log_writer'

module Cosmos

  describe PacketLogWriter do
    before(:each) do
      System.class_eval('@@instance = nil')
      System.load_configuration
      @log_path = System.paths['LOGS']
    end

    after(:each) do
      clean_config()
    end

    describe "initialize" do
      it "should complain with an unknown log type" do
        expect { PacketLogWriter.new(:BOTH) }.to raise_error
      end

      it "should create a command log writer" do
        plw = PacketLogWriter.new(:CMD,nil,true,nil,10000000,nil,false)
        plw.write(Packet.new('',''))
        plw.stop
        expect(Dir[File.join(@log_path,"*.bin")][-1]).to match("_cmd.bin")
      end

      it "should create a telemetry log writer" do
        plw = PacketLogWriter.new(:TLM,nil,true,nil,10000000,nil,false)
        plw.write(Packet.new('',''))
        plw.stop
        expect(Dir[File.join(@log_path,"*.bin")][-1]).to match("_tlm.bin")
      end

      it "should use log_name in the filename" do
        plw = PacketLogWriter.new(:TLM,'test',true,nil,10000000,nil,false)

        plw.write(Packet.new('',''))
        plw.stop
        expect(Dir[File.join(@log_path,"*.bin")][-1]).to match("testtlm.bin")
      end

      it "should use the log directory" do
        plw = PacketLogWriter.new(:TLM,'packet_log_writer_spec_',true,nil,10000000,Cosmos::USERPATH,false)
        plw.write(Packet.new('',''))
        plw.stop
        expect(Dir[File.join(Cosmos::USERPATH,"*packet_log_writer_spec*")][-1]).to match("_tlm.bin")
        Dir[File.join(Cosmos::USERPATH,"*packet_log_writer_spec*")].each do |file|
          File.delete file
        end
      end
    end

    describe "write" do
      it "should write synchronously to a log" do
        plw = PacketLogWriter.new(:CMD,nil,true,nil,10000000,nil,false)
        pkt = Packet.new('tgt','pkt')
        pkt.buffer = "\x01\x02\x03\x04"
        plw.write(pkt)
        plw.stop
        data = nil
        File.open(Dir[File.join(@log_path,"*.bin")][-1],'rb') do |file|
          data = file.read
        end
        data[-4..-1].should eql "\x01\x02\x03\x04"
      end

      it "should not write packets if logging is disabled" do
        plw = PacketLogWriter.new(:TLM,nil,false,nil,10000000,nil,false)
        pkt = Packet.new('tgt','pkt')
        pkt.buffer = "\x01\x02\x03\x04"
        plw.write(pkt)
        plw.stop
        Dir[File.join(@log_path,"*.bin")].should be_empty
      end

      it "should cycle the log when it a size" do
        plw = PacketLogWriter.new(:TLM,nil,true,nil,200,nil,false)
        pkt = Packet.new('tgt','pkt')
        pkt.buffer = "\x01\x02\x03\x04"
        plw.write(pkt) # size 152
        sleep 0.5
        plw.write(pkt) # size 176
        sleep 0.5
        plw.write(pkt) # size 200
        Dir[File.join(@log_path,"*.bin")].length.should eql 1
        # This write pushs us past 200 so we should start a new file
        plw.write(pkt)
        Dir[File.join(@log_path,"*.bin")].length.should eql 2
        plw.stop
      end

      it "should cycle the log after a set time" do
        # Monkey patch the constant so the test doesn't take forever
        PacketLogWriter.__send__(:remove_const,:CYCLE_TIME_INTERVAL)
        PacketLogWriter.const_set(:CYCLE_TIME_INTERVAL, 0.5)
        plw = PacketLogWriter.new(:TLM,nil,true,3,10000000,nil,false)
        pkt = Packet.new('tgt','pkt')
        pkt.buffer = "\x01\x02\x03\x04"
        plw.write(pkt)
        Dir[File.join(@log_path,"*.bin")].length.should eql 1
        sleep 1
        plw.write(pkt)
        sleep 1
        plw.write(pkt)
        sleep 1
        plw.write(pkt)
        sleep 1
        plw.write(pkt)
        sleep 1
        # Ensure we have two log files
        Dir[File.join(@log_path,"*.bin")].length.should eql 2
        # Check that the log files have timestamps which are 3 (or 4) seconds apart
        files = Dir[File.join(@log_path,"*tlm.bin")].sort
        log1_seconds = files[0].split('_')[-3].to_i * 60 + files[0].split('_')[-2].to_i
        log2_seconds = files[1].split('_')[-3].to_i * 60 + files[1].split('_')[-2].to_i
        (log2_seconds - log1_seconds).should be_within(2).of(3)
        plw.stop
        # Monkey patch the constant back to the default
        PacketLogWriter.__send__(:remove_const,:CYCLE_TIME_INTERVAL)
        PacketLogWriter.const_set(:CYCLE_TIME_INTERVAL, 2)
      end

      it "should write asynchronously to a log" do
        plw = PacketLogWriter.new(:CMD)
        pkt = Packet.new('tgt','pkt')
        pkt.buffer = "\x01\x02\x03\x04"
        plw.write(pkt)
        plw.write(pkt)
        sleep 0.1
        plw.stop
        data = nil
        File.open(Dir[File.join(@log_path,"*.bin")][-1],'rb') do |file|
          data = file.read
        end
        data[-4..-1].should eql "\x01\x02\x03\x04"
        plw.shutdown
      end

      it "should handle errors creating the log file" do
        capture_io do |stdout|
          allow(File).to receive(:new) { raise "Error" }
          plw = PacketLogWriter.new(:CMD)
          pkt = Packet.new('tgt','pkt')
          pkt.buffer = "\x01\x02\x03\x04"
          plw.write(pkt)
          sleep 0.1
          plw.stop
          stdout.string.should match "Error opening"
          plw.shutdown
        end
      end

      it "should handle errors closing the log file" do
        capture_io do |stdout|
          allow(File).to receive(:chmod ) { raise "Error" }
          plw = PacketLogWriter.new(:CMD)
          pkt = Packet.new('tgt','pkt')
          pkt.buffer = "\x01\x02\x03\x04"
          plw.write(pkt)
          sleep 0.1
          plw.stop
          stdout.string.should match "Error closing"
          plw.shutdown
        end
      end
    end

    describe "start" do
      it "should enable logging" do
        plw = PacketLogWriter.new(:TLM,nil,false,nil,10000000,nil,false)
        plw.start
        plw.write(Packet.new('',''))
        plw.stop
        file = Dir[File.join(@log_path,"*.bin")][-1]
        File.size(file).should_not eql 0
      end

      it "should add a label to the log file" do
        plw = PacketLogWriter.new(:TLM,nil,false,nil,10000000,nil,false)
        plw.start('test')
        plw.write(Packet.new('',''))
        plw.stop
        expect(Dir[File.join(@log_path,"*.bin")][-1]).to match("_tlm_test.bin")
      end

      it "should ignore bad label formats" do
        plw = PacketLogWriter.new(:TLM,nil,false,nil,10000000,nil,false)
        plw.start('my_test')
        plw.write(Packet.new('',''))
        plw.stop
        expect(Dir[File.join(@log_path,"*.bin")][-1]).to match("_tlm.bin")
      end
    end

  end
end

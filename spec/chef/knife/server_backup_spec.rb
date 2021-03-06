#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
# Copyright:: Copyright (c) 2012 Fletcher Nichol
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife/server_backup'
require 'fakefs/spec_helpers'
require 'timecop'

describe Chef::Knife::ServerBackup do
  include FakeFS::SpecHelpers

  before do
    Chef::Log.logger = Logger.new(StringIO.new)
    @knife = Chef::Knife::ServerBackup.new
    @stdout = StringIO.new
    @knife.ui.stub!(:stdout).and_return(@stdout)
    @knife.ui.stub(:msg)
    @stderr = StringIO.new
    @knife.ui.stub!(:stderr).and_return(@stderr)
    @knife.config[:backup_dir] = "/baks"

    Chef::Config[:chef_server_url] = "https://chef.example.com:9876"
  end

  describe "configuration" do
    before do
      Chef::Config[:_spec_file_backup_path] = Chef::Config[:file_backup_path]
    end

    after do
      Chef::Config[:file_backup_path] = Chef::Config[:_spec_file_backup_path]
    end

    it "defaults the backup dir to <backup_dir>/<server_name>_<time>" do
      Timecop.freeze(Time.utc(2012, 1, 2, 3, 4, 5)) do
        @knife.config[:backup_dir] = nil
        Chef::Config[:file_backup_path] = "/da/bomb"

        @knife.backup_dir.should eq(
          "/da/bomb/chef.example.com_20120102T030405-0000")
      end
    end
  end

  describe "#run" do
    let(:node_list) { Hash["mynode" => "http://pancakes/nodes/mynode"] }
    let(:role_list) { Hash["myrole" => "http://pancakes/roles/myrole"] }
    let(:env_list) { Hash["myenv" => "http://pancakes/envs/myenv"] }
    let(:data_bag_list) { Hash["mybag" => "http://pancakes/bags/mybag"] }
    let(:data_bag_item_list) { Hash["myitem" => "http://p/bags/mybag/myitem"] }

    before do
      Chef::Node.stub(:list) { node_list }
      Chef::Node.stub(:load).with("mynode") { stub_node("mynode") }
      Chef::Role.stub(:list) { role_list }
      Chef::Role.stub(:load).with("myrole") { stub_role("myrole") }
      Chef::Environment.stub(:list) { env_list }
      Chef::Environment.stub(:load).with("myenv") { stub_env("myenv") }
      Chef::DataBag.stub(:list) { data_bag_list }
      Chef::DataBag.stub(:load).with("mybag") { data_bag_item_list }
      Chef::DataBagItem.stub(:load).
        with("mybag", "myitem") { stub_bag_item("mybag", "myitem")}
    end

    it "exits if component type is invalid" do
      @knife.name_args = %w{nodes toasterovens}

      lambda { @knife.run }.should raise_error SystemExit
    end

    context "for nodes" do
      before { @knife.name_args = %w{nodes} }

      it "creates the backup nodes dir" do
        @knife.run

        File.directory?(["/baks", "nodes"].join("/")).should be_true
      end

      it "sends a message to the ui" do
        @knife.ui.should_receive(:msg).with(/mynode/)

        @knife.run
      end

      it "writes out each node to a json file" do
        @knife.run
        json_str = File.open("/baks/nodes/mynode.json", "rb") { |f| f.read }
        json = JSON.parse(json_str, :create_additions => false)

        json["name"].should eq("mynode")
      end
    end

    context "for roles" do
      before { @knife.name_args = %w{roles} }

      it "creates the backup roles dir" do
        @knife.run

        File.directory?(["/baks", "roles"].join("/")).should be_true
      end

      it "sends a message to the ui" do
        @knife.ui.should_receive(:msg).with(/myrole/)

        @knife.run
      end

      it "writes out each role to a json file" do
        @knife.run
        json_str = File.open("/baks/roles/myrole.json", "rb") { |f| f.read }
        json = JSON.parse(json_str, :create_additions => false)

        json["name"].should eq("myrole")
      end
    end

    context "for environments" do
      before { @knife.name_args = %w{environments} }

      it "creates the backup environments dir" do
        @knife.run

        File.directory?(["/baks", "environments"].join("/")).should be_true
      end

      it "sends a message to the ui" do
        @knife.ui.should_receive(:msg).with(/myenv/)

        @knife.run
      end

      it "writes out each environment to a json file" do
        @knife.run
        json_str = File.open("/baks/environments/myenv.json", "rb") { |f| f.read }
        json = JSON.parse(json_str, :create_additions => false)

        json["name"].should eq("myenv")
      end

      it "skips the _default environment" do
        Chef::Environment.stub(:list) { Hash["_default" => "http://url"] }
        Chef::Environment.stub(:load).with("_default") { stub_env("_default") }
        @knife.run

        File.exists?("/baks/environments/_default.json").should_not be_true
      end
    end

    context "for data_bags" do
      before { @knife.name_args = %w{data_bags} }

      it "creates the backup data_bags dir" do
        @knife.run

        File.directory?(["/baks", "data_bags"].join("/")).should be_true
      end

      it "sends messages to the ui" do
        @knife.ui.should_receive(:msg).with(/myitem/)

        @knife.run
      end

      it "writes out each data bag item to a json file" do
        @knife.run
        json_str = File.open("/baks/data_bags/mybag/myitem.json", "rb") { |f| f.read }
        json = JSON.parse(json_str, :create_additions => false)

        json["name"].should eq("data_bag_item_mybag_myitem")
      end
    end

    context "for all" do
      it "writes a node file" do
        @knife.run

        File.exists?("/baks/nodes/mynode.json").should be_true
      end

      it "writes a role file" do
        @knife.run

        File.exists?("/baks/roles/myrole.json").should be_true
      end

      it "writes an environment file" do
        @knife.run

        File.exists?("/baks/environments/myenv.json").should be_true
      end

      it "writes a data bag item file" do
        @knife.run

        File.exists?("/baks/data_bags/mybag/myitem.json").should be_true
      end
    end
  end

  private

  def stub_node(name)
    n = Chef::Node.new
    n.name(name)
    n
  end

  def stub_role(name)
    r = Chef::Role.new
    r.name(name)
    r
  end

  def stub_env(name)
    e = Chef::Environment.new
    e.name(name)
    e
  end

  def stub_bag_item(bag, name)
    d = Chef::DataBagItem.new
    d.data_bag(bag)
    d.raw_data[:id] = name
    d
  end
end

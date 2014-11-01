require 'spec_helper'
require 'vagrant-dsc/provisioner'
require 'vagrant-dsc/config'
require 'base'

describe VagrantPlugins::DSC::Config do
  include_context "unit"
  let(:instance) { described_class.new }
  let(:machine) { double("machine") }

  def valid_defaults
    # subject.prop = value
  end

  describe "defaults" do

    before do
      env = double("environment", root_path: "/tmp/vagrant-dsc-path")
      config = double("config")
      machine.stub(config: config, env: env)

      allow(machine).to receive(:root_path).and_return("/c/foo")
    end

    # before do
    #   # By default lets be Linux for validations
    #   Vagrant::Util::Platform.stub(linux: true)
    # end

    before { subject.finalize! }

    its("configuration_file")   { expect = "default.ps1" }
    its("manifests_path")       { expect = "." }
    its("configuration_name")   { expect = "default" }
    its("mof_path")             { expect be_nil }
    its("module_path")          { expect be_nil }
    its("options")              { expect = [] }
    its("configuration_params") { expect = {} }
    its("synced_folder_type")   { expect be_nil }
    its("temp_dir")             { expect match /^\/tmp\/vagrant-dsc-*/ }
    its("working_directory")    { expect be_nil }
  end

  describe "derived settings" do

    it "should derive 'configuration_name' from 'configuration_file' automatically" do
      subject.configuration_file = "manifests/MyWebsite.ps1"
      subject.finalize!
      expect(subject.configuration_name).to eq("MyWebsite")
    end

    it "should derive 'configuration_name' from 'configuration_file' automatically, when given multi-level file path" do
      subject.configuration_file = "manifests/foo/MyWebsite.ps1"
      subject.finalize!
      expect(subject.configuration_name).to eq("MyWebsite")
    end

    it "should derive 'configuration_name' from 'configuration_file' automatically, when given no multi-level file path" do
      subject.configuration_file = "MyWebsite.ps1"
      subject.finalize!
      expect(subject.configuration_name).to eq("MyWebsite")
    end

    it "should detect the fully qualified path to the manifest automatically" do
      env = double("environment", root_path: "")
      config = double("config")
      machine.stub(config: config, env: env)
      allow(machine).to receive(:root_path).and_return(".")

      subject.configuration_file = "manifests/MyWebsite.ps1"

      subject.finalize!
      subject.validate(machine)

      basePath = File.absolute_path(File.join(File.dirname(__FILE__), '../../'))
      expect(subject.expanded_configuration_file.to_s).to eq("#{basePath}/manifests/MyWebsite.ps1")
    end
  end

  describe "validate" do
    before { subject.finalize! }

    before do
      env = double("environment", root_path: "")
      config = double("config")
      machine.stub(config: config, env: env)

      allow(machine).to receive(:root_path).and_return("/path/to/vagrant")
    end

    # before do
    #   # By default lets be Linux for validations
    #   Vagrant::Util::Platform.stub(linux: true)
    # end

    # it "should disallow absolute module paths" do
    # end

    it "should generate a module path on the host machine relative to the Vagrantfile" do
      subject.module_path = "foo/modules"
      expect(subject.expanded_module_paths('/path/to/vagrant/')).to eq(["/path/to/vagrant/foo/modules"])
    end

    it "should generate module paths on the host machine relative to the Vagrantfile" do
      subject.module_path = ["dont/exist", "also/dont/exist"]
      expect(subject.expanded_module_paths('/path/to/vagrant/')).to eq(["/path/to/vagrant/dont/exist", "/path/to/vagrant/also/dont/exist"])
    end

    it "should be invalid if 'manifests_path' is not a real directory" do
      subject.manifests_path = "/i/do/not/exist"
      assert_invalid
      assert_error("\"Path to DSC Manifest folder does not exist: /i/do/not/exist\"")
    end

    it "should be invalid if 'configuration_file' is not a real file" do
      subject.manifests_path = "/"
      subject.configuration_file = "notexist.pp"
      assert_invalid
      assert_error("\"Path to DSC Manifest does not exist: /notexist.pp\"")
    end

    it "should be invalid if 'module_path' is not a real directory" do
      subject.module_path = "/i/dont/exist"
      assert_invalid
      assert_error("\"Path to DSC Modules does not exist: /i/dont/exist\"")
    end

    it "should be invalid if 'configuration_file' and 'mof_path' provided" do
      mof = File.new(temporary_file)
      man = File.new(temporary_file)

      subject.configuration_file = File.basename(man)
      subject.mof_path = File.basename(mof)
      expect { subject.finalize! }.to raise_error("\"Cannot provide configuration_file and mof_path at the same time. Please provide only one of the two.\"")
      # assert_error("\"Cannot provide configuration_file and mof_path at the same time. Please provide only one of the two.\"")
    end

    it "should be valid if 'configuration_file' is a real file" do
      file = File.new(temporary_file)

      subject.configuration_file = File.basename(file)
      subject.manifests_path = File.dirname(file)
      subject.module_path = File.dirname(file)
      assert_valid
    end
  end
end
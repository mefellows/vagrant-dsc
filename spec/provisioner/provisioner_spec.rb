require 'spec_helper'
require 'vagrant-dsc/provisioner'
require 'vagrant-dsc/config'
require 'rspec/its'

describe VagrantPlugins::DSC::Provisioner do
  include_context "unit"

  let(:root_path)               { (Pathname.new(Dir.mktmpdir)).to_s }
  let(:ui)                      { Vagrant::UI::Silent.new }
  let(:machine)                 { double("machine", ui: ui) }
  let(:env)                     { double("environment", root_path: root_path, ui: ui) }
  let(:vm)                      { double ("vm") }
  let(:shell)                   { double ("shell") }
  let(:communicator)            { double ("communicator") }
  let(:guest)                   { double ("guest") }
  let(:configuration_file)      { "manifests/MyWebsite.ps1" }
  let(:configuration_data_file) { "manifests/MyConfig.psd1" }
  let(:module_path)             { ["foo/modules", "foo/modules2"] }
  let(:root_config)             { VagrantPlugins::DSC::Config.new }
  subject                       { described_class.new machine, root_config }

  describe "configure" do
    before do
      allow(machine).to receive(:root_config).and_return(root_config)
      machine.stub(config: root_config, env: env)
      root_config.module_path = module_path
      root_config.configuration_file = configuration_file
      root_config.finalize!
      root_config.validate(machine)
    end

    it "should confirm if the OS is Windows by confirming with the communicator" do
      allow(root_config).to receive(:vm).and_return(vm)
      allow(vm).to receive(:communicator).and_return(:winrm)
      expect(subject.windows?).to eq(true)
    end

    it "when given default configuration, should share module and manifest folders with the guest" do
      allow(root_config).to receive(:vm).and_return(vm)
      expect(vm).to receive(:synced_folder).with("#{root_path}/manifests", /\/tmp\/vagrant-dsc-[0-9]+\/manifests/, {:owner=>"root"})
      expect(vm).to receive(:synced_folder).with("#{root_path}/foo/modules", /\/tmp\/vagrant-dsc-[0-9]+\/modules-0/, {:owner=>"root"})
      expect(vm).to receive(:synced_folder).with("#{root_path}/foo/modules2", /\/tmp\/vagrant-dsc-[0-9]+\/modules-1/, {:owner=>"root"})

      subject.configure(root_config)
    end

    it "when given a specific folder type, should modify folder options when sharing module and manifest folders with the guest" do
      root_config.synced_folder_type = "nfs"
      allow(root_config).to receive(:vm).and_return(vm)

      expect(vm).to receive(:synced_folder).with("#{root_path}/manifests", /\/tmp\/vagrant-dsc-[0-9]+\/manifests/, {:type=>"nfs"})
      expect(vm).to receive(:synced_folder).with("#{root_path}/foo/modules", /\/tmp\/vagrant-dsc-[0-9]+\/modules-0/, {:type=>"nfs"})
      expect(vm).to receive(:synced_folder).with("#{root_path}/foo/modules2", /\/tmp\/vagrant-dsc-[0-9]+\/modules-1/, {:type=>"nfs"})

      subject.configure(root_config)
    end

    it "when provided only manifests path, should only share manifest folders with the guest" do
      root_config.synced_folder_type = "nfs"
      root_config.module_path = nil
      allow(root_config).to receive(:vm).and_return(vm)

      expect(vm).to receive(:synced_folder).with("#{root_path}/manifests", /\/tmp\/vagrant-dsc-[0-9]+\/manifests/, {:type=>"nfs"})

      subject.configure(root_config)
    end

    it "should install DSC for supported OS's" do
      expect { subject.install_dsc }.to raise_error("\"Operation unsupported / not-yet implemented: install_dsc\"")


      # "Operation unsupported / not-yet implemented: install_dsc"
      # expect { subject.install_dsc }.to raise_error(VagrantPlugins::DSC::DSCError)
    end
  end

  describe "verify shared folders" do

    before do
      allow(machine).to receive(:root_config).and_return(root_config)
      machine.stub(config: root_config, env: env, communicate: communicator)
      root_config.module_path = module_path
      root_config.configuration_file = configuration_file
      root_config.finalize!
      root_config.validate(machine)
    end

    it "should raise error if folders not shared" do
      root_config.synced_folder_type = "nfs"

      expect(communicator).to receive(:test).twice.with("test -d foo/modules", {:sudo=>true}).and_return(false)

      subject.configure(root_config)

      folders = module_path << File.dirname(configuration_file)
      expect { subject.verify_shared_folders(folders) }.to raise_error("Shared folders not properly configured. This is generally resolved by a 'vagrant halt && vagrant up'")
    end

    it "should ensure shared folders are properly shared" do
      root_config.synced_folder_type = "nfs"

      expect(communicator).to receive(:test).twice.with("test -d foo/modules", {:sudo=>true}).and_return(true)
      expect(communicator).to receive(:test).twice.with("test -d foo/modules2", {:sudo=>true}).and_return(true)
      expect(communicator).to receive(:test).twice.with("test -d manifests", {:sudo=>true}).and_return(true)

      subject.configure(root_config)

      folders = module_path << File.dirname(configuration_file)
      subject.verify_shared_folders(folders)
    end
  end

  describe "provision" do

    before do
      # allow(root_config).to receive(:vm).and_return(vm)
      allow(machine).to receive(:root_config).and_return(root_config)
      allow(machine).to receive(:env).and_return(env)
      root_config.module_path = module_path
      root_config.configuration_file = configuration_file
      root_config.finalize!
      root_config.validate(machine)
      subject.configure(root_config)
      # allow(root_config).to receive(:vm).and_return(vm)
      machine.stub(config: root_config, env: env, communicate: communicator, guest: guest)
    end

    it "should allow reboot capability when capability exists" do
      allow(communicator).to receive(:sudo)
      allow(communicator).to receive(:test)
      allow(communicator).to receive(:upload)
      allow(subject).to receive(:verify_shared_folders).and_return(true)
      allow(subject).to receive(:verify_dsc).and_return(true)
      allow(subject).to receive(:run_dsc_apply).and_return(true)
      allow(subject).to receive(:wait_for_dsc_completion)
      allow(guest).to receive(:capability?).with(:wait_for_reboot).and_return(true)
      expect(guest).to receive(:capability).with(:wait_for_reboot)

      subject.provision
    end

    it "should not allow reboot capability when capability does not exist" do
      allow(communicator).to receive(:sudo)
      allow(communicator).to receive(:test)
      allow(communicator).to receive(:upload)
      allow(subject).to receive(:verify_shared_folders).and_return(true)
      allow(subject).to receive(:verify_dsc).and_return(true)
      allow(subject).to receive(:run_dsc_apply).and_return(true)
      allow(subject).to receive(:wait_for_dsc_completion) 
      allow(guest).to receive(:capability?).with(:wait_for_reboot).and_return(false)
      expect(guest).to_not receive(:capability).with(:wait_for_reboot)

      subject.provision
    end

    it "should create temporary folders on the guest" do
      allow(communicator).to receive(:test)
      allow(communicator).to receive(:upload)
      allow(subject).to receive(:verify_shared_folders).and_return(true)
      allow(subject).to receive(:verify_dsc).and_return(true)
      allow(subject).to receive(:run_dsc_apply).and_return(true)
      allow(subject).to receive(:wait_for_dsc_completion)
      allow(guest).to receive(:capability?)
      allow(guest).to receive(:capability)

      expect(communicator).to receive(:sudo).with("mkdir -p #{root_config.temp_dir}")
      expect(communicator).to receive(:sudo).with("chmod 0777 #{root_config.temp_dir}")

      subject.provision
    end

    it "should generate and write the runner script to the guest" do
      allow(communicator).to receive(:test)
      allow(communicator).to receive(:upload)
      allow(subject).to receive(:verify_shared_folders).and_return(true)
      allow(subject).to receive(:verify_dsc).and_return(true)
      allow(subject).to receive(:run_dsc_apply).and_return(true)
      allow(subject).to receive(:wait_for_dsc_completion)
      allow(guest).to receive(:capability?)
      allow(guest).to receive(:capability)

      expect(communicator).to receive(:sudo).with("mkdir -p #{root_config.temp_dir}")
      expect(communicator).to receive(:sudo).with("chmod 0777 #{root_config.temp_dir}")
      expect(subject).to receive(:verify_dsc)
      expect(subject).to receive(:write_dsc_runner_script)
      expect(subject).to receive(:run_dsc_apply)

      subject.provision
    end

    it "should ensure shared folders are properly configured" do
      allow(communicator).to receive(:test)
      allow(communicator).to receive(:sudo)
      allow(communicator).to receive(:upload)
      allow(subject).to receive(:verify_dsc).and_return(true)
      allow(subject).to receive(:run_dsc_apply).and_return(true)
      allow(subject).to receive(:wait_for_dsc_completion)
      allow(guest).to receive(:capability?)
      allow(guest).to receive(:capability)

      check = ["#{root_config.temp_dir}/manifests", "#{root_config.temp_dir}/modules-0", "#{root_config.temp_dir}/modules-1"]
      expect(subject).to receive(:verify_shared_folders).with(check)

      subject.provision
    end

    it "should provision wait for dsc" do
      allow(communicator).to receive(:sudo)
      allow(communicator).to receive(:test)
      allow(communicator).to receive(:upload)
      allow(subject).to receive(:verify_shared_folders).and_return(true)
      allow(subject).to receive(:verify_dsc).and_return(true)
      allow(subject).to receive(:run_dsc_apply).and_return(true)
      allow(guest).to receive(:capability?).with(:wait_for_reboot).and_return(true)
      allow(guest).to receive(:capability).with(:wait_for_reboot)
      expect(subject).to receive(:wait_for_dsc_completion)

      subject.provision
    end

    it "should wait for pending reboot" do
      allow_any_instance_of(Object).to receive(:sleep)
      allow(guest).to receive(:capability?).with(:wait_for_reboot).and_return(true)
      allow(communicator).to receive(:shell).and_return(shell)
      allow(subject).to receive(:get_lcm_state).and_return("PendingReboot", "Busy", "Sucess")
      allow(subject).to receive(:get_configuration_status).and_return("Sucess")
      allow(subject).to receive(:get_guest_powershell_version).and_return("5")
      expect(guest).to receive(:capability).with(:wait_for_reboot)

      subject.wait_for_dsc_completion
    end

    it "should wait for multi pending reboots" do
      allow_any_instance_of(Object).to receive(:sleep)
      allow(guest).to receive(:capability?).with(:wait_for_reboot).and_return(true)
      allow(communicator).to receive(:shell).and_return(shell)
      allow(subject).to receive(:get_lcm_state).and_return("PendingReboot", "Busy", "PendingReboot", "Busy", "Idle")
      allow(subject).to receive(:get_configuration_status).and_return("Success")
      allow(subject).to receive(:get_guest_powershell_version).and_return("5")
      expect(guest).to receive(:capability).twice.with(:wait_for_reboot)

      subject.wait_for_dsc_completion
    end

    it "should show error message on failure" do
      allow_any_instance_of(Object).to receive(:sleep)
      allow(guest).to receive(:capability?).with(:wait_for_reboot).and_return(true)
      allow(communicator).to receive(:shell).and_return(shell)
      allow(guest).to receive(:capability).with(:wait_for_reboot)
      allow(subject).to receive(:get_lcm_state).and_return("PendingReboot", "Busy", "PendingConfiguration")
      allow(subject).to receive(:get_configuration_status).and_return("Failure")
      allow(subject).to receive(:get_guest_powershell_version).and_return("5")
      expect(subject).to receive(:show_dsc_failure_message)

      subject.wait_for_dsc_completion
    end

    it "should not get the lcm state if powershell version is 4" do
      allow(guest).to receive(:capability?).with(:wait_for_reboot).and_return(true)
      allow(communicator).to receive(:shell).and_return(shell)
      allow(subject).to receive(:get_guest_powershell_version).and_return("4")
      expect(subject).to_not receive(:get_lcm_state)

      subject.wait_for_dsc_completion
    end

    it "should get the guest powershell version" do
      allow(communicator).to receive(:shell).and_return(shell)
      expect(shell).to receive(:powershell).with("$PSVersionTable.PSVersion.Major").and_return({:data => [{:stdout => "4"}]})
      
      expect(subject.get_guest_powershell_version).to eq("4")
    end

    it "should get the lcm state" do
      allow(communicator).to receive(:shell).and_return(shell)
      expect(shell).to receive(:powershell).with("(Get-DscLocalConfigurationManager).LCMState").and_return({:data => [{:stdout => "LCMState"}]})
      
      expect(subject.get_lcm_state).to eq("LCMState")
    end

    it "should get the configuration status" do
      allow(communicator).to receive(:shell).and_return(shell)
      expect(shell).to receive(:powershell).with("(Get-DscConfigurationStatus).Status").and_return({:data => [{:stdout => "Status"}]})

      expect(subject.get_configuration_status).to eq("Status")
    end

    it "should get the dsc error message" do
      allow(communicator).to receive(:shell).and_return(shell)
      expect(shell).to receive(:powershell)
        .with("Get-WinEvent \"Microsoft-Windows-Dsc/Operational\" | Where-Object {$_.LevelDisplayName -eq \"Error\" -and $_.Message.StartsWith(\"Job $((Get-DscConfigurationStatus).JobId)\" )} | foreach { $_.Message }")
        .and_yield(:stdout, "\r\n")
        .and_yield(:stdout, "\r\n")
        .and_yield(:stdout, "Job AE9233FD-8491-11E6-9810-080027F3ADE1} : \r\n          MIResult: 1\r\n")
      expect(ui).to receive(:error).with("\r\n", :prefix=>false).twice
      expect(ui).to receive(:error).with("Job AE9233FD-8491-11E6-9810-080027F3ADE1} : \r\n          MIResult: 1\r\n", :prefix=>false)

      subject.show_dsc_failure_message
    end

    it "should verify DSC binary exists" do
      expect(communicator).to receive(:sudo).with("which Start-DscConfiguration", {:error_class=>VagrantPlugins::DSC::DSCError, :error_key=>:dsc_not_detected, :binary=>"Start-DscConfiguration"})
      subject.verify_binary("Start-DscConfiguration")
    end

    it "should verify DSC and Powershell versions are valid" do
      expect(communicator).to receive(:test).with("(($PSVersionTable | ConvertTo-json | ConvertFrom-Json).PSVersion.Major) -ge 4", {:error_class=>VagrantPlugins::DSC::DSCError, :error_key=>:dsc_incorrect_PowerShell_version}).and_return(true)
      allow(subject).to receive(:verify_binary).and_return(true)
      subject.verify_dsc
    end

    it "should raise an error if DSC version is invalid" do
      # shell = double("WinRMShell")
      # allow(communicator).to receive(:shell).and_return(shell)
      # allow(communicator).to receive(:create_shell).and_return(shell)

      # TODO: Create an actual Communicator object and mock out methods/calls to isolate this behaviour better
      expect(communicator).to receive(:test).with("(($PSVersionTable | ConvertTo-json | ConvertFrom-Json).PSVersion.Major) -ge 4", {:error_class=>VagrantPlugins::DSC::DSCError, :error_key=>:dsc_incorrect_PowerShell_version})
      allow(subject).to receive(:verify_binary).and_return(true)
      # expect { subject.verify_dsc }.to raise_error("Unable to detect a working DSC environment. Please ensure powershell v4+ is installed, including WMF 4+.")
      subject.verify_dsc
    end

    it "should raise an error if Powershell version is invalid" do

    end
  end

  describe "DSC runner script" do
    before do
      # Prevent counters messing with output in tests
      Vagrant::Util::Counter.class_eval do
        def get_and_update_counter(name=nil) 1 end
      end

      allow(machine).to receive(:root_config).and_return(root_config)
      root_config.configuration_file = configuration_file
      machine.stub(config: root_config, env: env)
      root_config.module_path = module_path
      root_config.configuration_file = configuration_file
      root_config.finalize!
      root_config.validate(machine)
      subject.configure(root_config)

    end

    context "with default parameters" do
      it "should generate a valid powershell command" do
        script = subject.generate_dsc_runner_script
        expect_script = "#
# DSC Runner.
#
# Bootstraps the DSC environment, sets up configuration data
# and runs the DSC Configuration.
#
#

# Set the local PowerShell Module environment path
$absoluteModulePaths = [string]::Join(\";\", (\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { $_ | Resolve-Path }))

echo \"Adding to path: $absoluteModulePaths\"
$env:PSModulePath=\"$absoluteModulePaths;${env:PSModulePath}\"
(\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { gci -Recurse  $_ | ForEach-Object { Unblock-File  $_.FullName} })


$script = $(Join-Path \"/tmp/vagrant-dsc-1\" \"manifests/MyWebsite.ps1\" -Resolve)
echo \"PSModulePath Configured: ${env:PSModulePath}\"
echo \"\"
echo \"Running Configuration file: ${script}\"

# Generate the MOF file, only if a MOF path not already provided.
# Import the Manifest
. $script

cd \"/tmp/vagrant-dsc-1\"
$StagingPath = $(Join-Path \"/tmp/vagrant-dsc-1\" \"staging\")
MyWebsite -OutputPath $StagingPath 

# Start a DSC Configuration run
Start-DscConfiguration -Force -Wait -Verbose -Path $StagingPath
del $StagingPath\\*.mof
"

        expect(script).to eq(expect_script)
      end
    end

    context "with a relative manifests_path" do
      it "should generate a valid powershell command" do
        root_config.manifests_path = "../manifests"
        root_config.configuration_file = configuration_file

        script = subject.generate_dsc_runner_script
        expect_script = "#
# DSC Runner.
#
# Bootstraps the DSC environment, sets up configuration data
# and runs the DSC Configuration.
#
#

# Set the local PowerShell Module environment path
$absoluteModulePaths = [string]::Join(\";\", (\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { $_ | Resolve-Path }))

echo \"Adding to path: $absoluteModulePaths\"
$env:PSModulePath=\"$absoluteModulePaths;${env:PSModulePath}\"
(\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { gci -Recurse  $_ | ForEach-Object { Unblock-File  $_.FullName} })


$script = $(Join-Path \"/tmp/vagrant-dsc-1\" \"../manifests/MyWebsite.ps1\" -Resolve)
echo \"PSModulePath Configured: ${env:PSModulePath}\"
echo \"\"
echo \"Running Configuration file: ${script}\"

# Generate the MOF file, only if a MOF path not already provided.
# Import the Manifest
. $script

cd \"/tmp/vagrant-dsc-1\"
$StagingPath = $(Join-Path \"/tmp/vagrant-dsc-1\" \"staging\")
MyWebsite -OutputPath $StagingPath 

# Start a DSC Configuration run
Start-DscConfiguration -Force -Wait -Verbose -Path $StagingPath
del $StagingPath\\*.mof
"

        expect(script).to eq(expect_script)
      end
    end

    context "with custom DSC Parameters" do
      it "should pass through arguments to the generated Powershell runner" do
        root_config.configuration_params = {"-Foo" => "bar", "-ComputerName" => "catz"}
        script = subject.generate_dsc_runner_script

        expect_script = "#
# DSC Runner.
#
# Bootstraps the DSC environment, sets up configuration data
# and runs the DSC Configuration.
#
#

# Set the local PowerShell Module environment path
$absoluteModulePaths = [string]::Join(\";\", (\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { $_ | Resolve-Path }))

echo \"Adding to path: $absoluteModulePaths\"
$env:PSModulePath=\"$absoluteModulePaths;${env:PSModulePath}\"
(\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { gci -Recurse  $_ | ForEach-Object { Unblock-File  $_.FullName} })


$script = $(Join-Path \"/tmp/vagrant-dsc-1\" \"manifests/MyWebsite.ps1\" -Resolve)
echo \"PSModulePath Configured: ${env:PSModulePath}\"
echo \"\"
echo \"Running Configuration file: ${script}\"

# Generate the MOF file, only if a MOF path not already provided.
# Import the Manifest
. $script

cd \"/tmp/vagrant-dsc-1\"
$StagingPath = $(Join-Path \"/tmp/vagrant-dsc-1\" \"staging\")
MyWebsite -OutputPath $StagingPath -Foo \"bar\" -ComputerName \"catz\"

# Start a DSC Configuration run
Start-DscConfiguration -Force -Wait -Verbose -Path $StagingPath
del $StagingPath\\*.mof
"

        expect(script).to eq(expect_script)
      end

      it "should allow flags as arguments to the generated Powershell runner" do
        root_config.configuration_params = {"-FooFlag" => nil, "-BarFlag" => nil, "-FooParam" => "FooVal"}
        script = subject.generate_dsc_runner_script

        expect_script = "#
# DSC Runner.
#
# Bootstraps the DSC environment, sets up configuration data
# and runs the DSC Configuration.
#
#

# Set the local PowerShell Module environment path
$absoluteModulePaths = [string]::Join(\";\", (\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { $_ | Resolve-Path }))

echo \"Adding to path: $absoluteModulePaths\"
$env:PSModulePath=\"$absoluteModulePaths;${env:PSModulePath}\"
(\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { gci -Recurse  $_ | ForEach-Object { Unblock-File  $_.FullName} })


$script = $(Join-Path \"/tmp/vagrant-dsc-1\" \"manifests/MyWebsite.ps1\" -Resolve)
echo \"PSModulePath Configured: ${env:PSModulePath}\"
echo \"\"
echo \"Running Configuration file: ${script}\"

# Generate the MOF file, only if a MOF path not already provided.
# Import the Manifest
. $script

cd \"/tmp/vagrant-dsc-1\"
$StagingPath = $(Join-Path \"/tmp/vagrant-dsc-1\" \"staging\")
MyWebsite -OutputPath $StagingPath -FooFlag -BarFlag -FooParam \"FooVal\"

# Start a DSC Configuration run
Start-DscConfiguration -Force -Wait -Verbose -Path $StagingPath
del $StagingPath\\*.mof
"

        expect(script).to eq(expect_script)
      end
    end

    context "with a MOF file specified" do
      it "should generate a script that does not generate a new MOF" do
        root_config.configuration_params = {}
        root_config.mof_path = "staging"
        script = subject.generate_dsc_runner_script

        expect_script = "#
# DSC Runner.
#
# Bootstraps the DSC environment, sets up configuration data
# and runs the DSC Configuration.
#
#

# Set the local PowerShell Module environment path
$absoluteModulePaths = [string]::Join(\";\", (\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { $_ | Resolve-Path }))

echo \"Adding to path: $absoluteModulePaths\"
$env:PSModulePath=\"$absoluteModulePaths;${env:PSModulePath}\"
(\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { gci -Recurse  $_ | ForEach-Object { Unblock-File  $_.FullName} })


$script = $(Join-Path \"/tmp/vagrant-dsc-1\" \"manifests/MyWebsite.ps1\" -Resolve)
echo \"PSModulePath Configured: ${env:PSModulePath}\"
echo \"\"
echo \"Running Configuration file: ${script}\"

# Generate the MOF file, only if a MOF path not already provided.
$StagingPath = \"staging\"

# Start a DSC Configuration run
Start-DscConfiguration -Force -Wait -Verbose -Path $StagingPath
del $StagingPath\\*.mof
"

        expect(script).to eq(expect_script)
      end
    end

    context "with -ConfigurationData" do
      before do
        # Prevent counters messing with output in tests
        Vagrant::Util::Counter.class_eval do
          def get_and_update_counter(name=nil) 1 end
        end

        allow(machine).to receive(:root_config).and_return(root_config)
        root_config.configuration_file = configuration_file
        root_config.configuration_data_file = configuration_data_file
        machine.stub(config: root_config, env: env)
        root_config.module_path = module_path
        root_config.configuration_file = configuration_file
        root_config.finalize!
        root_config.validate(machine)
        subject.configure(root_config)

      end

      it "should pass in the location of" do
        script = subject.generate_dsc_runner_script
        expect_script = "#
# DSC Runner.
#
# Bootstraps the DSC environment, sets up configuration data
# and runs the DSC Configuration.
#
#

# Set the local PowerShell Module environment path
$absoluteModulePaths = [string]::Join(\";\", (\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { $_ | Resolve-Path }))

echo \"Adding to path: $absoluteModulePaths\"
$env:PSModulePath=\"$absoluteModulePaths;${env:PSModulePath}\"
(\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { gci -Recurse  $_ | ForEach-Object { Unblock-File  $_.FullName} })


$script = $(Join-Path \"/tmp/vagrant-dsc-1\" \"manifests/MyWebsite.ps1\" -Resolve)
echo \"PSModulePath Configured: ${env:PSModulePath}\"
echo \"\"
echo \"Running Configuration file: ${script}\"

# Generate the MOF file, only if a MOF path not already provided.
# Import the Manifest
. $script

cd \"/tmp/vagrant-dsc-1\"
$StagingPath = $(Join-Path \"/tmp/vagrant-dsc-1\" \"staging\")
$Config = $(iex (Get-Content (Join-Path \"/tmp/vagrant-dsc-1\" \"manifests/MyConfig.psd1\" -Resolve) | Out-String))
MyWebsite -OutputPath $StagingPath  -ConfigurationData $Config

# Start a DSC Configuration run
Start-DscConfiguration -Force -Wait -Verbose -Path $StagingPath
del $StagingPath\\*.mof
"

        expect(script).to eq(expect_script)
      end
    end

    context "with module_install" do
      it "should generate a valid powershell command" do
        root_config.module_install = ["xNetworking", "xSQLServer"]

        script = subject.generate_dsc_runner_script
        expect_script = "#
# DSC Runner.
#
# Bootstraps the DSC environment, sets up configuration data
# and runs the DSC Configuration.
#
#

# Set the local PowerShell Module environment path
$absoluteModulePaths = [string]::Join(\";\", (\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { $_ | Resolve-Path }))

echo \"Adding to path: $absoluteModulePaths\"
$env:PSModulePath=\"$absoluteModulePaths;${env:PSModulePath}\"
(\"/tmp/vagrant-dsc-1/modules-0;/tmp/vagrant-dsc-1/modules-1\".Split(\";\") | ForEach-Object { gci -Recurse  $_ | ForEach-Object { Unblock-File  $_.FullName} })

Write-Host \"Ensure Modules\"
Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue -ErrorVariable NuGetError | Out-Null
if ($NuGetError) {
    Write-Host \"Install Package Provider Nuget\"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne \"Trusted\") {
    Set-PSRepository -Name PSGallery -InstallationPolicy \"Trusted\"
}
# Install-Modules only installs if the module is not installed
\"xNetworking;xSQLServer\".Split(\";\") | foreach { Install-Module $_ }

$script = $(Join-Path \"/tmp/vagrant-dsc-1\" \"manifests/MyWebsite.ps1\" -Resolve)
echo \"PSModulePath Configured: ${env:PSModulePath}\"
echo \"\"
echo \"Running Configuration file: ${script}\"

# Generate the MOF file, only if a MOF path not already provided.
# Import the Manifest
. $script

cd \"/tmp/vagrant-dsc-1\"
$StagingPath = $(Join-Path \"/tmp/vagrant-dsc-1\" \"staging\")
MyWebsite -OutputPath $StagingPath 

# Start a DSC Configuration run
Start-DscConfiguration -Force -Wait -Verbose -Path $StagingPath
del $StagingPath\\*.mof
"

        expect(script).to eq(expect_script)
      end
    end

  end

  describe "write DSC Runner script" do
    it "should upload the customised DSC runner to the guest" do
      script = "myscript"
      path = "/local/runner/path"
      guest_path = "c:/tmp/vagrant-dsc-runner.ps1"
      machine.stub(config: root_config, env: env, communicate: communicator)
      file = double("file")
      allow(file).to receive(:path).and_return(path)
      allow(Tempfile).to receive(:new) { file }
      expect(file).to receive(:write).with(script)
      expect(file).to receive(:fsync)
      expect(file).to receive(:close).exactly(2).times
      expect(file).to receive(:unlink)
      expect(communicator).to receive(:upload).with(path, guest_path)
      res = subject.write_dsc_runner_script(script)
      expect(res.to_s).to eq(guest_path)
    end
  end

  describe "Apply DSC" do
    it "should invoke the DSC Runner and notify the User of provisioning status" do
      allow(communicator).to receive(:shell).and_return(shell)
      allow(machine).to receive(:communicate).and_return(communicator)
      expect(shell).to receive(:powershell).with("powershell -ExecutionPolicy Bypass -OutputFormat Text -file c:/tmp/vagrant-dsc-runner.ps1").and_yield(:stdout, "provisioned!")
      root_config.configuration_file = configuration_file
      expect(ui).to receive(:info).with("\"Running DSC Provisioner with manifests/MyWebsite.ps1...\"")
      expect(ui).to receive(:info).with("provisioned!", {color: :green, new_line: false, prefix: false}).once

      subject.run_dsc_apply
    end

    it "should show error output in red" do
      allow(machine).to receive(:communicate).and_return(communicator)
      allow(communicator).to receive(:shell).and_return(shell)

      root_config.configuration_file = configuration_file
      expect(ui).to receive(:info).with("\"Running DSC Provisioner with manifests/MyWebsite.ps1...\"")
      expect(ui).to receive(:info).with("not provisioned!", {color: :red, new_line: false, prefix: false}).once
      expect(shell).to receive(:powershell).with("powershell -ExecutionPolicy Bypass -OutputFormat Text -file c:/tmp/vagrant-dsc-runner.ps1").and_yield(:stderr, "not provisioned!")

      subject.run_dsc_apply
    end
  end
end

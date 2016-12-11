require "log4r"
require 'erb'

module VagrantPlugins
  module DSC
    # DSC Errors namespace, including setup of locale-based error messages.
    class DSCError < Vagrant::Errors::VagrantError
      error_namespace("vagrant_dsc.errors")
      I18n.load_path << File.expand_path("locales/en.yml", File.dirname(__FILE__))
    end
    class DSCUnsupportedOperation < DSCError
      error_key(:unsupported_operation)
    end

    # DSC Provisioner Plugin.
    #
    # Runs the [Desired State Configuration](http://technet.microsoft.com/en-au/library/dn249912.aspx) system
    # on a guest Virtual Machine, enabling you to quickly configure & bootstrap a Windows Virtual Machine in a repeatable,
    # reliable fashion - the Vagrant way.
    class Provisioner < Vagrant.plugin("2", :provisioner)
      PowerShell_VERSION = 4

      # Default path for storing the transient script runner
      # This should be removed in cleanup
      DSC_GUEST_RUNNER_PATH = "c:/tmp/vagrant-dsc-runner.ps1"

      # Constructs the Provisioner Plugin.
      #
      # @param [Machine] machine The guest machine that is to be provisioned.
      # @param [Config] config The Configuration object used by the Provisioner.
      # @returns Provisioner
      def initialize(machine, config)
        super

        @logger = Log4r::Logger.new("vagrant::provisioners::dsc")
      end

      # Configures the Provisioner.
      #
      # @param [Config] root_config The default configuration from the Vagrant hierarchy.
      def configure(root_config)
        @logger.info("==> Configuring DSC")

        # Calculate the paths we're going to use based on the environment
        root_path = @machine.env.root_path
        @expanded_module_paths   = @config.expanded_module_paths(root_path)

        # Setup the module paths
        @module_paths = []
        @expanded_module_paths.each_with_index do |path, i|
          @module_paths << [path, File.join(config.temp_dir, "modules-#{i}")]
        end

        folder_opts = {}
        folder_opts[:type] = @config.synced_folder_type if @config.synced_folder_type
        folder_opts[:owner] = "root" if !@config.synced_folder_type

        # Share the manifests directory with the guest
        @logger.info("==> Sharing manifest #{File.expand_path(@config.manifests_path, root_path)} | #{manifests_guest_path} | #{folder_opts}")

        root_config.vm.synced_folder(
          File.expand_path(@config.manifests_path, root_path),
          manifests_guest_path, folder_opts)

        # Share the module paths
        @module_paths.each do |from, to|
          @logger.info("==> Sharing module folders #{from} | #{to}")
          root_config.vm.synced_folder(from, to, folder_opts)
        end
      end

      # Provision the guest machine with DSC.
      def provision
        @logger.info("==> Provisioning DSC man! #{Vagrant.source_root}")

        # If the machine has a wait for reboot functionality, then
        # do that (primarily Windows)
        if @machine.guest.capability?(:wait_for_reboot)
          @machine.guest.capability(:wait_for_reboot)
        end

        # Check that the shared folders are properly shared
        check = []
        check << manifests_guest_path
        @module_paths.each do |host_path, guest_path|
          check << guest_path
        end

        # Make sure the temporary directory is properly set up
        @machine.communicate.tap do |comm|
          comm.sudo("mkdir -p #{config.temp_dir}")
          comm.sudo("chmod 0777 #{config.temp_dir}")
        end

        verify_shared_folders(check)

        verify_dsc

        write_dsc_runner_script(generate_dsc_runner_script)

        begin
          run_dsc_apply
        rescue VagrantPlugins::CommunicatorWinRM::Errors::AuthenticationFailed
          # when install set a domain controller windows kills the active connection with a AuthenticationFailed.
          # The DSC job is still running and new connections are possible, so try to wait 
          @machine.ui.info(I18n.t("vagrant_dsc.errors.winrm_authorization_error_recover"))
        end
        
        wait_for_dsc_completion
      end

      # Waits for the completion of the dsc configuration if dsc needs reboots. This currntly only works for WMF5 and needs wait_for_reboot
      def wait_for_dsc_completion
        powershell_version = get_guest_powershell_version
        return if powershell_version.to_i < 5 || !@machine.guest.capability?(:wait_for_reboot)
        dsc_running = true

        while dsc_running
          case get_lcm_state
            when "PendingReboot"
              @machine.ui.info("DSC needs reboot. Wait for the completion of DSC.")
              @machine.guest.capability(:wait_for_reboot)

            # Do not Know a way to reattch to dsc job, therefore check periodically the state
            when "Busy"
              sleep 10
            else
              dsc_running = false
          end
        end

        if (get_configuration_status == "Failure")
          @machine.ui.error(I18n.t("failure_status"))
          show_dsc_failure_message
          fail_vagrant_run_if_requested
        end
      end

      def get_guest_powershell_version
        version = @machine.communicate.shell.powershell("$PSVersionTable.PSVersion.Major")
        return version[:data][0][:stdout]
      end

      def get_lcm_state
        state = @machine.communicate.shell.powershell("(Get-DscLocalConfigurationManager).LCMState")
        return state[:data][0][:stdout]
      end

      def get_configuration_status
        status = @machine.communicate.shell.powershell("(Get-DscConfigurationStatus).Status")
        return status[:data][0][:stdout]
      end

      def show_dsc_failure_message
        dsc_error_ps = "Get-WinEvent \"Microsoft-Windows-Dsc/Operational\" | Where-Object {$_.LevelDisplayName -eq \"Error\" -and $_.Message.StartsWith(\"Job $((Get-DscConfigurationStatus).JobId)\" )} | foreach { $_.Message }"
        @machine.communicate.shell.powershell(dsc_error_ps) do |type,data|
          @machine.ui.error(data, prefix: false)
        end
      end

      def fail_vagrant_run_if_requested
        if (@config.abort_vagrant_run_if_dsc_fails)
          raise DSCError, :dsc_configuration_failed
        else
          @machine.ui.info("DSC execution failed. Set 'abort_vagrant_run_if_dsc_fails' to true to make this fail the build.")
        end
      end

      # Cleanup after a destroy action.
      #
      # This is the method called when destroying a machine that allows
      # for any state related to the machine created by the provisioner
      # to be cleaned up.
      def cleanup
        # Remove temp files? Or is this ONLY called in destroy (in which case those files will go anyway...)
      end

      # Local path (guest path) to the manifests directory.
      def manifests_guest_path
          File.join(config.temp_dir, config.manifests_path)
      end

      # Verify that a current version of WMF/Powershell is enabled on the guest.
      def verify_dsc
        verify_binary("Start-DscConfiguration")

        # Confirm WMF 4.0+ in $PSVersionTable
        @machine.communicate.test(
            "(($PSVersionTable | ConvertTo-json | ConvertFrom-Json).PSVersion.Major) -ge #{PowerShell_VERSION}",
            error_class: DSCError,
            error_key: :dsc_incorrect_PowerShell_version )
      end

      # Verify the DSC binary is executable on the guest machine.
      def verify_binary(binary)
        @machine.communicate.sudo(
          "which #{binary}",
          error_class: DSCError,
          error_key: :dsc_not_detected,
          binary: binary)
      end

      # Install and Configure DSC where possible.
      #
      # Operation is current unsupported, but is likely to be enabled
      # as a flag when the plugin detects an unsupported OS.
      def install_dsc
        raise DSCUnsupportedOperation,  :operation => "install_dsc"
      end

      # Generates a PowerShell DSC runner script from an ERB template
      #
      # @return [String] The interpolated PowerShell script.
      def generate_dsc_runner_script
        path = File.expand_path("../templates/runner.ps1", __FILE__)

        script = Vagrant::Util::TemplateRenderer.render(path, options: {
            config: @config,
            module_paths: @module_paths.map { |k,v| v }.join(";"),
            mof_path: @config.mof_path,
            configuration_file: @config.configuration_file,
            configuration_file_path: "#{@config.manifests_path}/#{File.basename @config.configuration_file}",
            configuration_data_file_path: @config.configuration_data_file,
            configuration_name: @config.configuration_name,
            manifests_path: @config.manifests_path,
            temp_path: @config.temp_dir,
            module_install: @config.module_install.nil? ? "" : @config.module_install.join(";"),
            parameters: @config.configuration_params.map { |k,v| "#{k}" + (!v.nil? ? " \"#{v}\"": '') }.join(" ")
        })
      end

      # Writes the PowerShell DSC runner script to a location on the guest.
      #
      # @param [String] script The PowerShell DSC runner script.
      # @return [String] the Path to the uploaded location on the guest machine.
      def write_dsc_runner_script(script)
        guest_script_path = DSC_GUEST_RUNNER_PATH
        file = Tempfile.new(["vagrant-dsc-runner", "ps1"])
        begin
          file.write(script)
          file.fsync
          file.close
          @machine.communicate.upload(file.path, guest_script_path)
        ensure
          file.close
          file.unlink
        end
        guest_script_path
      end

      # Runs the DSC Configuration on the guest machine.
      def run_dsc_apply

        @machine.ui.info(I18n.t(
          "vagrant_dsc.running_dsc",
          manifest: config.configuration_file))

        # A bit of an ugly dance, but this is how we get neat, colourised output and exit codes from a Powershell run
        error = false
        machine.communicate.shell.powershell("powershell -ExecutionPolicy Bypass -OutputFormat Text -file #{DSC_GUEST_RUNNER_PATH}") do |type, data|
          if !data.chomp.empty?
            error = true if type == :stderr
            if [:stderr, :stdout].include?(type)
              color = type == :stdout ? :green : :red
              # Remove the \r\n since the dsc output uses this if line is to long. A Line break is a simple \n
              data = data.gsub(/\r\n/,"") if type == :stdout
              @machine.ui.info( data.strip(), color: color, prefix: false)
            end
          end
        end

        error == false
      end

      # Verify that the shared folders have been properly configured
      # on the guest machine.
      def verify_shared_folders(folders)
        folders.each do |folder|
          # Warm up PoSH communicator for new instances - any stderr results
          # in failure: https://github.com/mefellows/vagrant-dsc/issues/21
          @machine.communicate.test("test -d #{folder}", sudo: true)

          @logger.info("Checking for shared folder: #{folder}")
          if !@machine.communicate.test("test -d #{folder}", sudo: true)
            raise DSCError, :missing_shared_folders
          end
        end
      end

      # If on using WinRM, we can assume we are on Windows
      def windows?
        @machine.config.vm.communicator == :winrm
      end
    end
  end
end

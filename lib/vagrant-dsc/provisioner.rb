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

        run_dsc_apply(generate_dsc_runner_script)
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
        # raise DSCError, I18n.t("vagrant_dsc.errors.manifest_missing", operation: "install_dsc")
        raise DSCUnsupportedOperation,  :operation => "install_dsc"
        # Install chocolatey

        # Ensure .NET 4.5 installed

        # Ensure WMF 4.0 is installed
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
            configuration_name: @config.configuration_name,
            temp_path: @config.temp_dir,
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

      # Runs the DSC Configuration over the guest machine.
      #
      # Expects
      def run_dsc_apply

        # Check the DSC_GUEST_RUNNER_PATH exists?

        # Set up Configuration arguments (hostname, manifest/module location, error levels ...)

          # Where are the modules?

          # Where is the manifest

        # TODO: Get a counter in here in case of multiple runs

        # Import starting point configuration into scope

        command = ".\\'#{DSC_GUEST_RUNNER_PATH}'"

        @machine.ui.info(I18n.t(
          "vagrant_dsc.running_dsc",
          manifest: config.configuration_file))

        opts = {
          elevated: true,
          error_key: :ssh_bad_exit_status_muted,
          good_exit: [0,2],
        }

        @machine.communicate.sudo(command, opts) do |type, data|
          if !data.chomp.empty?
            @machine.ui.info(data.chomp)
          end
        end
      end

      # Verify that the shared folders have been properly configured
      # on the guest machine.
      def verify_shared_folders(folders)
        folders.each do |folder|
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

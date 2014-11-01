require "vagrant/util/counter"
require "log4r"

module VagrantPlugins
  module DSC
    # The "Configuration" represents a configuration of how the DSC
    # provisioner should behave: data directories, working directory,
    # DSC Manifests etc.
    class Config < Vagrant.plugin("2", :config)
      extend Vagrant::Util::Counter

      # Set of Parameters to pass to the DSC Configuration.
      #
      # @return [Hash] Set of k/v parameters to pass to DSC.
      attr_accessor :configuration_params

      # Relative path to a folder, containing the pre-generated MOF file.
      #
      # Path is relative to the folder containing the Vagrantfile.
      attr_accessor :mof_path

      # Relative path to the DSC Configuration file.
      #
      # Path is relative to the folder containing the Vagrantfile.
      attr_accessor :configuration_file

      # Relative path to the folder containing the root Configuration manifest file.
      # Defaults to 'manifests'.
      #
      # Path is relative to the folder containing the Vagrantfile.
      attr_accessor :manifests_path

      # The name of the Configuration module
      #
      # Defaults to the basename of the "configuration_file"
      # e.g. "Foo.ps1" becomes "Foo"
      attr_accessor :configuration_name

      # Set of module paths relative to the Vagrantfile dir.
      #
      # These paths are added to the DSC Configuration running
      # environment to enable local modules to be addressed.
      #
      # @return [Array] Set of relative module paths.
      attr_accessor :module_path

      # The type of synced folders to use when sharing the data
      # required for the provisioner to work properly.
      #
      # By default this will use the default synced folder type.
      # For example, you can set this to "nfs" to use NFS synced folders.
      attr_accessor :synced_folder_type

      # Temporary working directory on the guest machine.
      attr_accessor :temp_dir

      # Fully qualified path to the configuration file.
      #
      # Do not override this.
      attr_accessor :expanded_configuration_file

      def initialize
        super

        @configuration_file     = UNSET_VALUE
        @manifests_path         = UNSET_VALUE
        @configuration_name     = UNSET_VALUE
        @mof_path               = UNSET_VALUE
        @module_path            = UNSET_VALUE
        @configuration_params   = {}
        @synced_folder_type     = UNSET_VALUE
        @temp_dir               = UNSET_VALUE
        @logger = Log4r::Logger.new("vagrant::vagrant_dsc")
      end

      # Final step of the Configuration lifecyle prior to
      # validation.
      #
      # Ensures all attributes are set to defaults if not provided.
      def finalize!
        super

        # Null checks
        @configuration_file = "default.ps1" if @configuration_file == UNSET_VALUE
        @module_path        = nil if @module_path == UNSET_VALUE
        @synced_folder_type = nil if @synced_folder_type == UNSET_VALUE
        @temp_dir           = nil if @temp_dir == UNSET_VALUE
        @mof_path           = nil if @mof_path == UNSET_VALUE
        @configuration_name = File.basename(@configuration_file, File.extname(@configuration_file)) if @configuration_name == UNSET_VALUE
        @manifests_path     = File.dirname(@configuration_file) if @manifests_path == UNSET_VALUE

        # Can't supply them both!
        if (@configuration_file != nil && @mof_path != nil)
          raise DSCError, :manifest_and_mof_provided
        end

        # Set a default temp dir that has an increasing counter so
        # that multiple DSC definitions won't overwrite each other
        if !@temp_dir
          counter   = self.class.get_and_update_counter(:dsc_config)
          @temp_dir = "/tmp/vagrant-dsc-#{counter}"
        end
      end

      # Returns the module paths as an array of paths expanded relative to the
      # root path.
      #
      # @param [String|Array] root_path The relative path to expand module paths against.
      # @return [Array] Set of fully qualified paths to the modules directories.
      def expanded_module_paths(root_path)
        return [] if !module_path

        # Get all the paths and expand them relative to the root path, returning
        # the array of expanded paths
        paths = module_path
        paths = [paths] if !paths.is_a?(Array)
        paths.map do |path|
          Pathname.new(path).expand_path(root_path).to_s
        end
      end

      # Validate configuration and return a hash of errors.
      #
      # Does not check that DSC itself is properly configured, which is performed
      # at run-time.
      #
      # @param [Machine] The current {Machine}
      # @return [Hash] Any errors or {} if no errors found
      def validate(machine)
        @logger.info("==> Configurin' DSC man!")
        errors = _detected_errors

        # Calculate the manifests and module paths based on env
        this_expanded_module_paths = expanded_module_paths(machine.env.root_path)

        # Manifest file validation
        this_expanded_module_paths.each do |path|
          errors << I18n.t("vagrant_dsc.errors.module_path_missing", path: path) if !Pathname.new(path).expand_path(machine.env.root_path).directory?
        end

        expanded_path = Pathname.new(manifests_path).
            expand_path(machine.env.root_path)

        if !expanded_path.directory?
          errors << I18n.t("vagrant_dsc.errors.manifests_path_missing",
                           path: expanded_path.to_s)
        end

        @expanded_configuration_file = expanded_path.join(File.basename(configuration_file))
        if !expanded_configuration_file.file? && !expanded_configuration_file.directory?
          errors << I18n.t("vagrant_dsc.errors.manifest_missing",
                           manifest: expanded_configuration_file.to_s)
        end

        { "dsc provisioner" => errors }
      end
    end
  end
end

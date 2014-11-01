require "vagrant"

module VagrantPlugins
  module DSC
    class Plugin < Vagrant.plugin("2")
      name "DSC"
      description <<-DESC
        Provides support for provisioning your virtual machines with
        DSC either using a local `DSC` Configuration or a DSC server.
      DESC

      config(:dsc, :provisioner) do
        require_relative 'config'
        Config
      end

      provisioner(:dsc) do
        require_relative 'provisioner'
        Provisioner
      end
    end
  end
end
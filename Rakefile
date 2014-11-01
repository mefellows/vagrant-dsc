require "bundler/gem_tasks"
require 'rspec/core/rake_task'
task :default => [:test, :quality]
# Remove 'install' task as the gem is installed to Vagrant, not to system
Rake::Task[:install].clear
namespace :test do
  RSpec::Core::RakeTask.new('unit') do |task|
    task.pattern = 'spec/**/*_spec.rb'
  end
end
desc "Run all tests"
task :test => ['test:unit']
task :spec => :test
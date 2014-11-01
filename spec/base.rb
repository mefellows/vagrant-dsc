shared_context "unit" do
  before(:each) do
    # State to store the list of registered plugins that we have to
    # unregister later.
    @_plugins = []

    # Create a thing to store our temporary files so that they aren't
    # unlinked right away.
    @_temp_files = []
  end

  # This helper creates a temporary file and returns a Pathname
  # object pointed to it.
  #
  # @return [Pathname]
  def temporary_file(contents=nil)
    f = Tempfile.new("vagrant-unit")

    if contents
      f.write(contents)
      f.flush
    end

    # Store the tempfile in an instance variable so that it is not
    # garbage collected, so that the tempfile is not unlinked.
    @_temp_files << f

    return Pathname.new(f.path)
  end

  # Asserts that the current (config) validation run should fail.
  # Any error message is sufficient.
  def assert_invalid
    errors = subject.validate(machine)
    if !errors.values.any? { |v| !v.empty? }
      raise "No errors: #{errors.inspect}"
    end
  end

  # Asserts that the current (config) validation should fail with a specific message.
  def assert_error(error)
    errors = subject.validate(machine)
    raise "Error #{error} was not raised" if !errors["dsc provisioner"].include? error
  end

  # Asserts that no failures should occur in the current (config) validation run.
  def assert_valid
    errors = subject.validate(machine)
    if !errors.values.all? { |v| v.empty? }
      raise "Errors: #{errors.inspect}"
    end
  end

end
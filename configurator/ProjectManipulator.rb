require 'xcodeproj'

module Pod

  class ProjectManipulator
    attr_reader :configurator, :xcodeproj_path, :platform, :remove_demo_target, :string_replacements, :prefix

    def self.perform(options)
      new(options).perform
    end

    def initialize(options)
      @xcodeproj_path = options.fetch(:xcodeproj_path)
      @configurator = options.fetch(:configurator)
      @platform = options.fetch(:platform)
      @remove_demo_target = options.fetch(:remove_demo_project)
      @prefix = options.fetch(:prefix)
    end

    def run
      @string_replacements = {
        "PROJECT_OWNER" => @configurator.user_name,
        "TODAYS_DATE" => @configurator.date,
        "TODAYS_YEAR" => @configurator.year,
        "PROJECT" => @configurator.pod_name,
        "CPD" => @prefix
      }
      replace_internal_project_settings

      @project = Xcodeproj::Project.open(@xcodeproj_path)
      remove_demo_project if @remove_demo_target
      @project.save

      rename_files
      rename_project_folder
    end

    def remove_demo_project
      app_project = @project.targets.select { |target| target.product_type == "com.apple.product-type.application" }.first
      test_target = @project.targets.select { |target| target.product_type == "com.apple.product-type.bundle.unit-test" }.first
      test_target.name = @configurator.pod_name + "_Tests"

      # Remove the implicit dependency on the app
      test_dependency = test_target.dependencies.first
      test_dependency.remove_from_project
      app_project.remove_from_project

      # Remove the build target on the unit tests
      test_target.build_configuration_list.build_configurations.each do |build_config|
        build_config.build_settings.delete "BUNDLE_LOADER"
      end

      # Remove the references in xcode
      project_app_group = @project.root_object.main_group.children.select { |group| group.display_name == @configurator.pod_name + ".xcodeproj" }.first
      project_app_group.remove_from_project

      # Remove the product reference
      product = @project.products.select { |product| product.path == "iOS Example.app" }.first

      product.remove_from_project

      # Remove the actual folder + files for all projects
      `rm -rf templates/ios/Example`
      `rm -rf templates/swift/Example`
      `rm -rf templates/swift/PROJECT.xcworkspace`
      `rm -rf templates/objective-c/Example`
      `rm -rf templates/objective-c/PROJECT.xcworkspace`

      if @configurator.pods_for_podfile.length
        # Replace the Podfile with a simpler one with only one target
        podfile_path = "staging/Podfile"
        podfile_text = <<-RUBY
use_frameworks!
target '#{configurator.pod_name}' do
  ${INCLUDED_PODS}
end

RUBY
        File.open(podfile_path, "w") { |file| file.puts podfile_text }
      end
    end

    def project_folder
      File.dirname @xcodeproj_path
    end

    def rename_files
      unless @remove_demo_target
        # change app file prefixes
        ["CPDAppDelegate.h", "CPDAppDelegate.m", "CPDViewController.h", "CPDViewController.m"].each do |file|
          before = project_folder + "/PROJECT/" + file
          next unless File.exist? before

          after = project_folder + "/PROJECT/" + file.gsub("CPD", prefix)
          File.rename before, after
        end

        # rename project related files
        ["PROJECT-Info.plist", "PROJECT-Prefix.pch"].each do |file|
          before = project_folder + "/PROJECT/" + file
          next unless File.exist? before

          after = project_folder + "/PROJECT/" + file.gsub("PROJECT", @configurator.pod_name)
          File.rename before, after
        end
      end

    end

    def rename_project_folder
      if Dir.exist? project_folder + "/PROJECT"
        File.rename(project_folder + "/PROJECT", project_folder + "/" + @configurator.pod_name)
      end
    end

    def replace_internal_project_settings
      Dir.glob(project_folder + "/**/**/**/**").each do |name|
        next if Dir.exist? name
        next if name.end_with? "png"

        text = File.read(name)
        for find, replace in @string_replacements
          text = text.gsub(find, replace)
        end

        File.open(name, "w") { |file| file.puts text }
      end
    end

  end

end

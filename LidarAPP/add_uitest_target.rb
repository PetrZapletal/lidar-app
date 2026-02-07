#!/usr/bin/env ruby
# Script to add XCUITest target to LidarAPP Xcode project
# Run: ruby add_uitest_target.rb

require 'xcodeproj'

# Configuration
PROJECT_PATH = 'LidarAPP.xcodeproj'
TARGET_NAME = 'LidarAPPUITests'
BUNDLE_ID = 'com.lidarscanner.app.uitests'
DEVELOPMENT_TEAM = '65HGP9PL6X'
HOST_TARGET_NAME = 'LidarAPP'

# Open project
project = Xcodeproj::Project.open(PROJECT_PATH)

# Check if target already exists
if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "Target '#{TARGET_NAME}' already exists. Updating..."
  ui_test_target = project.targets.find { |t| t.name == TARGET_NAME }
else
  puts "Creating new target '#{TARGET_NAME}'..."

  # Find host target
  host_target = project.targets.find { |t| t.name == HOST_TARGET_NAME }
  unless host_target
    puts "Error: Host target '#{HOST_TARGET_NAME}' not found!"
    exit 1
  end

  # Create UI Testing target
  ui_test_target = project.new_target(:ui_test_bundle, TARGET_NAME, :ios, '17.0')

  # Set the host application
  ui_test_target.add_dependency(host_target)
end

# Create or find the group for UI tests
ui_tests_group = project.main_group.find_subpath(TARGET_NAME, true)
ui_tests_group.set_source_tree('<group>')
ui_tests_group.set_path(TARGET_NAME)

# Define source files
source_files = [
  # Utilities
  'Utilities/AccessibilityIdentifiers.swift',
  'Utilities/XCTestExtensions.swift',
  'Utilities/BaseUITestCase.swift',
  # Pages
  'Pages/BasePage.swift',
  'Pages/TabBarPage.swift',
  'Pages/GalleryPage.swift',
  'Pages/ProfilePage.swift',
  'Pages/ScanModeSelectorPage.swift',
  'Pages/ScanningPage.swift',
  'Pages/ModelDetailPage.swift',
  'Pages/SettingsPage.swift',
  'Pages/AuthPage.swift',
  'Pages/ExportPage.swift',
  # Test Cases
  'TestCases/AppLaunchTests.swift',
  'TestCases/NavigationTests.swift',
  'TestCases/GalleryTests.swift',
  'TestCases/ProfileTests.swift',
  'TestCases/SettingsTests.swift',
  'TestCases/ScanningModeTests.swift',
  'TestCases/AuthenticationTests.swift',
]

# Add source files to target
source_files.each do |file_path|
  full_path = "#{TARGET_NAME}/#{file_path}"

  # Create subgroups as needed
  components = file_path.split('/')
  current_group = ui_tests_group

  if components.length > 1
    subgroup_name = components[0]
    subgroup = current_group.find_subpath(subgroup_name, true)
    subgroup.set_source_tree('<group>')
    current_group = subgroup
  end

  file_name = components.last

  # Check if file reference already exists
  existing_ref = current_group.files.find { |f| f.path == file_name }

  unless existing_ref
    if File.exist?(full_path)
      file_ref = current_group.new_file(file_name)
      ui_test_target.source_build_phase.add_file_reference(file_ref)
      puts "  Added: #{file_path}"
    else
      puts "  Warning: File not found: #{full_path}"
    end
  else
    puts "  Exists: #{file_path}"
  end
end

# Add Info.plist
info_plist_path = "#{TARGET_NAME}/Info.plist"
if File.exist?(info_plist_path)
  info_plist_ref = ui_tests_group.files.find { |f| f.path == 'Info.plist' }
  unless info_plist_ref
    info_plist_ref = ui_tests_group.new_file('Info.plist')
    puts "  Added: Info.plist"
  end
end

# Configure build settings
ui_test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  config.build_settings['DEVELOPMENT_TEAM'] = DEVELOPMENT_TEAM
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['INFOPLIST_FILE'] = "#{TARGET_NAME}/Info.plist"
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['TEST_TARGET_NAME'] = HOST_TARGET_NAME
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@loader_path/Frameworks'
  ]
end

# Add target to scheme if needed
scheme_path = "#{PROJECT_PATH}/xcshareddata/xcschemes/#{HOST_TARGET_NAME}.xcscheme"
if File.exist?(scheme_path)
  puts "Scheme exists, you may need to manually add UI test target to scheme"
end

# Save project
project.save

puts ""
puts "Successfully configured UI Test target!"
puts ""
puts "Next steps:"
puts "1. Open Xcode and verify the #{TARGET_NAME} target"
puts "2. Add UI test target to the LidarAPP scheme (Product > Scheme > Edit Scheme > Test)"
puts "3. Run tests: xcodebuild test -scheme LidarAPP -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:#{TARGET_NAME}"

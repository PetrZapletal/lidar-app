#!/usr/bin/env ruby
# Script to add test target to Xcode project

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Check if test target already exists
existing_target = project.targets.find { |t| t.name == 'LidarAPPTests' }
if existing_target
  puts "Test target 'LidarAPPTests' already exists"
  exit 0
end

# Find main target
main_target = project.targets.find { |t| t.name == 'LidarAPP' }
unless main_target
  puts "Error: Could not find main target 'LidarAPP'"
  exit 1
end

# Create test target
test_target = project.new_target(:unit_test_bundle, 'LidarAPPTests', :ios, '17.0')

# Add test host dependency
test_target.add_dependency(main_target)

# Configure build settings
test_target.build_configurations.each do |config|
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/LidarAPP.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LidarAPP'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.lidarscanner.app.tests'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['INFOPLIST_FILE'] = 'LidarAPPTests/Info.plist'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
end

# Create test group
test_group = project.main_group.find_subpath('LidarAPPTests', true)
test_group.set_source_tree('<group>')
test_group.set_path('LidarAPPTests')

# Add test files to target
test_files = Dir.glob('LidarAPPTests/*.swift')
test_files.each do |file_path|
  file_name = File.basename(file_path)
  file_ref = test_group.new_file(file_name)
  test_target.add_file_references([file_ref])
end

# Create Info.plist for tests
info_plist_content = <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
PLIST

File.write('LidarAPPTests/Info.plist', info_plist_content)

# Add scheme for testing
project.save

puts "Successfully added test target 'LidarAPPTests'"
puts "Test files added:"
test_files.each { |f| puts "  - #{f}" }

#!/usr/bin/env ruby
# Fix test target configuration

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find test target
test_target = project.targets.find { |t| t.name == 'LidarAPPTests' }
unless test_target
  puts "Error: Test target not found"
  exit 1
end

# Fix build settings
test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'LidarAPPTests'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.lidarscanner.app.tests'
  config.build_settings['INFOPLIST_FILE'] = 'LidarAPPTests/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'

  # Test host settings
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/LidarAPP.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LidarAPP'
  config.build_settings['TEST_TARGET_NAME'] = 'LidarAPP'
end

project.save
puts "Test target configuration fixed"

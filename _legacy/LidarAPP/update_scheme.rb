#!/usr/bin/env ruby
# Add test target to scheme

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find scheme
scheme_path = "#{project_path}/xcshareddata/xcschemes/LidarAPP.xcscheme"

unless File.exist?(scheme_path)
  puts "Creating scheme directory..."
  FileUtils.mkdir_p("#{project_path}/xcshareddata/xcschemes")
end

# Find targets
main_target = project.targets.find { |t| t.name == 'LidarAPP' }
test_target = project.targets.find { |t| t.name == 'LidarAPPTests' }

unless main_target && test_target
  puts "Targets not found"
  exit 1
end

# Create or update scheme
scheme = Xcodeproj::XCScheme.new

# Build action
scheme.build_action = Xcodeproj::XCScheme::BuildAction.new
build_entry = Xcodeproj::XCScheme::BuildAction::Entry.new(main_target)
build_entry.build_for_testing = true
build_entry.build_for_running = true
build_entry.build_for_profiling = true
build_entry.build_for_archiving = true
build_entry.build_for_analyzing = true
scheme.build_action.add_entry(build_entry)

# Test action
scheme.test_action = Xcodeproj::XCScheme::TestAction.new
scheme.test_action.build_configuration = 'Debug'
testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
testable.skipped = false
scheme.test_action.add_testable(testable)

# Launch action
scheme.launch_action = Xcodeproj::XCScheme::LaunchAction.new
scheme.launch_action.build_configuration = 'Debug'
scheme.launch_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(main_target)

# Profile action
scheme.profile_action = Xcodeproj::XCScheme::ProfileAction.new
scheme.profile_action.build_configuration = 'Release'
scheme.profile_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(main_target)

# Analyze action
scheme.analyze_action = Xcodeproj::XCScheme::AnalyzeAction.new
scheme.analyze_action.build_configuration = 'Debug'

# Archive action
scheme.archive_action = Xcodeproj::XCScheme::ArchiveAction.new
scheme.archive_action.build_configuration = 'Release'
scheme.archive_action.reveal_archive_in_organizer = true

# Save scheme
scheme.save_as(project_path, 'LidarAPP')

puts "Scheme updated successfully with test target"

#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'LidarAPP' }

main_group = project.main_group.find_subpath('LidarAPP', true)
services_group = main_group.find_subpath('Services', true)

# Create Diagnostics group if it doesn't exist
existing_diag = services_group.children.find { |c| c.display_name == 'Diagnostics' }
existing_diag&.remove_from_project

diag_group = services_group.new_group('Diagnostics', 'Diagnostics')
crash_reporter_file = diag_group.new_file('CrashReporter.swift')
target.source_build_phase.add_file_reference(crash_reporter_file)

project.save

puts "Added CrashReporter.swift to project"

#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'LidarAPP' }

# Remove any existing broken ObjectCapture references
project.files.each do |file|
  if file.path && file.path.include?('ObjectCapture')
    file.remove_from_project
    puts "Removed existing reference: #{file.path}"
  end
end

# Find the main group
main_group = project.main_group.find_subpath('LidarAPP', true)

# Add ObjectCapture Service - use absolute file path
services_group = main_group.find_subpath('Services', true)

# Check if ObjectCapture group already exists
existing_oc_services = services_group.children.find { |c| c.display_name == 'ObjectCapture' }
existing_oc_services&.remove_from_project

object_capture_service_group = services_group.new_group('ObjectCapture', 'ObjectCapture')
object_capture_service_file = object_capture_service_group.new_file('ObjectCaptureService.swift')
target.source_build_phase.add_file_reference(object_capture_service_file)

# Add ObjectCapture View
presentation_group = main_group.find_subpath('Presentation', true)

# Check if ObjectCapture group already exists
existing_oc_presentation = presentation_group.children.find { |c| c.display_name == 'ObjectCapture' }
existing_oc_presentation&.remove_from_project

object_capture_view_group = presentation_group.new_group('ObjectCapture', 'ObjectCapture')
object_capture_view_file = object_capture_view_group.new_file('ObjectCaptureScanningView.swift')
target.source_build_phase.add_file_reference(object_capture_view_file)

project.save

puts "Added ObjectCapture files to project"

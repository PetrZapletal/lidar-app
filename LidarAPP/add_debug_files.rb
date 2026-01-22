#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find or create Debug group under Services
services_group = nil
project.main_group.recursive_children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == 'Services'
    services_group = child
    break
  end
end

unless services_group
  puts "ERROR: Could not find Services group"
  exit 1
end

# Find or create Debug group
debug_group = nil
services_group.children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == 'Debug'
    debug_group = child
    break
  end
end

unless debug_group
  debug_group = services_group.new_group('Debug', 'Debug')
  puts "Created Debug group"
end

# Files to add
debug_files = [
  'DebugSettings.swift',
  'DepthFrame.swift',
  'RawDataPackager.swift',
  'RawDataUploader.swift',
  'DebugLogger.swift',
  'PerformanceMonitor.swift'
]

# Find target
target = project.targets.find { |t| t.name == 'LidarAPP' }
unless target
  puts "ERROR: Could not find LidarAPP target"
  exit 1
end

# Add each file
debug_files.each do |filename|
  # Check if file already exists in group
  exists = false
  debug_group.files.each do |file|
    if file.display_name == filename
      exists = true
      puts "#{filename} already exists in project"
      break
    end
  end

  next if exists

  # Add file reference
  file_ref = debug_group.new_file(filename)

  # Add to target
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added #{filename} to project and target"
end

project.save
puts "Project saved successfully"

#!/usr/bin/env ruby
# Add GaussianSplatRenderer.swift to Xcode project

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find main target
main_target = project.targets.find { |t| t.name == 'LidarAPP' }
unless main_target
  puts "Error: LidarAPP target not found"
  exit 1
end

# Find Rendering group
lidar_group = project.main_group.find_subpath('LidarAPP', true)
services_group = lidar_group.find_subpath('Services', true)
rendering_group = services_group.find_subpath('Rendering', true)

unless rendering_group
  puts "Creating Rendering group..."
  rendering_group = services_group.new_group('Rendering')
end

# Check if file already exists
file_path = 'Services/Rendering/GaussianSplatRenderer.swift'
existing_file = rendering_group.files.find { |f| f.path&.include?('GaussianSplatRenderer') }

if existing_file
  puts "GaussianSplatRenderer.swift already in project"
else
  # Add file reference
  file_ref = rendering_group.new_file('GaussianSplatRenderer.swift')
  puts "Added file reference: GaussianSplatRenderer.swift"

  # Add to Sources build phase
  sources_phase = main_target.source_build_phase
  sources_phase.add_file_reference(file_ref)
  puts "Added to Sources build phase"
end

# Save project
project.save
puts "Project saved successfully"

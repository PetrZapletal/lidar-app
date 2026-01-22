#!/usr/bin/env ruby
# Add CoreML model to Xcode project

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find main target
main_target = project.targets.find { |t| t.name == 'LidarAPP' }
unless main_target
  puts "Error: LidarAPP target not found"
  exit 1
end

# Find or create ML group under LidarAPP group
lidar_group = project.main_group.find_subpath('LidarAPP', true)

# Remove any existing ML group with wrong path
existing_ml_group = lidar_group.groups.find { |g| g.name == 'ML' }
if existing_ml_group
  puts "Removing existing ML group..."
  existing_ml_group.remove_from_project
end

# Create new ML group with correct path
ml_group = lidar_group.new_group('ML', 'ML')

# Add model file with correct relative path
model_file = ml_group.new_file('DepthAnythingV2SmallF16.mlpackage')
puts "Added model reference: ML/DepthAnythingV2SmallF16.mlpackage"

# Add to Copy Bundle Resources build phase
resources_phase = main_target.resources_build_phase

# Check if already added
already_added = resources_phase.files.any? { |f| f.display_name&.include?('DepthAnythingV2SmallF16') }
unless already_added
  resources_phase.add_file_reference(model_file)
  puts "Added to Copy Bundle Resources"
end

# Save project
project.save
puts "Project saved successfully"

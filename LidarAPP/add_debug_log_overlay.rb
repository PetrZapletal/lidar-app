#!/usr/bin/env ruby
# Add DebugLogOverlay.swift to Xcode project

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the target
target = project.targets.find { |t| t.name == 'LidarAPP' }

# Find the Scanning Views group
main_group = project.main_group
lidarapp_group = main_group.children.find { |g| g.display_name == 'LidarAPP' }
presentation_group = lidarapp_group.children.find { |g| g.display_name == 'Presentation' }
scanning_group = presentation_group.children.find { |g| g.display_name == 'Scanning' }
views_group = scanning_group.children.find { |g| g.display_name == 'Views' }

# Check if file already exists
existing = views_group.files.find { |f| f.display_name == 'DebugLogOverlay.swift' }
if existing
  puts "DebugLogOverlay.swift already exists in project"
  exit 0
end

# Add the file
file_path = 'LidarAPP/Presentation/Scanning/Views/DebugLogOverlay.swift'
file_ref = views_group.new_file(file_path)

# Add to target
target.add_file_references([file_ref])

project.save

puts "Added DebugLogOverlay.swift to project"

#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the Diagnostics group
diagnostics_group = nil
project.main_group.recursive_children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == 'Diagnostics'
    diagnostics_group = child
    break
  end
end

# If Diagnostics group not found, find Services group and create it
if diagnostics_group.nil?
  services_group = nil
  project.main_group.recursive_children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == 'Services'
      services_group = child
      break
    end
  end

  if services_group
    diagnostics_group = services_group.new_group('Diagnostics', 'Services/Diagnostics')
    puts "Created Diagnostics group"
  else
    puts "ERROR: Could not find Services group"
    exit 1
  end
end

# Check if AppDiagnostics.swift is already in the group
app_diagnostics_exists = false
diagnostics_group.files.each do |file|
  if file.display_name == 'AppDiagnostics.swift'
    app_diagnostics_exists = true
    puts "AppDiagnostics.swift already exists in project"
    break
  end
end

# Add AppDiagnostics.swift if not exists
unless app_diagnostics_exists
  file_ref = diagnostics_group.new_file('LidarAPP/Services/Diagnostics/AppDiagnostics.swift')

  # Add to target
  target = project.targets.find { |t| t.name == 'LidarAPP' }
  if target
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added AppDiagnostics.swift to project and target"
  end
end

project.save
puts "Project saved successfully"

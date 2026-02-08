require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find main group
main_group = project.main_group

# Find or create Core group
core_group = main_group.find_subpath('LidarAPP/Core', true)

# Create Mock group
mock_group = core_group.find_subpath('Mock', true) || core_group.new_group('Mock')

# Get main target
target = project.targets.find { |t| t.name == 'LidarAPP' }

# Add files
mock_files = [
  'LidarAPP/Core/Mock/MockDataProvider.swift',
  'LidarAPP/Core/Mock/MockARSessionManager.swift',
  'LidarAPP/Core/Mock/MockDataPreviewView.swift'
]

mock_files.each do |file_path|
  # Check if file already exists in project
  existing = mock_group.files.find { |f| f.path == File.basename(file_path) }
  next if existing
  
  file_ref = mock_group.new_file(file_path)
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
end

project.save
puts "Project saved successfully"

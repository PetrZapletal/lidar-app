#!/usr/bin/env ruby
# Fix MetalSplatter version requirement

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find MetalSplatter package reference and update version
project.root_object.package_references.each do |pkg|
  if pkg.respond_to?(:repositoryURL) && pkg.repositoryURL&.include?('MetalSplatter')
    puts "Found MetalSplatter package reference"
    pkg.requirement = {
      'kind' => 'upToNextMinorVersion',
      'minimumVersion' => '0.1.0'
    }
    puts "Updated version requirement to 0.1.0"
  end
end

project.save
puts "Project saved successfully"

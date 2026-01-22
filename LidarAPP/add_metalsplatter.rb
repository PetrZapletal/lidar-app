#!/usr/bin/env ruby
# Add MetalSplatter Swift Package to Xcode project

require 'xcodeproj'

project_path = 'LidarAPP.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find main target
main_target = project.targets.find { |t| t.name == 'LidarAPP' }
unless main_target
  puts "Error: LidarAPP target not found"
  exit 1
end

# Check if MetalSplatter is already added
existing_pkg = project.root_object.package_references.find { |pkg|
  pkg.respond_to?(:repositoryURL) && pkg.repositoryURL&.include?('MetalSplatter')
}

if existing_pkg
  puts "MetalSplatter already added to project"
  exit 0
end

# Add Swift Package Reference
pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref.repositoryURL = 'https://github.com/scier/MetalSplatter.git'
pkg_ref.requirement = {
  'kind' => 'upToNextMajorVersion',
  'minimumVersion' => '1.0.0'
}
project.root_object.package_references << pkg_ref
puts "Added MetalSplatter package reference"

# Add package product dependency to target
pkg_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
pkg_product.product_name = 'MetalSplatter'
pkg_product.package = pkg_ref

main_target.package_product_dependencies << pkg_product
puts "Added MetalSplatter product dependency to LidarAPP target"

# Save project
project.save
puts "Project saved successfully"
puts ""
puts "NOTE: Open Xcode and let it resolve the package dependencies."
puts "The package will be downloaded automatically."

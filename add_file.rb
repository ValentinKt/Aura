require 'xcodeproj'
project_path = 'Aura.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group1 = project.main_group.find_subpath(File.join('Aura', 'Views', 'Settings'), true)
file_ref1 = group1.new_file('WebsiteManagerView.swift')
target.add_file_references([file_ref1])

project.save

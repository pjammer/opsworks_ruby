# frozen_string_literal: true

def applications
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search. Chef Solo does not support search.')
  end
  search(:aws_opsworks_app)
end

def rdses
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search. Chef Solo does not support search.')
  end
  search(:aws_opsworks_rds_db_instance)
end

def fire_hook(name, options)
  raise ArgumentError 'context is missing' if options[:context].blank?

  Array.wrap(options[:items]).each do |item|
    item.send(name, options[:context])
  end
end

def www_group
  value_for_platform_family(
    'debian' => 'www-data'
  )
end

def create_deploy_dir(application, subdir = '/')
  dir = File.join(deploy_dir(application), subdir)
  directory dir do
    mode '0755'
    recursive true
    owner node['deployer']['user'] || 'root'
    group www_group
    not_if { File.directory?(dir) }
  end
  dir
end
def add_application_env(application)
  template "#{deploy_dir(application)}/shared/config/application.yml" do
    source "application.yml.erb"
    owner node['deployer']['user'] || 'root'
    group www_group
    mode "0660"
    variables :env => application['enrvironment']
  end
end
def deploy_dir(application)
  File.join('/', 'srv', 'www', application['shortname'])
end

def every_enabled_application
  node['deploy'].each do |deploy_app_shortname, deploy|
    drapplication = applications.detect { |app| app['shortname'] == deploy_app_shortname }
    next unless drapplication
    yield drapplication, deploy
  end
end

def every_enabled_rds
  rdses.each do |rds|
    yield rds
  end
end

def perform_bundle_install(release_path)
  bundle_install File.join(release_path, 'Gemfile') do
    deployment true
    without %w(development test)
  end
end

def prepare_recipe
  Chef::Log.info("I am in prepare_recipe")
  node.default['deploy'] = Hash[applications.map { |app| [app['shortname'], {}] }].merge(node['deploy'] || {})
  Chef::Log.info("I am in prepare_recipe seccond last line")
  apps_not_included.each do |app_for_removal|
    node.rm('deploy', app_for_removal)
  end
end

def apps_not_included
  return [] if node['applications'].blank?
  node['deploy'].keys.select { |app_name| !node['applications'].include?(app_name) }
end

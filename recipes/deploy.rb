# frozen_string_literal: true

prepare_recipe

include_recipe 'opsworks_ruby::configure'

every_enabled_application do |application, deploy|
  databases = []
  every_enabled_rds do |rds|
    databases.push(Drivers::Db::Factory.build(application, node, rds: rds))
  end

  databases = [Drivers::Db::Factory.build(application, node)] if rdses.blank?

  scm = Drivers::Scm::Factory.build(application, node)
  framework = Drivers::Framework::Factory.build(application, node)
  appserver = Drivers::Appserver::Factory.build(application, node)
  worker = Drivers::Worker::Factory.build(application, node)
  webserver = Drivers::Webserver::Factory.build(application, node)

  fire_hook(:before_deploy, context: self, items: databases + [scm, framework, appserver, worker, webserver])

  deploy application['shortname'] do
    deploy_to deploy_dir(application)
    user node['deployer']['user'] || 'root'
    group www_group
    rollback_on_error true
    environment application['environment'].merge(framework.out[:deploy_environment])
    keep_releases deploy[:keep_releases]
    create_dirs_before_symlink(
      (node['defaults']['deploy']['create_dirs_before_symlink'] + Array.wrap(deploy[:create_dirs_before_symlink])).uniq
    )
    purge_before_symlink(
      (node['defaults']['deploy']['purge_before_symlink'] + Array.wrap(deploy[:purge_before_symlink])).uniq
    )
    # putting application.yml creation here
    template File.join(deploy_dir(application), 'shared', 'config', 'application.yml') do
      source 'application.yml.erb'
      mode '0660'
      owner node['deployer']['user'] || 'root'
      group www_group
      variables(env: [])
    end

    #continue with original code
    symlink_before_migrate deploy[:symlink_before_migrate]
    symlinks(node['defaults']['deploy']['symlinks'].merge(deploy[:symlinks] || {}))

    scm.out.each do |scm_key, scm_value|
      send(scm_key, scm_value) if respond_to?(scm_key)
    end

    [appserver, webserver].each do |server|
      server.notifies[:deploy].each do |config|
        notifies config[:action],
                 config[:resource].respond_to?(:call) ? config[:resource].call(application) : config[:resource],
                 config[:timer]
      end
    end

    migration_command(framework.out[:migration_command])
    migrate framework.out[:migrate]
    before_migrate do
      execute "cd #{release_path} && RAILS_ENV=production bundle install --without=development test"
      # bundle_install File.join(release_path, 'Gemfile') do
      #   deployment true
      #   without %w(development test)
      # end

      fire_hook(:deploy_before_migrate, context: self,
                                        items: databases + [scm, framework, appserver, worker, webserver])

      run_callback_from_file(File.join(release_path, 'deploy', 'before_migrate.rb'))
    end

    before_symlink do
      unless framework.out[:migrate]
        execute "cd #{release_path} && RAILS_ENV=production bundle install --without=development test"
        # bundle_install File.join(release_path, 'Gemfile') do
        #   deployment true
        #   without %w(development test)
        # end
      end

      fire_hook(:deploy_before_symlink, context: self,
                                        items: databases + [scm, framework, appserver, worker, webserver])

      run_callback_from_file(File.join(release_path, 'deploy', 'before_symlink.rb'))
    end

    before_restart do
      directory File.join(release_path, '.git') do
        recursive true
        action :delete
      end if scm.out[:remove_scm_files]

      fire_hook(:deploy_before_restart, context: self,
                                        items: databases + [scm, framework, appserver, worker, webserver])

      run_callback_from_file(File.join(release_path, 'deploy', 'before_restart.rb'))
    end

    after_restart do
      fire_hook(:deploy_after_restart, context: self,
                                       items: databases + [scm, framework, appserver, worker, webserver])

      run_callback_from_file(File.join(release_path, 'deploy', 'after_restart.rb'))
    end
  end

  fire_hook(:after_deploy, context: self, items: databases + [scm, framework, appserver, worker, webserver])
end

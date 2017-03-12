# frozen_string_literal: true
module Drivers
  module Webserver
    class Nginx < Drivers::Webserver::Base
      adapter :nginx
      allowed_engines :nginx
      output filter: [
        :build_type, :client_body_timeout, :client_header_timeout, :client_max_body_size, :dhparams, :keepalive_timeout,
        :log_dir, :proxy_read_timeout, :proxy_send_timeout, :send_timeout, :ssl_for_legacy_browsers,
        :extra_config, :extra_config_ssl
      ]
      notifies :deploy, action: :reload, resource: 'service[nginx]', timer: :delayed
      notifies :undeploy, action: :reload, resource: 'service[nginx]', timer: :delayed

      def raw_out
        output = node['defaults']['webserver'].merge(node['nginx']).merge(
          node['deploy'][app['shortname']]['webserver'] || {}
        ).symbolize_keys
        output[:extra_config_ssl] = output[:extra_config] if output[:extra_config_ssl] == true
        output
      end

      def setup(context)
        node.default['nginx']['install_method'] = out[:build_type].to_s == 'source' ? 'source' : 'package'
        recipe = out[:build_type].to_s == 'source' ? 'source' : 'default'
        #context.include_recipe("nginx::default")
        # Chef::Log.info("ss; nginx in recipe")
        # Chef::Log.info("i am here in setup")
        # Chef::Log.info("#{node.default['nginx']['install_method']}")
        # Chef::Log.info("#{recipe.inspect}")
        # Chef::Log.info(context.inspect)
        # Chef::Log.info("end context")
#        define_service(context, :start)
      end

      def configure(context)
        add_ssl_directory(context)
        add_ssl_item(context, :private_key)
        add_ssl_item(context, :certificate)
        add_ssl_item(context, :chain)
        add_dhparams(context)

        add_unicorn_config(context) if Drivers::Appserver::Factory.build(app, node).adapter == 'unicorn'
        enable_appserver_config(context)
      end

      def before_deploy(context)
        define_service(context)
      end
      alias before_undeploy before_deploy

      private

      def define_service(context, default_action = :nothing)
        context.service 'nginx' do
          supports status: true, restart: true, reload: true
          action default_action
        end
      end

      def add_ssl_directory(context)
        context.directory '/etc/nginx/ssl' do
          owner 'root'
          group 'root'
          mode '0700'
        end
      end

      def add_ssl_item(context, name)
        key_data = app[:ssl_configuration].try(:[], name)
        return if key_data.blank?
        extensions = { private_key: 'key', certificate: 'crt', chain: 'ca' }

        context.template "/etc/nginx/ssl/#{app[:domains].first}.#{extensions[name]}" do
          owner 'root'
          group 'root'
          mode name == :private_key ? '0600' : '0644'
          source 'ssl_key.erb'
          variables key_data: key_data
        end
      end

      def add_dhparams(context)
        dhparams = out[:dhparams]
        return if dhparams.blank?

        context.template "/etc/nginx/ssl/#{app[:domains].first}.dhparams.pem" do
          owner 'root'
          group 'root'
          mode '0600'
          source 'ssl_key.erb'
          variables key_data: dhparams
        end
      end

      def add_unicorn_config(context)
        deploy_to = deploy_dir(app)
        application = app
        output = out

        context.template "/etc/nginx/sites-available/#{app['shortname']}" do
          owner 'root'
          group 'root'
          mode '0644'
          source 'unicorn.nginx.conf.erb'
          variables application: application, deploy_dir: deploy_to, out: output
        end
      end

      def enable_appserver_config(context)
        application = app
        context.link "/etc/nginx/sites-enabled/#{application['shortname']}" do
          to "/etc/nginx/sites-available/#{application['shortname']}"
        end
      end
    end
  end
end

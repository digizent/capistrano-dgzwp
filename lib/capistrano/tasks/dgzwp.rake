
set :site_url, 'change.me'
set :site_title, 'Automatic WP Deploys'
set :admin_user, 'admin'
set :admin_password, 'password'
set :admin_email, 'rperez@digizent.com'
set :first_install_plugins, %w{wp-migrate-db-pro wp-migrate-db-pro-cli wp-migrate-db-pro-media-files}

set :migrate_db_action, 'push'
set :push_migrate_profile, nil
set :pull_migrate_profile, nil

namespace :wordpress do

  desc "Activates plugins necessary for the deployment process"
  task :activate_deployment_plugins do
    on roles(:web) do
      within release_path do
        info 'Activating required plugins'
        plugins = fetch(:first_install_plugins)
        plugins.each do |plugin|
          execute :wp, :plugin, :activate, plugin
        end
      end
    end
  end

  namespace :db do

    desc "Install WordPress DB"
    task :install do
      on roles(:web) do
        within release_path do
          info 'Installing initial DB'
          execute :wp, :core, :install, "--url=\"#{fetch(:site_url)}\" --title=\"#{fetch(:site_title)}\" --admin_user=\"#{fetch(:admin_user)}\" --admin_password=\"#{fetch(:admin_password)}\" --admin_email=\"#{fetch(:admin_email)}\""
          execute :touch, "#{shared_path}/db_installed"
        end
      end
    end

    desc "Migrates a DB from one environment to another"
    task :migrate do
      on roles(:web) do
        info "Migrating DB"
        within release_path do
          info "Checking if the DB has already been installed"
          if test "[ -f #{shared_path}/db_installed ]"
            info "Proceeding to migrate the DB according to settings"
            Rake::Task["wordpress:db:#{fetch(:migrate_db_action)}"].invoke
          else
            info "The DB has not been installed yet. Proceeding to install it"
            Rake::Task["wordpress:db:install"].invoke
            Rake::Task["wordpress:activate_deployment_plugins"].invoke
          end
        end
      end
    end

    desc "Pull a remote environment DB to the deployed environment"
    task :pull do
      on roles(:web) do
        within release_path do
          pull_migrate_profile = fetch(:pull_migrate_profile)
          info "Pulling remote environment DB to the deployed environment - #{pull_migrate_profile}"
          begin
            execute :wp, :wpmdb, :migrate, pull_migrate_profile
          rescue
            error_message = "
            WP Migrate DB Pro Error:
            Check if the plugin is correctly installed on each environment
            -> Check that Migrate DB Pro is installed and activate
            -> Check that the plugin is set to accept Push/Pull requests
            -> Check that all environments have a licence key
            -> Check that the plugin is updated
            -> Check that the Migrate DB Pro CLI extension is installed and active"
            error error_message
            raise error_message
          end
        end
      end
    end

    desc "Push the local environment DB to the deployed environment"
    task :push do
      on roles(:web) do
        run_locally do
          push_migrate_profile = fetch(:push_migrate_profile)
          info "Pushing the local environment DB to the deployed environment - #{push_migrate_profile}"
          begin
            execute :wp, :wpmdb, :migrate, push_migrate_profile
          rescue
            error_message = "
            WP Migrate DB Pro Error:
            Check if the plugin is correctly installed on each environment
            -> Check that Migrate DB Pro is installed and activate
            -> Check that the plugin is set to accept Push/Pull requests
            -> Check that all environments have a licence key
            -> Check that the plugin is updated
            -> Check that the Migrate DB Pro CLI extension is installed and active"
            error error_message
            raise error_message
          end
        end
      end
    end

    desc "Backs up the current DB"
    task :backup do
      on roles(:web) do
        within release_path do
          info "Backing up current DB"
          execute :wp, :db, :export, "#{release_path}/db.sql"
          execute :chmod, 660, "#{release_path}/db.sql"
        end
      end
    end

    desc "Roll back to the previous DB"
    task :rollback do
      on roles(:web) do
        within release_path do
          if test "[ -f #{release_path}/db.sql ]"
            info "Removing all DB tables"
            execute :wp, :db, :reset, "--yes"
            info "Importing previous DB"
            execute :wp, :db, :import, "#{release_path}/db.sql"
          else
            info "A previous DB doesn't exist. Nothing was migrated"
            info "Please perform this operation manually"
          end
        end
      end
    end

  end

end

# after 'deploy:started', 'wordpress:db:backup'
after 'deploy:updated', 'wordpress:db:migrate'
after 'deploy:reverted', 'wordpress:db:rollback'
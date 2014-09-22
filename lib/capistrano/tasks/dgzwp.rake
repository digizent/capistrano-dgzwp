set :site_url, 'set-me.mysitebuild.com'
set :site_title, 'Automatic WP Deploys'
set :admin_user, 'admin'
set :admin_password, 'password'
set :admin_email, 'rperez@digizent.com'
set :first_install_plugins, %w{wp-migrate-db-pro wp-migrate-db-pro-cli wp-migrate-db-pro-media-files}

set :migrate_db_action, 'push'
set :migrate_db_profile_id, '1'

namespace :wordpress do

  namespace :db do

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
            Rake::Task["wordpress:db:activate_deployment_plugins"].invoke
          end
        end
      end
    end

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

    desc "Pull a remote environment DB to the deployed environment"
    task :pull do
      on roles(:web) do
        within release_path do
          info "Pulling remote environment DB to the deployed environment"
          execute :wp, :wpmdb, :migrate, fetch(:migrate_db_profile_id)
        end
      end
    end

    desc "Push the local environment DB to the deployed environment"
    task :push do
      on roles(:web) do
        run_locally do
          info "Pushing the local environment DB to the deployed environment"
          execute :wp, :wpmdb, :migrate, fetch(:migrate_db_profile_id)
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
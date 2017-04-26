namespace :pm do
  namespace :test do
    desc 'setup necessary scaffoliding for running policy machine specs'
    task :prepare, [:db_type] do |t, args|
      Dir.chdir('./test') do
        db_type = args[:db_type] || 'postgresql'
        `rm -rf testapp`
        `bundle exec rails new testapp -f -d #{db_type} -m ./template.rb  --skip-keeps --skip-spring  --skip-git`
      end

      Dir.chdir('./test/testapp') do
        `bundle install`

        `bundle exec rails generate the_policy_machine:add_initial_policy_machine_tables -f`
        `bundle exec rails generate the_policy_machine:add_logical_links_table -f`
        `bundle exec rails generate the_policy_machine:update_policy_element_associations_table -f`
        FileUtils.cp('../add_test_columns_migration.rb', './db/migrate/99999999999999_add_test_columns.rb')

        `bundle exec rake db:drop:all db:create db:migrate db:test:prepare`
      end
    end
  end
end

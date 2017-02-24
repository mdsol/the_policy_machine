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
        `bundle exec rails generate policy_machine -f`
        #TODO  replace with another generator or equivalent
        FileUtils.cp('../migration.rb', './db/migrate/99999999999999_add_test_columns.rb')
        `bundle exec rake db:drop:all db:create db:migrate db:test:prepare`
      end
    end
  end
end

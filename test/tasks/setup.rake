namespace :pm do
  namespace :testing do
    desc 'setup necessary scaffoliding for running policy machine specs'
    task :setup, [:db_type] do |t, args|
      Dir.chdir('./test') do
        `bundle exec rails new testapp -f -d #{args[:db_type] || 'postgresql'} -m ./template.rb  --skip-keeps --skip-spring  --skip-git`
      end

      Dir.chdir('./test/testapp') do
        `bundle install`
        `bundle exec rails g policy_machine -f`
        `bundle exec rails g migration AddColorToPolicyElements color:string`
        `bundle exec rake db:drop:all db:create db:migrate db:test:prepare`
      end
    end
  end
end

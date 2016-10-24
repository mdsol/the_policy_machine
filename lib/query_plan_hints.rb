module QueryPlanHints

  # Method decorator to ensure not using a specific query plan
  # during postgres privilege deriviations
  def disable_mergejoin(method_name)
    if ActiveRecord::Base.connection.is_a? ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
      function = instance_method(method_name)

      define_method(method_name) do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute("set local enable_mergejoin = false")
          function.bind(self).call
        end
      end
    end
  end
end

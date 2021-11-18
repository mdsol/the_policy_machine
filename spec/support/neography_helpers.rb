# This file contains helper methods to manage a neo4j db via neography, for testing purposes.

def neo4j_exists?
  system('test -d neo4j')
end

def start_neo4j
  # Start the server
  # TODO:  sometimes the server doesn't start before tests start to run.  Fix!
  # TODO:  probably have to make a separate connection for test db so as not to wipe out dev data.
  puts 'STARTING NEO4J SERVER...'
  `neo4j/bin/neo4j start`
end

def stop_neo4j
  puts 'STOPPING NEO4J SERVER...'
  `neo4j/bin/neo4j stop`
end

def reset_neo4j
  # Reset the database
  puts 'RESETTING NEO4J DB...'
  FileUtils.rm_rf('neo4j/data/graph.db')
  FileUtils.mkdir('neo4j/data/graph.db')

  # Remove log files
  puts 'REMOVING NEO4J LOGS...'
  FileUtils.rm_rf('neo4j/data/log')
  FileUtils.mkdir('neo4j/data/log')
end

# Clear all nodes except start node. Should be run before each unit test.
def clean_neo4j
  neo_connection.execute_query('START n0=node(0),nx=node(*) MATCH n0-[r0?]-(),nx-[rx?]-() WHERE nx <> n0 DELETE r0,rx,nx')
end

def neo_connection
  @neo ||= Neography::Rest.new
end

# SquirrelDB Ruby SDK

Official Ruby client for SquirrelDB.

## Installation

Add to your Gemfile:

```ruby
gem 'squirreldb'
```

Or install directly:

```bash
gem install squirreldb
```

## Quick Start

```ruby
require 'squirreldb'

# Connect to database
db = SquirrelDB::Client.new(
  host: 'localhost',
  port: 8080,
  token: ENV['SQUIRRELDB_TOKEN']
)

# Insert a document
user = db.table('users').insert(
  name: 'Alice',
  email: 'alice@example.com'
)
puts "Created user: #{user['id']}"

# Query documents
active_users = db.table('users')
  .filter('u => u.status === "active"')
  .run

# Subscribe to changes
db.table('messages').changes do |change|
  puts "Change: #{change['operation']} - #{change['newValue']}"
end
```

## Documentation

Visit [squirreldb.com/docs/sdks](https://squirreldb.com/docs/sdks) for full documentation.

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.

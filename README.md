# Stairstep

📶 Stairstep is a Ruby gem that simplifies the process of deploying Rails applications to Heroku. It provides a streamlined workflow for deploying and promoting applications across different Heroku environments. 

### Table of Contents

- [Setup](#setup)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Configuration](#configuration)
- [Usage](#usage)
- [Code of Conduct](#code-of-conduct)
- [License](#license)

## Setup

### Prerequisites

Before installing Stairstep, ensure you have:

1. Ruby 3.2.0 or higher installed
2. Git installed and configured
3. Heroku CLI installed and authenticated (`heroku login`)
4. Heroku Builds plugin* installed: `heroku plugins:install @heroku-cli/heroku-builds`
5. A Rails application with a Git repository
6. Heroku applications and pipeline set up

### Installation

Add this line to your application's Gemfile:

```ruby
gem 'stairstep'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install stairstep
```

### Configuration

You may add an **optional** `stairstep.yml` file in the application's `config/` directory to customize Stairstep's behavior.

#### Pipeline name

You may optionally specify the name of the pipeline for deploys. By default, this is the name of the GitHub repository.

#### App names

You may optionally specify app names per remote. This will default to the hyphenated combination of the pipeline name and the remote name (e.g. syrup-demo).

#### Hooks

Top level config keys may be the name of a Heroku deploy hook. Each key within a hook is a Heroku CLI command. Each value is an array of parameters for that command.

- `before_deploy` Runs right before the deploy (during maintenance mode)
- `after_deploy` Runs at the very end (after maintenance mode)

#### Example Configuration

```yaml
---
pipeline: wibble-wobble

demo:
  app: wib-wob-demo
staging:
  app: wib-wob-staging
production:
  app: wibble-wobble-prod
before_deploy:
  config:unset:
    - MINOR_VERSION
  config:set:
    - DEPLOY_TIME=`date +%s`
after_deploy:
  run:
    - rails pusher:new_release rollbar:source_maps
    - rails db:seed:static
```

## Usage

Stairstep provides two main commands: `deploy` and `promote`.

For information on available commands and options, use:

```bash
$ stairstep --help
$ stairstep deploy --help
$ stairstep promote --help
```

### Deploying to an Environment

To deploy your application to a specific Heroku environment:

```bash
$ stairstep deploy ENVIRONMENT [options]
```

For detailed `deploy` documentation, [see here](https://srpatx.atlassian.net/wiki/external/YjgzYzU0N2Q3OWYwNDMwNzgyODVlZTVmNjRmNDM1Zjk#deploy).

### Promoting Between Environments

To promote your application from one environment to another:

```bash
$ stairstep promote ENVIRONMENT [options]
```

For detailed `promote` documentation, [see here](https://srpatx.atlassian.net/wiki/external/YjgzYzU0N2Q3OWYwNDMwNzgyODVlZTVmNjRmNDM1Zjk#promote).

## Code of Conduct

Everyone interacting in the Stairstep project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](./CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).


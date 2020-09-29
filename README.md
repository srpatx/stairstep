# Stairstep

Deploying

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Configuration

Add a `config/stairstep.yml` file to the application. Each key within a hook is
a Heroku CLI command. Each value is an array of invocations for that command.

### Hooks
- `before_deploy` Runs right before the deploy (during maintenance mode)
- `after_deploy` Runs at the very end (after maintenance mode)

### Example

```yaml
---
before_deploy:
  config:unset:
    - MINOR_VERSION
after_deploy:
  run:
    - rails pusher:new_release rollbar:source_maps
```


## Code of Conduct

Everyone interacting in the Stairstep project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](./CODE_OF_CONDUCT.md).


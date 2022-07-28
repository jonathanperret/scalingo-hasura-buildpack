# Scalingo Hasura Buildpack

This [buildpack](https://doc.scalingo.com/platform/deployment/buildpacks/custom)
allows deploying [Hasura GraphQL engine](https://github.com/hasura/graphql-engine)
on [Scalingo](https://scalingo.com).

## Usage

* Create a Scalingo application.
* In the app's environment, set `BUILDPACK_URL=https://github.com/ut7/scalingo-hasura-buildpack`

### Directories

The buildpack expects the standard Hasura directories at the root of the source:
* `metadata`
* `migrations`
* `seeds`

The metadata and migrations, if present, will be applied during each deployment
in a `postdeploy` hook.

The seeds will only be applied if `HASURA_GRAPHQL_SEED_ON_DEPLOY` is set to
`true` (see below).

### Environment variables

At a minimum, the Hasura GraphQL engine itself will require the following
environment variables to be set on your application:
* `HASURA_GRAPHQL_DATABASE_URL`: assuming you have provisioned a PostgreSQL
  add-on, a sensible value would be `$SCALINGO_POSTGRESQL_URL`
* `HASURA_GRAPHQL_ADMIN_SECRET`: set this to a secret string.

In addition to the environment variables recognized by Hasura GraphQL engine,
this buildpack can be controlled using these variables:

* `HASURA_VERSION`: set this to the version of the GraphQL engine you want to
  deploy, e.g. `v2.8.3`
* `HASURA_GRAPHQL_SEED_ON_DEPLOY`: if set to `true`, the postdeploy hook will
  run `hasura seed apply`. If your seed scripts are destructive, you probably
  do not want to run this in production.
* `HASURA_CONNECTION_POOL_SETTINGS`: set this to a YAML fragment and it will
  be merged into the `configuration.connection_info.pool_settings` key of the
  first database defined in `metadata/databases/databases.yaml`.
  For example, set this variable to `{"max_connections":2, "idle_timeout":5}`
  to reduce the default pool size for e.g. a review environment with minimal
  resources. Note that since the connection settings are stored in the
  metadata, and the metadata is only uploaded to the database upon application
  deployment, a change in this variable will require a redeployment of your
  application to take effect.

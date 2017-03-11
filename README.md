[![Dependency Status](https://gemnasium.com/badges/github.com/kessler-oliveira/PGRA.svg)](https://gemnasium.com/github.com/kessler-oliveira/PGRA)

# PGRA - PostgreSQL Rewrite Advisor

PostgreSQL Rewrite Advisor is an automated interactive tool for SQL query optimization through PostgreSQL rewrite.

## Getting Started

``` bash
$ git clone --depth 1 https://github.com/kessler-oliveira/PGRA.git
```

## Installation

### Use bundler to install gems

``` bash
$ bundle install
```

### Start the server

``` bash
$ rackup
```

ou

``` bash
$ bundle exec shotgun config.ru
```

## Using

PostgreSQL Rewrite Advisor is a modular prototype, in this moments it has just two implementated modules. 
With this modules is possible try optimize querys problems with nested subqueries in the FROM clause and SELECT cluase.
For using you need create a connection of your database, connect in and send a querys in the form to try to optimization.